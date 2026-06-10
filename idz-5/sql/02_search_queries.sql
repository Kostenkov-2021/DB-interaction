-- 4.1. Базовый поиск
SELECT id, title, WEIGHT() AS w
FROM products
WHERE MATCH('wireless bluetooth headphones')
ORDER BY w DESC
LIMIT 10;

-- 4.2. Поиск с точной фразой
SELECT id, title, WEIGHT() AS w
FROM products
WHERE MATCH('"noise cancelling"')
LIMIT 10;

-- 4.3. Поиск с оператором proximity
SELECT id, title, WEIGHT() AS w
FROM products
WHERE MATCH('"portable speaker"~3')
LIMIT 10;

-- 4.4. Поиск с фильтрацией по атрибутам
SELECT id, title, price, rating
FROM products
WHERE MATCH('laptop') AND price BETWEEN 30000 AND 80000 AND rating >= 4.0
ORDER BY rating DESC
LIMIT 10;

-- 4.5. Поиск по JSON-атрибуту
SELECT id, title, tags
FROM products
WHERE MATCH('phone') AND tags.color = 'black'
LIMIT 10;

-- Дополнительно: подсветка найденных слов
SELECT id, HIGHLIGHT() AS snippet
FROM products
WHERE MATCH('wireless headphones')
LIMIT 5;

-- Дополнительно: autocomplete/suggest через словарь ключевых слов
CALL KEYWORDS('wireles headphons', 'products', 1 AS stats);
