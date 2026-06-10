-- Агрегация по категориям
SELECT category, COUNT(*) AS cnt, AVG(price) AS avg_price
FROM products
WHERE MATCH('gaming')
GROUP BY category
ORDER BY cnt DESC;

-- Нативные фасеты ManticoreSearch
SELECT id, title, price FROM products WHERE MATCH('gaming')
FACET category ORDER BY COUNT(*) DESC
FACET brand ORDER BY COUNT(*) DESC;
