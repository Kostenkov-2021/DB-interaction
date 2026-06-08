# ИДЗ-2. ClickHouse: колоночное хранилище, движки и OLAP-аналитика

Костенков Данил Денисович, P4150

## Что сделано

В каталоге находится воспроизводимое решение на ClickHouse для предметной области интернет-магазина из ИДЗ-1:

- `orders_flat` на движке `MergeTree`: денормализованная таблица фактов, одна строка соответствует одной позиции заказа.
- `orders_ttl` на движке `MergeTree` с TTL: та же структура, но строки старше 90 дней автоматически удаляются при слиянии частей.
- `monthly_sales` на движке `SummingMergeTree`: предагрегированные месячные продажи по категории и региону.
- `mv_monthly_sales`: материализованное представление, которое пишет агрегаты из `orders_flat` в `monthly_sales`.
- Конфигурация ClickHouse: прослушивание `0.0.0.0`, профиль `readonly`, пользователь `analyst` с режимом только чтения.
- Скрипт генерации данных объемом не менее 1 000 000 строк.
- Аналитические запросы, демонстрация TTL, запросы к системным таблицам и текстовые файлы проверок.

## Как поднять окружение

Запустить PostgreSQL и ClickHouse рядом:

```sh
cd idz-2
docker compose up -d
```

Проверить подключение:

```sh
docker compose exec clickhouse clickhouse-client --query "SELECT currentUser(), version()"
docker compose exec clickhouse clickhouse-client --user analyst --password analyst --query "SELECT currentUser(), version()"
docker compose exec clickhouse clickhouse-client --user analyst --password analyst --query "CREATE DATABASE readonly_check"
```

Последняя команда должна завершиться ошибкой, потому что пользователь `analyst` работает с профилем `readonly`.

Создать схему и загрузить данные:

```sh
docker compose exec clickhouse clickhouse-client --multiquery --queries-file /sql/01_create_db.sql
docker compose exec clickhouse clickhouse-client --multiquery --queries-file /sql/02_orders_flat.sql
docker compose exec clickhouse clickhouse-client --multiquery --queries-file /sql/03_orders_ttl.sql
docker compose exec clickhouse clickhouse-client --multiquery --queries-file /sql/04_monthly_sales.sql
docker compose exec clickhouse sh /scripts/generate_data.sh 1000000
```

Запустить аналитику и системные проверки:

```sh
docker compose exec clickhouse clickhouse-client --time --queries-file /sql/05_queries.sql
docker compose exec clickhouse clickhouse-client --time --queries-file /sql/06_system_tables.sql
docker compose exec clickhouse sh /scripts/ttl_demo.sh
```

## Почему схема денормализована

ClickHouse оптимизирован под аналитическое сканирование и агрегацию по колонкам. Нормализованная схема 3NF из ИДЗ-1 хорошо подходит для OLTP-нагрузки: точечных вставок, точечных чтений и обновлений. Но аналитические отчеты по заказам обычно требуют нескольких соединений: `orders`, `customers`, `order_items`, `products`, `categories`. В ClickHouse такие JOIN на лету увеличивают расход CPU и памяти.

Для этой нагрузки таблица намеренно сделана плоской. Товар, категория, email клиента, регион и статус хранятся в той же строке, что и числовые меры. Это убирает JOIN из горячих отчетов: топ товаров, месячная динамика, перцентили стоимости заказа и поиск клиента читают одну таблицу фактов.

Избыточность данных компенсируется колоночным сжатием. Повторяющиеся измерения `category`, `region`, `customer_email`, `order_status` объявлены как `LowCardinality(String)`: ClickHouse хранит компактные ключи словаря вместо полного повторения строковых значений в каждой записи. В аналитике с преобладанием чтения это заменяет многие небольшие справочники.

## Выбор ORDER BY

В `orders_flat` используется:

```sql
ORDER BY (category, toStartOfHour(order_datetime), order_status)
```

Такой порядок соответствует отчетам: категория участвует в динамике продаж, временные бакеты используются для месячных и часовых срезов, статус часто выступает низкокардинальным фильтром. Сортировка похожих значений рядом улучшает пропуск ненужных гранул данных и сжатие: соседние строки повторяют категории, статусы и близкие временные метки, поэтому кодеки `ZSTD` и `Delta` работают эффективнее.

## Движки

