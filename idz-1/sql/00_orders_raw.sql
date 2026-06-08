DROP TABLE IF EXISTS orders_raw;

CREATE TABLE orders_raw (
    order_id           INTEGER,
    order_date         DATE,
    customer_name      TEXT,
    customer_email     TEXT,
    customer_phone     TEXT,
    delivery_address   TEXT,
    product_names      TEXT,
    product_prices     TEXT,
    product_quantities TEXT,
    total_amount       NUMERIC(12, 2),
    status             TEXT
);

WITH product_catalog(product_no, product_name, product_price) AS (
    VALUES
        (1, 'Laptop Pro 15', 125000::numeric),
        (2, 'Wireless Mouse', 1900::numeric),
        (3, 'Mechanical Keyboard', 6500::numeric),
        (4, 'USB-C Hub', 4200::numeric),
        (5, 'Monitor 27', 31000::numeric),
        (6, 'Desk Mat', 1200::numeric),
        (7, 'Web Camera', 7900::numeric),
        (8, 'Headphones', 11500::numeric),
        (9, 'Smartphone X', 84000::numeric),
        (10, 'Tablet Air', 56000::numeric),
        (11, 'External SSD 1TB', 9800::numeric),
        (12, 'Router AX3000', 7200::numeric)
),
orders_seed AS (
    SELECT
        gs AS order_id,
        DATE '2026-01-01' + ((gs - 1) % 150) AS order_date,
        'Customer ' || lpad(((gs - 1) % 250 + 1)::text, 3, '0') AS customer_name,
        'customer' || lpad(((gs - 1) % 250 + 1)::text, 3, '0') || '@shop.test' AS customer_email,
        '+7-900-' || lpad(((gs - 1) % 1000)::text, 3, '0') || '-' || lpad(((gs * 17) % 100)::text, 2, '0') || '-' || lpad(((gs * 31) % 100)::text, 2, '0') AS customer_phone,
        'City ' || (((gs - 1) % 25) + 1) || ', Street ' || (((gs - 1) % 80) + 1) || ', building ' || (((gs - 1) % 40) + 1) AS delivery_address,
        CASE gs % 5
            WHEN 0 THEN 'new'
            WHEN 1 THEN 'paid'
            WHEN 2 THEN 'shipped'
            WHEN 3 THEN 'delivered'
            ELSE 'cancelled'
        END AS status,
        1 + (gs % 3) AS item_count
    FROM generate_series(1, 1200) AS gs
),
order_lines AS (
    SELECT
        os.order_id,
        pc.product_name,
        pc.product_price,
        1 + ((os.order_id + line_no) % 4) AS quantity,
        line_no
    FROM orders_seed os
    CROSS JOIN LATERAL generate_series(1, os.item_count) AS line_no
    JOIN product_catalog pc
        ON pc.product_no = ((os.order_id + line_no - 1) % 12) + 1
)
INSERT INTO orders_raw (
    order_id,
    order_date,
    customer_name,
    customer_email,
    customer_phone,
    delivery_address,
    product_names,
    product_prices,
    product_quantities,
    total_amount,
    status
)
SELECT
    os.order_id,
    os.order_date,
    os.customer_name,
    os.customer_email,
    os.customer_phone,
    os.delivery_address,
    string_agg(ol.product_name, ', ' ORDER BY ol.line_no) AS product_names,
    string_agg(ol.product_price::text, ', ' ORDER BY ol.line_no) AS product_prices,
    string_agg(ol.quantity::text, ', ' ORDER BY ol.line_no) AS product_quantities,
    SUM(ol.product_price * ol.quantity) AS total_amount,
    os.status
FROM orders_seed os
JOIN order_lines ol ON ol.order_id = os.order_id
GROUP BY
    os.order_id,
    os.order_date,
    os.customer_name,
    os.customer_email,
    os.customer_phone,
    os.delivery_address,
    os.status;

SELECT COUNT(*) AS orders_raw_rows FROM orders_raw;
