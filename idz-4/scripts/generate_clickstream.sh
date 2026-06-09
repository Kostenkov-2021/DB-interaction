#!/usr/bin/env sh
set -eu

ROWS="${1:-2000000}"
OFFSET="${2:-0}"
CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"

"$CLIENT" --query "
INSERT INTO events_distributed
SELECT
    toDate(toDateTime('2026-01-01 00:00:00') + number + ${OFFSET}) AS event_date,
    toDateTime('2026-01-01 00:00:00') + number + ${OFFSET} AS event_time,
    toUInt64((number % 100000) + 1) AS user_id,
    concat('session_', toString(intDiv(number + ${OFFSET}, 20))) AS session_id,
    multiIf(
        number % 6 = 0, 'page_view',
        number % 6 = 1, 'search',
        number % 6 = 2, 'product_view',
        number % 6 = 3, 'add_to_cart',
        number % 6 = 4, 'checkout',
        'logout'
    ) AS event_type,
    concat('/page/', toString(number % 1000)) AS page_url,
    toUInt32(50 + (number % 5000)) AS duration_ms
FROM numbers(${ROWS});
SETTINGS distributed_foreground_insert = 1;
"

"$CLIENT" --query "
SELECT
    count() AS distributed_rows,
    uniqExact(user_id) AS users,
    min(event_time) AS first_event,
    max(event_time) AS last_event
FROM events_distributed;
"
