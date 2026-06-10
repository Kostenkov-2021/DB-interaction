DROP TABLE IF EXISTS product_notifications;

CREATE TABLE product_notifications (
    query text,
    user_id integer,
    channel string
) type='percolate';

INSERT INTO product_notifications (id, query, user_id, channel)
VALUES
    (1, '@title gaming laptop', 1001, 'email'),
    (2, '@description wireless headphones', 1002, 'telegram'),
    (3, '@title portable speaker', 1003, 'email');

CALL PQ('product_notifications', 'New gaming laptop with RTX graphics and fast 144hz screen');
