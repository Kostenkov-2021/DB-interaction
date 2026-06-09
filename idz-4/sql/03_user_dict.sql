CREATE TABLE IF NOT EXISTS user_dict_local ON CLUSTER 'cluster_2x2'
(
    user_id UInt64,
    name String,
    segment LowCardinality(String)
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/user_dict_local',
    '{replica}'
)
ORDER BY user_id;

CREATE TABLE IF NOT EXISTS user_dict_distributed ON CLUSTER 'cluster_2x2'
AS user_dict_local
ENGINE = Distributed('cluster_2x2', default, user_dict_local, xxHash64(user_id));

TRUNCATE TABLE user_dict_local ON CLUSTER 'cluster_2x2';

INSERT INTO user_dict_distributed
SELECT
    toUInt64(number + 1) AS user_id,
    concat('user_', toString(number + 1)) AS name,
    multiIf(
        number % 4 = 0, 'new',
        number % 4 = 1, 'regular',
        number % 4 = 2, 'vip',
        'at_risk'
    ) AS segment
FROM numbers(100000);
