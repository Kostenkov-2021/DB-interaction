SET client_min_messages = warning;

DROP MATERIALIZED VIEW IF EXISTS mv_monthly_sales;

CREATE MATERIALIZED VIEW mv_monthly_sales AS
SELECT
    date_trunc('month', o.order_date) AS month,
    p.name AS product_name,
    c.name AS category_name,
    SUM(oi.quantity) AS total_qty,
    SUM(oi.quantity * oi.price_at_order) AS total_revenue
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
GROUP BY 1, 2, 3;

CREATE INDEX IF NOT EXISTS idx_mv_monthly_sales_month_product
    ON mv_monthly_sales(month, product_name);

ANALYZE mv_monthly_sales;

-- Запрос к нормализованным таблицам.
EXPLAIN ANALYZE
SELECT
    date_trunc('month', o.order_date) AS month,
    p.name AS product_name,
    c.name AS category_name,
    SUM(oi.quantity) AS total_qty,
    SUM(oi.quantity * oi.price_at_order) AS total_revenue
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
GROUP BY 1, 2, 3
ORDER BY 1, 2;

-- Запрос к материализованному представлению.
EXPLAIN ANALYZE
SELECT month, product_name, category_name, total_qty, total_revenue
FROM mv_monthly_sales
ORDER BY month, product_name;

REFRESH MATERIALIZED VIEW mv_monthly_sales;

RESET client_min_messages;
