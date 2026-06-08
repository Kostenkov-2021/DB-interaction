#!/usr/bin/env sh
set -eu

ROWS="${1:-150000}"
BATCH="${2:-manual}"
OFFSET="${3:-0}"
CLIENT="${CLICKHOUSE_CLIENT:-clickhouse-client}"

"$CLIENT" --query "
INSERT INTO idz3.events
SELECT
    toDateTime('2026-01-01 00:00:00') + number + ${OFFSET} AS event_time,
    multiIf(
        number % 5 = 0, 'page_view',
        number % 5 = 1, 'add_to_cart',
        number % 5 = 2, 'checkout',
        number % 5 = 3, 'payment',
        'logout'
    ) AS event_type,
    toUInt64((number % 25000) + 1) AS user_id,
    concat('batch=${BATCH}; event_id=', toString(number + ${OFFSET}), '; source=', hostName()) AS payload
FROM numbers(${ROWS});
"

"$CLIENT" --query "
SELECT
    hostName() AS host,
    '${BATCH}' AS batch,
    count() AS total_rows,
    sum(cityHash64(event_time, event_type, user_id, payload)) AS data_hash
FROM idz3.events;
"
