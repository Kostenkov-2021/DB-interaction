DROP TABLE IF EXISTS order_items_2nf;
DROP TABLE IF EXISTS orders_2nf;
DROP TABLE IF EXISTS products_2nf;
DROP TABLE IF EXISTS customers_2nf;

CREATE TABLE customers_2nf (
    customer_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE,
    phone       TEXT NOT NULL
);

CREATE TABLE products_2nf (
    product_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       TEXT NOT NULL UNIQUE,
    price      NUMERIC(12, 2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE orders_2nf (
    order_id         INTEGER PRIMARY KEY,
    customer_id      INTEGER NOT NULL REFERENCES customers_2nf(customer_id),
    order_date       DATE NOT NULL,
    delivery_address TEXT NOT NULL,
    status           TEXT NOT NULL,
    total_amount     NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0)
);

CREATE TABLE order_items_2nf (
    order_id       INTEGER NOT NULL REFERENCES orders_2nf(order_id) ON DELETE CASCADE,
    product_id     INTEGER NOT NULL REFERENCES products_2nf(product_id),
    quantity       INTEGER NOT NULL CHECK (quantity > 0),
    price_at_order NUMERIC(12, 2) NOT NULL CHECK (price_at_order >= 0),
    PRIMARY KEY (order_id, product_id)
);

INSERT INTO customers_2nf (name, email, phone)
SELECT
    MIN(customer_name) AS name,
    customer_email AS email,
    MIN(customer_phone) AS phone
FROM orders_1nf
GROUP BY customer_email
ORDER BY customer_email;

INSERT INTO products_2nf (name, price)
SELECT product_name, MIN(product_price) AS price
FROM orders_1nf
GROUP BY product_name
ORDER BY product_name;

INSERT INTO orders_2nf (order_id, customer_id, order_date, delivery_address, status, total_amount)
SELECT DISTINCT
    o.order_id,
    c.customer_id,
    o.order_date,
    o.delivery_address,
    o.status,
    o.order_total
FROM orders_1nf o
JOIN customers_2nf c ON c.email = o.customer_email;

INSERT INTO order_items_2nf (order_id, product_id, quantity, price_at_order)
SELECT
    o.order_id,
    p.product_id,
    SUM(o.quantity) AS quantity,
    MIN(o.product_price) AS price_at_order
FROM orders_1nf o
JOIN products_2nf p ON p.name = o.product_name
GROUP BY o.order_id, p.product_id;

SELECT
    (SELECT COUNT(*) FROM customers_2nf) AS customers,
    (SELECT COUNT(*) FROM products_2nf) AS products,
    (SELECT COUNT(*) FROM orders_2nf) AS orders,
    (SELECT COUNT(*) FROM order_items_2nf) AS order_items;
