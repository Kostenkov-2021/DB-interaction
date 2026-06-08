#!/usr/bin/env sh
set -eu

OUT="${1:-/checks/replicas_watch.log}"
INTERVAL="${2:-2}"
ITERATIONS="${3:-30}"
CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"

: > "$OUT"

i=1
while [ "$i" -le "$ITERATIONS" ]; do
    {
        echo "===== итерация ${i} $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
        "$CLIENT" --query "
        SELECT
            hostName() AS host,
            replica_name,
            is_leader,
            total_replicas,
            active_replicas,
            queue_size,
            inserts_in_queue,
            merges_in_queue,
            log_pointer,
            absolute_delay
        FROM system.replicas
        WHERE database = 'idz3' AND table = 'events'
        FORMAT PrettyCompact;
        "
    } >> "$OUT"
    i=$((i + 1))
    sleep "$INTERVAL"
done
