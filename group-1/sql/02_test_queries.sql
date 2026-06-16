SELECT 'total rows through distributed table' AS check_name;
SELECT count() AS rows FROM default.metrics_distributed FORMAT TSVWithNames;

SELECT 'rows by metric' AS check_name;
SELECT
    metric_name,
    count() AS rows,
    round(avg(value), 2) AS avg_value,
    round(quantile(0.99)(value), 2) AS p99_value
FROM default.metrics_distributed
GROUP BY metric_name
ORDER BY metric_name
FORMAT TSVWithNames;

SELECT 'rows by logical host' AS check_name;
SELECT
    host,
    count() AS rows
FROM default.metrics_distributed
GROUP BY host
ORDER BY host
FORMAT TSVWithNames;

SELECT 'last minute sample' AS check_name;
SELECT
    metric_name,
    max(timestamp) AS last_ts,
    round(avg(value), 2) AS avg_value
FROM default.metrics_distributed
WHERE timestamp >= now() - INTERVAL 60 MINUTE
GROUP BY metric_name
ORDER BY metric_name
FORMAT TSVWithNames;
