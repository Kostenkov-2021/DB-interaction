CREATE DATABASE IF NOT EXISTS idz2;

DROP VIEW IF EXISTS idz2.mv_monthly_sales;
DROP TABLE IF EXISTS idz2.monthly_sales;

CREATE TABLE idz2.monthly_sales
(
    month       Date,
    category    LowCardinality(String),
    region      LowCardinality(String),
    total_qty   UInt64,
    total_sales Decimal(18, 2)
)
ENGINE = SummingMergeTree((total_qty, total_sales))
PARTITION BY toYYYYMM(month)
ORDER BY (month, category, region);

CREATE MATERIALIZED VIEW idz2.mv_monthly_sales
TO idz2.monthly_sales
AS
SELECT
    toStartOfMonth(order_date) AS month,
    category,
    region,
    sum(quantity) AS total_qty,
    sum(line_total) AS total_sales
FROM idz2.orders_flat
GROUP BY
    month,
    category,
    region;
