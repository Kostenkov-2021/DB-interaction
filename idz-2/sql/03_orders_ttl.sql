CREATE DATABASE IF NOT EXISTS idz2;

DROP TABLE IF EXISTS idz2.orders_ttl;

CREATE TABLE idz2.orders_ttl
(
    order_date       Date CODEC(Delta, ZSTD(3)),
    order_datetime   DateTime CODEC(Delta, ZSTD(3)),
    order_id         UInt64 CODEC(Delta, ZSTD(3)),
    customer_id      UInt64 CODEC(Delta, ZSTD(3)),
    customer_name    String CODEC(ZSTD(3)),
    customer_email   LowCardinality(String) CODEC(ZSTD(3)),
    region           LowCardinality(String) CODEC(ZSTD(3)),
    product_id       UInt64 CODEC(Delta, ZSTD(3)),
    product_name     String CODEC(ZSTD(3)),
    category         LowCardinality(String) CODEC(ZSTD(3)),
    quantity         UInt32 CODEC(LZ4),
    price            Decimal(12, 2) CODEC(Delta, ZSTD(3)),
    line_total       Decimal(12, 2) CODEC(Delta, ZSTD(3)),
    order_status     LowCardinality(String) CODEC(ZSTD(3))
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (category, toStartOfHour(order_datetime), order_status)
TTL order_date + INTERVAL 90 DAY DELETE
SETTINGS index_granularity = 8192;
