CREATE TABLE IF NOT EXISTS default.metrics_local ON CLUSTER 'production'
(
    timestamp   DateTime,
    host        LowCardinality(String),
    metric_name LowCardinality(String),
    value       Float64
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/metrics_local',
    '{replica}'
)
PARTITION BY toYYYYMM(timestamp)
ORDER BY (host, metric_name, timestamp);

CREATE TABLE IF NOT EXISTS default.metrics_distributed ON CLUSTER 'production'
AS default.metrics_local
ENGINE = Distributed(
    'production',
    'default',
    'metrics_local',
    xxHash64(host, metric_name)
);
