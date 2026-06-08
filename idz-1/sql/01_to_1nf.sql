DROP TABLE IF EXISTS orders_1nf;

CREATE TABLE orders_1nf (
    order_id         INTEGER NOT NULL,
    order_date       DATE NOT NULL,
    customer_name    TEXT NOT NULL,
    customer_email   TEXT NOT NULL,
    customer_phone   TEXT NOT NULL,
    delivery_address TEXT NOT NULL,
    line_no          INTEGER NOT NULL,
    product_name     TEXT NOT NULL,
    product_price    NUMERIC(12, 2) NOT NULL CHECK (product_price >= 0),
    quantity         INTEGER NOT NULL CHECK (quantity > 0),
    line_amount      NUMERIC(12, 2) NOT NULL CHECK (line_amount >= 0),
    order_total      NUMERIC(12, 2) NOT NULL CHECK (order_total >= 0),
    status           TEXT NOT NULL,
    PRIMARY KEY (order_id, line_no)
);

INSERT INTO orders_1nf (
    order_id,
    order_date,
    customer_name,
    customer_email,
    customer_phone,
    delivery_address,
    line_no,
    product_name,
    product_price,
    quantity,
    line_amount,
    order_total,
    status
)
SELECT
    r.order_id,
    r.order_date,
    r.customer_name,
    r.customer_email,
    r.customer_phone,
    r.delivery_address,
    line.line_no,
    trim(names.product_name) AS product_name,
    trim(prices.product_price)::numeric(12, 2) AS product_price,
    trim(quantities.quantity)::integer AS quantity,
    trim(prices.product_price)::numeric(12, 2) * trim(quantities.quantity)::integer AS line_amount,
    r.total_amount AS order_total,
    r.status
FROM orders_raw r
CROSS JOIN LATERAL unnest(
    string_to_array(r.product_names, ','),
    string_to_array(r.product_prices, ','),
    string_to_array(r.product_quantities, ',')
) WITH ORDINALITY AS line(product_name, product_price, quantity, line_no)
CROSS JOIN LATERAL (SELECT line.product_name) AS names
CROSS JOIN LATERAL (SELECT line.product_price) AS prices
CROSS JOIN LATERAL (SELECT line.quantity) AS quantities;

SELECT COUNT(*) AS orders_1nf_rows FROM orders_1nf;
