SELECT 'cluster_2x2 topology' AS check_name;

SELECT
    cluster,
    shard_num,
    replica_num,
    host_name,
    host_address,
    port,
    is_local
FROM system.clusters
WHERE cluster = 'cluster_2x2'
ORDER BY shard_num, replica_num;

SELECT 'global count through Distributed' AS check_name;

SELECT count() AS distributed_rows
FROM events_distributed;

SELECT
    count() AS local_rows_sum
FROM cluster('cluster_2x2', default.events_local);

SELECT 'rows on every replica' AS check_name;

SELECT
    hostName() AS host,
    count() AS rows
FROM clusterAllReplicas('cluster_2x2', default.events_local)
GROUP BY host
ORDER BY host;

SELECT 'rows on one replica per shard' AS check_name;

SELECT
    hostName() AS host,
    count() AS rows
FROM cluster('cluster_2x2', default.events_local)
GROUP BY host
ORDER BY host;

SELECT 'top users, GROUP BY sharding key' AS check_name;

SELECT
    user_id,
    count() AS events
FROM events_distributed
GROUP BY user_id
ORDER BY events DESC, user_id
LIMIT 10;

SELECT 'user placement proof' AS check_name;

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
    WHERE user_id GLOBAL IN
    (
        SELECT user_id
        FROM events_distributed
        GROUP BY user_id
        ORDER BY count() DESC, user_id
        LIMIT 10
    )
    GROUP BY host, user_id
)
GROUP BY user_id
ORDER BY rows DESC, user_id;

SELECT 'top pages, GROUP BY non-sharding key' AS check_name;

SELECT
    page_url,
    count() AS visits
FROM events_distributed
GROUP BY page_url
ORDER BY visits DESC, page_url
LIMIT 10;

SELECT 'JOIN through Distributed' AS check_name;

SELECT
    d.segment,
    e.event_type,
    count() AS events,
    uniqExact(e.user_id) AS users
FROM events_distributed AS e
GLOBAL INNER JOIN user_dict_distributed AS d USING (user_id)
GROUP BY d.segment, e.event_type
ORDER BY events DESC
LIMIT 20;

SELECT 'GLOBAL IN comparison plan' AS check_name;

SET distributed_product_mode = 'local';

EXPLAIN
SELECT count()
FROM events_distributed
WHERE user_id IN
(
    SELECT user_id
    FROM user_dict_distributed
    WHERE segment = 'vip'
);

SET distributed_product_mode = 'deny';

EXPLAIN
SELECT count()
FROM events_distributed
WHERE user_id GLOBAL IN
(
    SELECT user_id
    FROM user_dict_distributed
    WHERE segment = 'vip'
);

SELECT 'distributed DDL queue' AS check_name;

SELECT
    entry,
    host,
    status,
    query
FROM system.distributed_ddl_queue
WHERE query ILIKE '%events_%' OR query ILIKE '%user_dict%'
ORDER BY entry, host
LIMIT 50;
