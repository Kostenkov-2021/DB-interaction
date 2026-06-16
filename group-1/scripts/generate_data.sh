#!/usr/bin/env sh
set -eu

ROWS="${1:-5000000}"
CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"

echo "Inserting ${ROWS} telemetry rows into default.metrics_distributed"

"$CLIENT" --query "
INSERT INTO default.metrics_distributed
SELECT
    now() - toIntervalSecond(number % 86400) AS timestamp,
    concat('app-', toString(1 + number % 200)) AS host,
    ['cpu_usage', 'memory_usage', 'request_latency', 'disk_io'][1 + number % 4] AS metric_name,
    round(
        multiIf(
            metric_name = 'cpu_usage', 20 + randCanonical() * 75,
            metric_name = 'memory_usage', 512 + randCanonical() * 15872,
            metric_name = 'request_latency', 5 + randCanonical() * 450,
            100 + randCanonical() * 900
        ),
        3
    ) AS value
FROM numbers(${ROWS})
"

echo "Done"
