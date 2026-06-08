#!/usr/bin/env sh
set -eu

ROWS="${1:-1000000}"
CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"

"$CLIENT" --multiquery <<SQL
USE idz2;

INSERT INTO orders_flat
SELECT
    toDate('2026-01-01') + (number % 150) AS order_date,
    toDateTime(order_date) + ((number * 37) % 86400) AS order_datetime,
    intDiv(number, 3) + 1 AS order_id,
    (number % 250) + 1 AS customer_id,
    concat('Customer ', leftPad(toString(customer_id), 3, '0')) AS customer_name,
    concat('customer', leftPad(toString(customer_id), 3, '0'), '@shop.test') AS customer_email,
    concat('Region ', toString((number % 8) + 1)) AS region,
    (number % 12) + 1 AS product_id,
    multiIf(
        product_id = 1, 'Laptop Pro 15',
        product_id = 2, 'Wireless Mouse',
        product_id = 3, 'Mechanical Keyboard',
        product_id = 4, 'USB-C Hub',
        product_id = 5, 'Monitor 27',
        product_id = 6, 'Desk Mat',
        product_id = 7, 'Web Camera',
        product_id = 8, 'Headphones',
        product_id = 9, 'Smartphone X',
        product_id = 10, 'Tablet Air',
        product_id = 11, 'External SSD 1TB',
        product_id = 12, 'Router AX3000',
        'Unknown') AS product_name,
    multiIf(
        product_id IN (1, 11), 'Computers',
        product_id IN (2, 4, 6), 'Accessories',
        product_id IN (3, 5, 7, 8), 'Peripherals',
        product_id IN (9, 10), 'Mobile',
        product_id = 12, 'Network',
        'Other') AS category,
    toUInt32((number % 4) + 1) AS quantity,
    toDecimal64(multiIf(
        product_id = 1, 125000,
        product_id = 2, 1900,
        product_id = 3, 6500,
        product_id = 4, 4200,
        product_id = 5, 31000,
        product_id = 6, 1200,
        product_id = 7, 7900,
        product_id = 8, 11500,
        product_id = 9, 84000,
        product_id = 10, 56000,
        product_id = 11, 9800,
        product_id = 12, 7200,
        0), 2) AS price,
    price * quantity AS line_total,
    multiIf(
        number % 5 = 0, 'new',
        number % 5 = 1, 'paid',
        number % 5 = 2, 'shipped',
        number % 5 = 3, 'delivered',
        'cancelled') AS order_status
FROM numbers($ROWS);

INSERT INTO orders_ttl SELECT * FROM orders_flat;

SELECT count() AS orders_flat_rows FROM orders_flat;
SELECT count() AS orders_ttl_rows FROM orders_ttl;
SELECT count() AS monthly_sales_rows FROM monthly_sales;
SQL
