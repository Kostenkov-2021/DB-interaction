#!/usr/bin/env sh
set -eu

CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"
CHECK_DIR="${1:-/checks}"

mkdir -p "$CHECK_DIR"

"$CLIENT" --query "
SELECT
    cluster,
    shard_num,
    replica_num,
    host_name,
    port,
    is_local
FROM system.clusters
WHERE cluster = 'production'
ORDER BY shard_num, replica_num
FORMAT TSVWithNames
" > "$CHECK_DIR/cluster_status.txt"

"$CLIENT" --multiquery > "$CHECK_DIR/data_distribution.txt" <<'SQL'
SELECT 'Rows on every replica' AS section;
SELECT
    hostName() AS node,
    count() AS rows
FROM clusterAllReplicas('production', default.metrics_local)
GROUP BY node
ORDER BY node
FORMAT TSVWithNames;

SELECT 'Rows on one replica per shard' AS section;
SELECT
    hostName() AS shard_node,
    count() AS rows
FROM cluster('production', default.metrics_local)
GROUP BY shard_node
ORDER BY shard_node
FORMAT TSVWithNames;

SELECT 'Shard balance via one replica per shard' AS section;
SELECT
    _shard_num,
    count() AS rows,
    round(rows / sum(rows) OVER (), 4) AS ratio
FROM default.metrics_distributed
GROUP BY _shard_num
ORDER BY _shard_num
FORMAT TSVWithNames;
SQL

"$CLIENT" --query "
SELECT
    hostName() AS node,
    database,
    table,
    replica_name,
    is_leader,
    is_readonly,
    absolute_delay,
    queue_size,
    inserts_in_queue,
    merges_in_queue
FROM clusterAllReplicas('production', system.replicas)
WHERE database = 'default' AND table = 'metrics_local'
ORDER BY node, replica_name
FORMAT TSVWithNames
" > "$CHECK_DIR/replication_status.txt"

"$CLIENT" --multiquery --queries-file /sql/02_test_queries.sql > "$CHECK_DIR/distributed_queries.txt"

{
    echo "Nginx health before stopping replica"
    wget -qO- "http://nginx:8123/?query=SELECT%20hostName()%20FORMAT%20TSV"
    echo
    echo "Stop ch-s1-r2 from host and rerun this command to document failover:"
    echo "docker compose stop ch-s1-r2"
    echo "for i in 1 2 3 4 5; do curl -s 'http://localhost:18123/?query=SELECT%20hostName()%20FORMAT%20TSV'; done"
    echo "docker compose start ch-s1-r2"
} > "$CHECK_DIR/nginx_failover.txt"

cat > "$CHECK_DIR/grafana_screenshots_NOT_ALLOWED.md" <<'EOF'
# Grafana

Скриншоты запрещены стратегией задания. Дашборд экспортирован в JSON:

- `monitoring/dashboards/clickhouse.json`
- provisioning: `monitoring/provisioning/datasources.yml`, `monitoring/provisioning/dashboards.yml`
EOF
