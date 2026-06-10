DROP TABLE IF EXISTS pg_products;

CREATE TABLE pg_products (
    id            bigint PRIMARY KEY,
    title         text NOT NULL,
    description   text NOT NULL,
    category      text NOT NULL,
    brand         text NOT NULL,
    price         numeric(12,2) NOT NULL,
    rating        numeric(3,2) NOT NULL,
    reviews_count integer NOT NULL,
    in_stock      boolean NOT NULL,
    tags          jsonb NOT NULL,
    created_at    timestamptz NOT NULL
);

-- После загрузки тех же данных добавляется полнотекстовая колонка и GIN-индекс.
ALTER TABLE pg_products ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || description)) STORED;

CREATE INDEX idx_pg_products_tsv ON pg_products USING GIN(tsv);
CREATE INDEX idx_pg_products_tags ON pg_products USING GIN(tags);

EXPLAIN (ANALYZE, BUFFERS)
SELECT title, ts_rank(tsv, q) AS rank
FROM pg_products, to_tsquery('english', 'wireless & bluetooth & headphones') q
WHERE tsv @@ q
ORDER BY rank DESC
LIMIT 10;

EXPLAIN (ANALYZE, BUFFERS)
SELECT category, COUNT(*) AS cnt, AVG(price) AS avg_price
FROM pg_products, plainto_tsquery('english', 'gaming') q
WHERE tsv @@ q
GROUP BY category
ORDER BY cnt DESC;
