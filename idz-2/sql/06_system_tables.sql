USE idz2;

-- Сжатие по колонкам.
SELECT
    column,
    formatReadableSize(sum(column_data_compressed_bytes)) AS compressed,
    formatReadableSize(sum(column_data_uncompressed_bytes)) AS uncompressed,
    round(sum(column_data_uncompressed_bytes) / nullIf(sum(column_data_compressed_bytes), 0), 2) AS ratio
FROM system.parts_columns
WHERE database = 'idz2'
  AND table = 'orders_flat'
  AND active
GROUP BY column
ORDER BY sum(column_data_uncompressed_bytes) DESC;

-- Размеры таблиц.
SELECT
    table,
    formatReadableSize(sum(data_compressed_bytes)) AS compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    sum(rows) AS rows
FROM system.parts
WHERE database = 'idz2'
  AND active
GROUP BY table
ORDER BY sum(data_uncompressed_bytes) DESC;

-- Демонстрация TTL: состояние частей до удаления старых строк при слиянии.
SELECT
    table,
    partition,
    name,
    active,
    rows,
    min_date,
    max_date,
    delete_ttl_info_min,
    delete_ttl_info_max
FROM system.parts
WHERE database = 'idz2'
  AND table = 'orders_ttl'
ORDER BY partition, name;

-- Выполнить после вставки старых строк:
-- OPTIMIZE TABLE orders_ttl FINAL;
