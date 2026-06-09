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
WHERE cluster = 'cluster_2x2'
ORDER BY shard_num, replica_num
FORMAT TSVWithNames
" > "$CHECK_DIR/cluster_info.txt"

"$CLIENT" --multiquery > "$CHECK_DIR/data_distribution.txt" <<'SQL'
SELECT 'Rows on every replica' AS section;
SELECT
    hostName() AS host,
    count() AS rows,
    uniqExact(user_id) AS users
FROM clusterAllReplicas('cluster_2x2', default.events_local)
GROUP BY host
ORDER BY host
FORMAT TSVWithNames;

SELECT 'Rows on one replica per shard' AS section;
SELECT
    hostName() AS host,
    count() AS rows,
    uniqExact(user_id) AS users
FROM cluster('cluster_2x2', default.events_local)
GROUP BY host
ORDER BY host
FORMAT TSVWithNames;

SELECT 'Selected users are stored on exactly one shard host' AS section;
SELECT
    user_id,
    uniqExact(host) AS shard_hosts,
    groupArray(host) AS hosts,
    sum(rows) AS rows
FROM
(
    SELECT
        hostName() AS host,
        user_id,
        count() AS rows
    FROM cluster('cluster_2x2', default.events_local)
    WHERE user_id IN (1, 7, 42, 1000, 99999)
    GROUP BY host, user_id
)
GROUP BY user_id
ORDER BY user_id
FORMAT TSVWithNames;
SQL

"$CLIENT" --multiquery --queries-file /sql/04_queries.sql > "$CHECK_DIR/distributed_queries.txt"

"$CLIENT" --multiquery > "$CHECK_DIR/reshard_demo.txt" <<'SQL'
SELECT 'Third shard procedure is documented in README.md and sql/05_reshard_plan.sql' AS note;
SELECT 'Old rows remain on old shards until copied/deleted by an explicit rebalance migration.' AS old_data_behavior;
SELECT 'New rows use cluster_3x2 after events_distributed is recreated with Distributed(cluster_3x2, ...).' AS new_data_behavior;
SQL
