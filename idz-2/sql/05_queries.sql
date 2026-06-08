USE idz2;

-- 1. Топ-10 товаров по выручке.
SELECT
    product_id,
    product_name,
    sum(quantity) AS sold_qty,
    sum(line_total) AS revenue
FROM orders_flat
GROUP BY
    product_id,
    product_name
ORDER BY revenue DESC
LIMIT 10;

-- 2. Ежемесячная динамика продаж по категориям.
SELECT
    toStartOfMonth(order_date) AS month,
    category,
    sum(quantity) AS sold_qty,
    sum(line_total) AS revenue
FROM orders_flat
GROUP BY
    month,
    category
ORDER BY
    month,
    category;

-- 3. Перцентили p95/p99 стоимости заказа.
WITH order_totals AS
(
    SELECT
        order_id,
        sum(line_total) AS order_total
    FROM orders_flat
    GROUP BY order_id
)
SELECT
    quantileExact(0.95)(order_total) AS p95_order_value,
    quantileExact(0.99)(order_total) AS p99_order_value,
    avg(order_total) AS avg_order_value
FROM order_totals;

-- 4. Поиск клиента по подстроке email.
SELECT
    customer_id,
    any(customer_name) AS customer_name,
    customer_email,
    countDistinct(order_id) AS orders_count,
    sum(line_total) AS revenue
FROM orders_flat
WHERE positionCaseInsensitive(customer_email, 'customer120') > 0
GROUP BY
    customer_id,
    customer_email
ORDER BY customer_id;

-- 5a. Агрегация из плоской таблицы фактов.
SELECT
    toStartOfMonth(order_date) AS month,
    category,
    region,
    sum(quantity) AS total_qty,
    sum(line_total) AS total_sales
FROM orders_flat
GROUP BY
    month,
    category,
    region
ORDER BY
    month,
    category,
    region
LIMIT 20;

-- 5b. Тот же результат из предагрегированной таблицы SummingMergeTree.
SELECT
    month,
    category,
    region,
    sum(total_qty) AS total_qty,
    sum(total_sales) AS total_sales
FROM monthly_sales
GROUP BY
    month,
    category,
    region
ORDER BY
    month,
    category,
    region
LIMIT 20;

-- Время выполнения запросов можно сохранить командой:
-- clickhouse-client --time --queries-file /sql/05_queries.sql
