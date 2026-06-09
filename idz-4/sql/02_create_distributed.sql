CREATE TABLE IF NOT EXISTS events_distributed ON CLUSTER 'cluster_2x2'
AS events_local
ENGINE = Distributed('cluster_2x2', default, events_local, xxHash64(user_id));

