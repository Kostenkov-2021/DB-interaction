-- 1. Создание заказа: CTE + RETURNING + SELECT ... FOR UPDATE.
BEGIN;

EXPLAIN ANALYZE
WITH selected_customer AS (
    SELECT customer_id
    FROM customers
    WHERE email = 'customer001@shop.test'
),
selected_address AS (
    SELECT address_id
    FROM addresses
    WHERE customer_id = (SELECT customer_id FROM selected_customer)
    ORDER BY address_id
    LIMIT 1
),
locked_products AS (
    SELECT product_id, name, price
    FROM products
    WHERE name IN ('Wireless Mouse', 'Desk Mat')
    FOR UPDATE
),
new_order AS (
    INSERT INTO orders (order_id, customer_id, address_id, order_date, status, total_amount)
    SELECT
        900001,
        (SELECT customer_id FROM selected_customer),
        (SELECT address_id FROM selected_address),
        CURRENT_DATE,
        'new',
        SUM(CASE WHEN name = 'Wireless Mouse' THEN price * 2 ELSE price END)
    FROM locked_products
    RETURNING order_id
)
INSERT INTO order_items (order_id, product_id, quantity, price_at_order)
SELECT
    (SELECT order_id FROM new_order),
    product_id,
    CASE WHEN product_id = (SELECT product_id FROM products WHERE name = 'Wireless Mouse') THEN 2 ELSE 1 END,
    price
FROM locked_products;

COMMIT;

-- 2. Обновление статуса заказа.
EXPLAIN ANALYZE
UPDATE orders
SET status = 'shipped'
WHERE order_id = 900001
RETURNING order_id, status;

-- 3. Получение заказа вместе с клиентом, позициями и товарами.
EXPLAIN ANALYZE
SELECT
    o.order_id,
    o.order_date,
    o.status,
    c.name AS customer_name,
    c.email,
    p.name AS product_name,
    oi.quantity,
    oi.price_at_order
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
WHERE o.order_id = 900001;

-- 4. Отчёт "топ-10 товаров".
EXPLAIN ANALYZE
SELECT
    p.name,
    SUM(oi.quantity) AS sold_qty,
    SUM(oi.quantity * oi.price_at_order) AS revenue
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
GROUP BY p.product_id, p.name
ORDER BY revenue DESC
LIMIT 10;

-- 5a. Поиск клиента по email.
EXPLAIN ANALYZE
SELECT customer_id, name, email, phone
FROM customers
WHERE email = 'customer120@shop.test';

-- 5b. Поиск клиента по подстроке имени.
EXPLAIN ANALYZE
SELECT customer_id, name, email, phone
FROM customers
WHERE name ILIKE '%Customer 12%';
