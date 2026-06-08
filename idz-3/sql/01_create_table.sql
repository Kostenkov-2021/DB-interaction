CREATE DATABASE IF NOT EXISTS idz3 ON CLUSTER idz3_cluster;

CREATE TABLE IF NOT EXISTS idz3.events ON CLUSTER idz3_cluster
(
    event_time DateTime,
    event_type LowCardinality(String),
    user_id UInt64,
    payload String
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/idz3/events',
    '{replica}'
)
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_type, event_time);

CREATE TABLE IF NOT EXISTS idz3.events_all ON CLUSTER idz3_cluster
AS idz3.events
ENGINE = Distributed(idz3_cluster, idz3, events, rand());

SELECT
    hostName() AS host,
    database,
    name,
    engine
FROM clusterAllReplicas('idz3_cluster', system.tables)
WHERE database = 'idz3' AND name IN ('events', 'events_all')
ORDER BY host, name;
