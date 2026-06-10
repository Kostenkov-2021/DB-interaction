-- Команды выполняются после создания RT-индекса products на первом узле.
-- Узел 1: 127.0.0.1:19306 / http://127.0.0.1:19308
CREATE CLUSTER products_cluster;
SET CLUSTER products_cluster GLOBAL 'pc.bootstrap' = 1;
ALTER CLUSTER products_cluster ADD products;

-- Узел 2: 127.0.0.1:29306 / http://127.0.0.1:29308
-- Команду нужно выполнить на втором узле.
JOIN CLUSTER products_cluster AT 'manticore-1:9312';

-- Если после одновременного restart двух узлов статус стал non-primary:
SET CLUSTER products_cluster GLOBAL 'pc.bootstrap' = 1;

-- Проверка:
SHOW STATUS LIKE 'cluster%';
