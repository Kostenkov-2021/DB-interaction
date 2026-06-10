-- UPDATE: меняем атрибуты документа
SELECT id, title, price, rating FROM products WHERE id = 42;
UPDATE products_cluster:products SET price = 49990, rating = 4.9 WHERE id = 42;
SELECT id, title, price, rating FROM products WHERE id = 42;

-- DELETE: удаляем документ и проверяем, что он больше не находится
SELECT id, title FROM products WHERE id = 43;
DELETE FROM products_cluster:products WHERE id = 43;
SELECT id, title FROM products WHERE id = 43;

-- REPLACE: заменяем документ целиком
REPLACE INTO products_cluster:products (
    id, title, description, category, brand, price, rating,
    reviews_count, in_stock, tags, created_at
) VALUES (
    44,
    'Replaced gaming laptop with RTX graphics',
    'Full document replacement for RT-index demo. Gaming laptop, mechanical keyboard, fast screen.',
    'laptops',
    'Aster',
    79990,
    4.8,
    512,
    1,
    '{"color":"black","gaming":true,"wireless":false,"memory":"16gb"}',
    1767225600
);
SELECT id, title, price, rating, tags FROM products WHERE id = 44;
