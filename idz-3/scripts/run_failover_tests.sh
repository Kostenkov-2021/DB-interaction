#!/usr/bin/env sh
set -eu

export MSYS_NO_PATHCONV=1

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
if command -v cygpath >/dev/null 2>&1; then
    COMPOSE_FILE="$(cygpath -w "$COMPOSE_FILE")"
fi
CHECKS_DIR="$ROOT_DIR/checks"
mkdir -p "$CHECKS_DIR"

dc() {
    docker compose -f "$COMPOSE_FILE" "$@"
}

ch() {
    node="$1"
    shift
    dc exec -T "$node" clickhouse-client "$@"
}

keeper_cmd() {
    node="$1"
    command="$2"
    dc exec -T "$node" bash -lc "exec 3<>/dev/tcp/127.0.0.1/9181; printf '${command}\n' >&3; timeout 2 cat <&3 || true"
}

section() {
    printf '\n===== %s =====\n' "$1"
}

wait_clickhouse() {
    node="$1"
    i=1
    until ch "$node" --query "SELECT 1" >/dev/null 2>&1; do
        if [ "$i" -gt 60 ]; then
            echo "Узел ClickHouse $node не перешел в состояние готовности" >&2
            exit 1
        fi
        i=$((i + 1))
        sleep 2
    done
}

sync_replica() {
    node="$1"
    ch "$node" --query "SYSTEM SYNC REPLICA idz3.events" >/dev/null
}

cluster_counts() {
    ch clickhouse1 --query "
    SELECT
        hostName() AS host,
        count() AS rows,
        sum(cityHash64(event_time, event_type, user_id, payload)) AS data_hash
    FROM clusterAllReplicas('idz3_cluster', idz3.events)
    GROUP BY host
    ORDER BY host
    FORMAT PrettyCompact;
    "
}

replicas_status_to_file() {
    node="$1"
    file="$2"
    ch "$node" --query "
    SELECT
        database, table, replica_name,
        is_leader, total_replicas, active_replicas,
        queue_size, inserts_in_queue, merges_in_queue,
        log_pointer, last_queue_update
    FROM system.replicas
    WHERE database = 'idz3' AND table = 'events'
    FORMAT Vertical;
    " > "$file"
}

dc up -d
wait_clickhouse clickhouse1
wait_clickhouse clickhouse2
wait_clickhouse clickhouse3

ch clickhouse1 --multiquery --queries-file /sql/01_create_table.sql
ch clickhouse1 --query "TRUNCATE TABLE idz3.events ON CLUSTER idz3_cluster SYNC"
ch clickhouse1 --multiquery --queries-file /sql/02_insert_data.sql
sync_replica clickhouse1
sync_replica clickhouse2
sync_replica clickhouse3

{
    section "keeper1 ruok"
    keeper_cmd keeper1 ruok
    section "keeper1 mntr"
    keeper_cmd keeper1 mntr
    section "keeper2 mntr"
    keeper_cmd keeper2 mntr
    section "keeper3 mntr"
    keeper_cmd keeper3 mntr
} > "$CHECKS_DIR/keeper_health.txt"

replicas_status_to_file clickhouse1 "$CHECKS_DIR/replicas_status_node1.txt"
replicas_status_to_file clickhouse2 "$CHECKS_DIR/replicas_status_node2.txt"
replicas_status_to_file clickhouse3 "$CHECKS_DIR/replicas_status_node3.txt"

{
    section "начальная консистентность после 150000 строк"
    cluster_counts
} > "$CHECKS_DIR/replication_initial_consistency.txt"

{
    section "A1 остановка реплики 3"
    dc stop clickhouse3
    section "A2 вставка 20000 строк в реплику 1"
    dc exec -T clickhouse1 sh /scripts/generate_events.sh 20000 experiment_a 200000
    section "A3 реплика 2 получила данные"
    sync_replica clickhouse2
    ch clickhouse2 --query "SELECT hostName() AS host, count() AS rows FROM idz3.events FORMAT PrettyCompact"
    section "A4 запуск реплики 3 и фиксация replication_queue во время догоняющей синхронизации"
    dc start clickhouse3
    wait_clickhouse clickhouse3
    ch clickhouse3 --query "SYSTEM STOP REPLICATION QUEUES idz3.events" >/dev/null
    dc exec -T clickhouse1 sh /scripts/generate_events.sh 5000 experiment_a_queue_capture 250000
    sleep 2
    ch clickhouse3 --query "SELECT * FROM system.replication_queue WHERE database = 'idz3' AND table = 'events' FORMAT Vertical" > "$CHECKS_DIR/replication_queue.txt"
    ch clickhouse3 --query "SYSTEM START REPLICATION QUEUES idz3.events" >/dev/null
    sync_replica clickhouse3
    section "A5 очередь реплики 3 пуста"
    ch clickhouse3 --query "SELECT replica_name, queue_size, inserts_in_queue, merges_in_queue FROM system.replicas WHERE database = 'idz3' AND table = 'events' FORMAT PrettyCompact"
    section "A6 все реплики совпадают"
    cluster_counts
} > "$CHECKS_DIR/experiment_a.txt" 2>&1

{
    section "B1 остановка keeper 3"
    dc stop keeper3
    section "B2 кворум жив: keeper1/keeper2 mntr"
    keeper_cmd keeper1 mntr
    keeper_cmd keeper2 mntr
    section "B3 вставка работает при 2 из 3 узлов Keeper"
    dc exec -T clickhouse1 sh /scripts/generate_events.sh 10000 experiment_b_quorum 300000
    sync_replica clickhouse1
    section "B4 остановка keeper 2: кворум потерян"
    dc stop keeper2
    section "B5 вставка без кворума должна завершиться ошибкой"
    set +e
    dc exec -T clickhouse1 sh /scripts/generate_events.sh 1000 experiment_b_no_quorum 400000
    rc="$?"
    set -e
    echo "insert_exit_code=$rc"
    section "B6 локальный SELECT продолжает работать"
    ch clickhouse1 --query "SELECT hostName() AS host, count() AS rows FROM idz3.events FORMAT PrettyCompact"
    section "B7 восстановление кворума Keeper"
    dc start keeper2 keeper3
} > "$CHECKS_DIR/experiment_b.txt" 2>&1

wait_clickhouse clickhouse1

{
    section "C1 остановка реплики 2"
    dc stop clickhouse2
    section "C2 вставка строк через реплику 1"
    dc exec -T clickhouse1 sh /scripts/generate_events.sh 15000 experiment_c 500000
    section "C3 запуск реплики 2 и синхронизация"
    dc start clickhouse2
    wait_clickhouse clickhouse2
    sync_replica clickhouse2
    section "C4 детерминированный журнал Keeper предотвращает конфликты"
    ch clickhouse2 --query "
    SELECT
        replica_name,
        queue_size,
        zookeeper_path,
        replica_path,
        columns_version
    FROM system.replicas
    WHERE database = 'idz3' AND table = 'events'
    FORMAT Vertical;
    "
    section "C5 все реплики имеют одинаковое количество строк и хеш"
    cluster_counts
} > "$CHECKS_DIR/experiment_c.txt" 2>&1

echo "Проверки отказоустойчивости сохранены в $CHECKS_DIR"
