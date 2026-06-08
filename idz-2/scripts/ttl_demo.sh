#!/usr/bin/env sh
set -eu

CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"

"$CLIENT" --multiquery <<SQL
USE idz2;

INSERT INTO orders_ttl
SELECT
    toDate('2025-01-01') AS order_date,
    toDateTime('2025-01-01 12:00:00') AS order_datetime,
    900000000 + number AS order_id,
    1 AS customer_id,
    'Customer 001' AS customer_name,
    'customer001@shop.test' AS customer_email,
    'Region 1' AS region,
    2 AS product_id,
    'Wireless Mouse' AS product_name,
    'Accessories' AS category,
    1 AS quantity,
    toDecimal64(1900, 2) AS price,
    toDecimal64(1900, 2) AS line_total,
    'paid' AS order_status
FROM numbers(1000);

SELECT 'before_optimize' AS stage, count() AS old_rows
FROM orders_ttl
WHERE order_date < today() - 90;

SELECT
    'before_optimize' AS stage,
    partition,
    name,
    active,
    rows,
    min_date,
    max_date,
    delete_ttl_info_min,
    delete_ttl_info_max
FROM system.parts
WHERE database = 'idz2'
  AND table = 'orders_ttl'
ORDER BY partition, name;

OPTIMIZE TABLE orders_ttl FINAL;

SELECT 'after_optimize' AS stage, count() AS old_rows
FROM orders_ttl
WHERE order_date < today() - 90;

SELECT
    'after_optimize' AS stage,
    partition,
    name,
    active,
    rows,
    min_date,
    max_date,
    delete_ttl_info_min,
    delete_ttl_info_max
FROM system.parts
WHERE database = 'idz2'
  AND table = 'orders_ttl'
ORDER BY partition, name;
SQL
