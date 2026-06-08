#!/usr/bin/env sh
set -eu

# Опциональный путь переноса: PostgreSQL 3NF -> поток CSV -> плоская таблица ClickHouse.
# Предполагается, что SQL-скрипты idz-1 уже выполнены в сервисе postgres.
docker compose exec -T postgres psql -U idz1 -d idz1 -c "\copy (
SELECT
    o.order_date,
    o.order_date::timestamp AS order_datetime,
    o.order_id,
    c.customer_id,
    c.name AS customer_name,
    c.email AS customer_email,
    split_part(a.address, ',', 1) AS region,
    p.product_id,
    p.name AS product_name,
    cat.name AS category,
    oi.quantity,
    oi.price_at_order AS price,
    oi.quantity * oi.price_at_order AS line_total,
    o.status AS order_status
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN addresses a ON a.address_id = o.address_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN categories cat ON cat.category_id = p.category_id
ORDER BY o.order_id, p.product_id
) TO STDOUT WITH CSV HEADER" |
docker compose exec -T clickhouse clickhouse-client --query "
INSERT INTO idz2.orders_flat
FORMAT CSVWithNames"
