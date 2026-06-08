-- EXPLAIN-запросы нужно выполнить один раз до создания индексов и один раз после.

SET client_min_messages = warning;

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_date ON orders(order_date);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);
CREATE INDEX IF NOT EXISTS idx_orders_active_status ON orders(order_date) WHERE status IN ('new', 'paid', 'shipped');

ANALYZE customers;
ANALYZE orders;
ANALYZE order_items;
ANALYZE products;

EXPLAIN ANALYZE
SELECT customer_id, name, email, phone
FROM customers
WHERE email = 'customer120@shop.test';

-- На маленьком наборе данных PostgreSQL может предпочесть Seq Scan.
-- Отключаем его только для демонстрации применимости email-индекса.
SET enable_seqscan = off;

EXPLAIN ANALYZE
SELECT customer_id, name, email, phone
FROM customers
WHERE email = 'customer120@shop.test';

RESET enable_seqscan;

EXPLAIN ANALYZE
SELECT order_id, order_date, status, total_amount
FROM orders
WHERE status IN ('new', 'paid', 'shipped')
ORDER BY order_date DESC
LIMIT 20;

-- Обычный B-tree индекс не помогает при ведущем символе `%`.
EXPLAIN ANALYZE
SELECT customer_id, name, email
FROM customers
WHERE name ILIKE '%Customer 12%';

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_customers_name_trgm ON customers USING gin (name gin_trgm_ops);

ANALYZE customers;

EXPLAIN ANALYZE
SELECT customer_id, name, email
FROM customers
WHERE name ILIKE '%Customer 12%';

-- Аналогично: учебный набор данных компактный, поэтому этот блок доказывает,
-- что путь через trigram-индекс доступен, даже если модель стоимости выбирает Seq Scan.
SET enable_seqscan = off;

EXPLAIN ANALYZE
SELECT customer_id, name, email
FROM customers
WHERE name ILIKE '%Customer 12%';

RESET enable_seqscan;

RESET client_min_messages;