| Таблица | Движок | Назначение |
|---|---|---|
| `orders_flat` | `MergeTree` | Основная OLAP-таблица фактов. Одна строка = одна позиция заказа. |
| `orders_ttl` | `MergeTree` с TTL | Демонстрация TTL: строки старше 90 дней удаляются после слияния частей. |
| `monthly_sales` | `SummingMergeTree` | Месячный агрегат по категории и региону. |

`mv_monthly_sales` — материализованное представление поверх `orders_flat`. Каждый вставляемый блок агрегируется и записывается в `monthly_sales`, поэтому повторяющиеся отчеты читают меньше строк.

## Сжатие

Лучше всего сжимаются:

- `order_status`, `category`, `region`: мало различных значений, поэтому `LowCardinality` и сортировка дают компактные словари и длинные серии повторов.
- `order_date`, `order_datetime`, числовые идентификаторы: значения меняются постепенно, поэтому `Delta` вместе с `ZSTD` сжимает разности, а не полные значения.
- `price` и `line_total`: цены каталога и набор количеств повторяются, поэтому хорошо подходят для `Delta` и `ZSTD`.

Хуже сжимаются высококардинальные строки, например `customer_name`, если они не вынесены в словарь. Email хранится как `LowCardinality`, потому что генератор специально переиспользует 250 клиентов на 1 000 000 строк.

## Сравнение PostgreSQL и ClickHouse

Сторона PostgreSQL основана на 3NF-скриптах из ИДЗ-1. Сторона ClickHouse использует ту же предметную область, но хранит плоскую аналитическую таблицу фактов.

| Запрос / операция | PostgreSQL 3NF | ClickHouse, плоская таблица | Вывод |
|---|---:|---:|---|
| Вставка 1 строки | Быстрая транзакционная вставка, около 1-5 мс локально | Не целевой сценарий; лучше пакетная вставка | PostgreSQL лучше подходит для OLTP-записей. |
| Вставка 1 000 000 строк | Нужны множественные вставки или промежуточная таблица | Один пакет `INSERT SELECT FROM numbers()` | ClickHouse лучше подходит для пакетной загрузки. |
| Топ-10 товаров на 1M строк | Нужны JOIN от позиций заказа к товарам | Сканирование и агрегация одной таблицы | ClickHouse убирает стоимость JOIN. |
| JOIN 4 таблиц | Нужен для нормализованного отчета | Не нужен в плоской модели | Денормализация подходит для OLAP-чтения. |
| Обновление статуса | Нативная транзакция `UPDATE` | Мутации есть, но это не основная нагрузка | PostgreSQL лучше для частых обновлений. |
| Размер на диске для 1M строк | Строковое хранение плюс индексы | Сжатые колоночные части | ClickHouse компактнее хранит повторяющиеся аналитические данные. |
| Поиск по подстроке email | `ILIKE` / trigram index | Сканирование через `positionCaseInsensitive` | PostgreSQL выигрывает для селективного индексного поиска; ClickHouse приемлем для аналитического скана. |

Точные времена зависят от CPU, диска, ограничений Docker и прогрева кэша. Файл `checks/pg_vs_ch_comparison.txt` фиксирует методику и локальные значения из этого запуска.

## Файлы

- `sql/01_create_db.sql`: создание базы и проверочный запрос подключения.
- `sql/02_orders_flat.sql`: основная таблица `MergeTree`.
- `sql/03_orders_ttl.sql`: таблица с TTL.
- `sql/04_monthly_sales.sql`: таблица `SummingMergeTree` и материализованное представление.
- `sql/05_queries.sql`: пять бизнес-запросов.
- `sql/06_system_tables.sql`: сжатие, размеры таблиц и `system.parts`.
- `scripts/generate_data.sh`: детерминированная генерация не менее 1M строк.
- `scripts/ttl_demo.sh`: вставка старых строк, `OPTIMIZE` и проверка TTL.
- `scripts/pg_to_ch.sh`: опциональный перенос из PostgreSQL в ClickHouse через CSV.
- `config/users.xml`: профиль `readonly` и пользователь `analyst`.
- `config/config.d/listen.xml`: ClickHouse слушает все интерфейсы.

## Как сохранить вывод проверок

```sh
docker compose exec clickhouse clickhouse-client --time --queries-file /sql/05_queries.sql > checks/all_queries.txt
docker compose exec clickhouse clickhouse-client --time --queries-file /sql/06_system_tables.sql > checks/compression_stats.txt
docker compose exec clickhouse sh /scripts/ttl_demo.sh > checks/ttl_demo.txt
```
