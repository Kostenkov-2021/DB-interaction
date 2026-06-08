INSERT INTO idz3.events
SELECT
    toDateTime('2026-01-01 00:00:00') + number AS event_time,
    multiIf(
        number % 5 = 0, 'page_view',
        number % 5 = 1, 'add_to_cart',
        number % 5 = 2, 'checkout',
        number % 5 = 3, 'payment',
        'logout'
    ) AS event_type,
    toUInt64((number % 25000) + 1) AS user_id,
    concat('batch=initial; event_id=', toString(number), '; source=replica1') AS payload
FROM numbers(150000);

SELECT
    hostName() AS host,
    count() AS rows,
    min(event_time) AS min_event_time,
    max(event_time) AS max_event_time,
    sum(cityHash64(event_time, event_type, user_id, payload)) AS data_hash
FROM idz3.events;
