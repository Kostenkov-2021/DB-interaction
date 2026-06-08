SET client_min_messages = warning;

ALTER TABLE order_items
    ADD COLUMN IF NOT EXISTS product_name_snapshot TEXT;

UPDATE order_items oi
SET product_name_snapshot = p.name
FROM products p
WHERE p.product_id = oi.product_id
  AND oi.product_name_snapshot IS DISTINCT FROM p.name;

ALTER TABLE order_items
    ALTER COLUMN product_name_snapshot SET NOT NULL;

CREATE OR REPLACE FUNCTION sync_order_item_product_name_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE order_items
    SET product_name_snapshot = NEW.name
    WHERE product_id = NEW.product_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_sync_order_item_name ON products;

CREATE TRIGGER trg_products_sync_order_item_name
AFTER UPDATE OF name ON products
FOR EACH ROW
WHEN (OLD.name IS DISTINCT FROM NEW.name)
EXECUTE FUNCTION sync_order_item_product_name_snapshot();

EXPLAIN ANALYZE
SELECT order_id, product_name_snapshot, quantity, price_at_order
FROM order_items
WHERE product_name_snapshot ILIKE '%Mouse%';

-- jsonb-атрибуты гибкие, но ограничения и индексированные соединения становятся сложнее.
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS attributes_jsonb JSONB NOT NULL DEFAULT '{}'::jsonb;

UPDATE products
SET attributes_jsonb = CASE
    WHEN name = 'Laptop Pro 15' THEN '{"screen": "15 inch", "ram": "32 GB"}'::jsonb
    WHEN name = 'Wireless Mouse' THEN '{"connection": "wireless", "dpi": 1600}'::jsonb
    WHEN name = 'Router AX3000' THEN '{"wifi": "802.11ax", "ports": 4}'::jsonb
    ELSE '{"warranty_months": 12}'::jsonb
END;

CREATE INDEX IF NOT EXISTS idx_products_attributes_jsonb
    ON products USING gin (attributes_jsonb);

EXPLAIN ANALYZE
SELECT product_id, name, attributes_jsonb
FROM products
WHERE attributes_jsonb @> '{"warranty_months": 12}'::jsonb;

RESET client_min_messages;
