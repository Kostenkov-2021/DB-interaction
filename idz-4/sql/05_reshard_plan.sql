-- Start optional third-shard containers first:
-- docker compose --profile shard3 up -d ch-s3-r1 ch-s3-r2
--
-- Then update all ClickHouse nodes to use config/clickhouse/cluster_3x2.xml
-- and restart the ClickHouse containers.

CREATE TABLE IF NOT EXISTS events_local ON CLUSTER 'cluster_3x2'
(
    event_date  Date,
    event_time  DateTime,
    user_id     UInt64,
    session_id  String,
    event_type  LowCardinality(String),
    page_url    String,
    duration_ms UInt32
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/events_local',
    '{replica}'
)
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_time);

DROP TABLE IF EXISTS events_distributed ON CLUSTER 'cluster_3x2';

CREATE TABLE events_distributed ON CLUSTER 'cluster_3x2'
AS events_local
ENGINE = Distributed('cluster_3x2', default, events_local, xxHash64(user_id));

-- New rows now use three shards.
INSERT INTO events_distributed
SELECT
    toDate(toDateTime('2026-02-01 00:00:00') + number) AS event_date,
    toDateTime('2026-02-01 00:00:00') + number AS event_time,
    toUInt64((number % 100000) + 1) AS user_id,
    concat('session_', toString(intDiv(number, 20))) AS session_id,
    'page_view' AS event_type,
    concat('/page/', toString(number % 1000)) AS page_url,
    toUInt32(50 + (number % 5000)) AS duration_ms
FROM numbers(300000);

SELECT
    hostName() AS host,
    count() AS rows
FROM cluster('cluster_3x2', default.events_local)
GROUP BY host
ORDER BY host;

-- Rebalance skeleton: rows with the new 3-shard assignment for shard 3
-- are copied, validated, and then removed from old shards.
CREATE TABLE IF NOT EXISTS events_rebalance_buffer AS events_local
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_date)
ORDER BY (user_id, event_time);

INSERT INTO events_rebalance_buffer
SELECT *
FROM cluster('cluster_2x2', default.events_local)
WHERE modulo(xxHash64(user_id), 3) = 2;

-- In a real run, insert the buffer into the new cluster and validate counts/hashes.
INSERT INTO events_distributed
SELECT *
FROM events_rebalance_buffer;

-- After validation:
-- ALTER TABLE events_local ON CLUSTER 'cluster_2x2'
--     DELETE WHERE modulo(xxHash64(user_id), 3) = 2;
-- SELECT * FROM system.mutations WHERE table = 'events_local';

