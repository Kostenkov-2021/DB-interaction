#!/usr/bin/env sh
set -eu

COMPOSE="${COMPOSE:-docker compose}"
CHECK_DIR="${CHECK_DIR:-./checks}"
OUT="$CHECK_DIR/fault_scenarios.txt"

mkdir -p "$CHECK_DIR"

query_lb() {
    $COMPOSE exec -T nginx wget -T 5 -qO- "http://127.0.0.1:8123/?query=$1" || true
}

query_node() {
    $COMPOSE exec -T ch-s1-r1 clickhouse-client --query "$1" || true
}

{
    echo "# Fault injection"
    date
    echo

    echo "## 1. Потеря реплики ch-s1-r2"
    echo "Command: docker compose stop ch-s1-r2"
    $COMPOSE stop ch-s1-r2
    sleep 5
    echo "Query via nginx:"
    query_lb "SELECT%20hostName()%2C%20count()%20FROM%20default.metrics_distributed%20FORMAT%20TSV"
    echo "Restore: docker compose start ch-s1-r2"
    $COMPOSE start ch-s1-r2
    sleep 10
    echo

    echo "## 2. Потеря шарда ch-s2-r1 + ch-s2-r2"
    echo "Command: docker compose stop ch-s2-r1 ch-s2-r2"
    $COMPOSE stop ch-s2-r1 ch-s2-r2
    sleep 5
    echo "Distributed query result or expected error:"
    query_node "SELECT count() FROM default.metrics_distributed"
    echo "Restore: docker compose start ch-s2-r1 ch-s2-r2"
    $COMPOSE start ch-s2-r1 ch-s2-r2
    sleep 15
    echo

    echo "## 3. Потеря одного Keeper keeper-1"
    echo "Command: docker compose stop keeper-1"
    $COMPOSE stop keeper-1
    sleep 5
    echo "INSERT into ReplicatedMergeTree with Keeper quorum alive:"
    query_node "INSERT INTO default.metrics_local SELECT now(), 'fault-one-keeper', 'cpu_usage', 42.0"
    query_node "SELECT count() FROM default.metrics_distributed WHERE host = 'fault-one-keeper'"
    echo "Restore: docker compose start keeper-1"
    $COMPOSE start keeper-1
    sleep 10
    echo

    echo "## 4. Потеря кворума Keeper keeper-1 + keeper-2"
    echo "Command: docker compose stop keeper-1 keeper-2"
    $COMPOSE stop keeper-1 keeper-2
    sleep 5
    echo "INSERT into ReplicatedMergeTree should fail, SELECT from existing parts should work:"
    query_node "INSERT INTO default.metrics_local SELECT now(), 'fault-no-quorum', 'memory_usage', 1024.0"
    query_node "SELECT count() FROM default.metrics_distributed WHERE host = 'fault-no-quorum'"
    query_node "SELECT count() FROM default.metrics_distributed"
    echo "Restore: docker compose start keeper-1 keeper-2"
    $COMPOSE start keeper-1 keeper-2
    sleep 15
    echo

    echo "## Final status"
    $COMPOSE ps
} > "$OUT" 2>&1

echo "Fault scenarios written to $OUT"
