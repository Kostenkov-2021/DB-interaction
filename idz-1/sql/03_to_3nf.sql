DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS addresses;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE,
    phone       TEXT NOT NULL
);

CREATE TABLE addresses (
    address_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    address     TEXT NOT NULL,
    UNIQUE (customer_id, address)
);

CREATE TABLE categories (
    category_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE
);

CREATE TABLE products (
    product_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    category_id INTEGER NOT NULL REFERENCES categories(category_id),
    price       NUMERIC(12, 2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE orders (
    order_id     INTEGER PRIMARY KEY,
    customer_id  INTEGER NOT NULL REFERENCES customers(customer_id),
    address_id   INTEGER NOT NULL REFERENCES addresses(address_id),
    order_date   DATE NOT NULL,
    status       TEXT NOT NULL CHECK (status IN ('new', 'paid', 'shipped', 'delivered', 'cancelled')),
    total_amount NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0)
);

CREATE TABLE order_items (
    order_id       INTEGER NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id     INTEGER NOT NULL REFERENCES products(product_id),
    quantity       INTEGER NOT NULL CHECK (quantity > 0),
    price_at_order NUMERIC(12, 2) NOT NULL CHECK (price_at_order >= 0),
    PRIMARY KEY (order_id, product_id)
);

INSERT INTO customers (name, email, phone)
SELECT name, email, phone
FROM customers_2nf
ORDER BY customer_id;

INSERT INTO addresses (customer_id, address)
SELECT DISTINCT c.customer_id, o.delivery_address
FROM orders_2nf o
JOIN customers_2nf c2 ON c2.customer_id = o.customer_id
JOIN customers c ON c.email = c2.email
ORDER BY c.customer_id, o.delivery_address;

INSERT INTO categories (name)
VALUES
    ('Computers'),
    ('Accessories'),
    ('Peripherals'),
    ('Mobile'),
    ('Network');

INSERT INTO products (name, category_id, price)
SELECT
    p.name,
    c.category_id,
    p.price
FROM products_2nf p
JOIN categories c ON c.name = CASE
    WHEN p.name IN ('Laptop Pro 15', 'External SSD 1TB') THEN 'Computers'
    WHEN p.name IN ('Wireless Mouse', 'USB-C Hub', 'Desk Mat') THEN 'Accessories'
    WHEN p.name IN ('Mechanical Keyboard', 'Monitor 27', 'Web Camera', 'Headphones') THEN 'Peripherals'
    WHEN p.name IN ('Smartphone X', 'Tablet Air') THEN 'Mobile'
    ELSE 'Network'
END
ORDER BY p.product_id;

INSERT INTO orders (order_id, customer_id, address_id, order_date, status, total_amount)
SELECT
    o.order_id,
    c.customer_id,
    a.address_id,
    o.order_date,
    o.status,
    o.total_amount
FROM orders_2nf o
JOIN customers_2nf c2 ON c2.customer_id = o.customer_id
JOIN customers c ON c.email = c2.email
JOIN addresses a ON a.customer_id = c.customer_id AND a.address = o.delivery_address;

INSERT INTO order_items (order_id, product_id, quantity, price_at_order)
SELECT
    oi.order_id,
    p.product_id,
    oi.quantity,
    oi.price_at_order
FROM order_items_2nf oi
JOIN products_2nf p2 ON p2.product_id = oi.product_id
JOIN products p ON p.name = p2.name;

SELECT
    (SELECT COUNT(*) FROM customers) AS customers,
    (SELECT COUNT(*) FROM addresses) AS addresses,
    (SELECT COUNT(*) FROM categories) AS categories,
    (SELECT COUNT(*) FROM products) AS products,
    (SELECT COUNT(*) FROM orders) AS orders,
    (SELECT COUNT(*) FROM order_items) AS order_items;
