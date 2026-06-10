# ИДЗ-5. ManticoreSearch: полнотекстовый поиск и NoSQL-подход

Костенков Данил Денисович, P4150

## Что сделано

В каталоге собран воспроизводимый стенд для поиска по каталогу товаров:

- Docker Compose с двумя узлами ManticoreSearch и PostgreSQL для сравнения.
- RT-индекс `products` с текстовыми полями, атрибутами, JSON-тегами и настройками морфологии.
- Скрипт генерации и загрузки не менее 100 000 товаров.
- SQL-запросы для базового поиска, точной фразы, proximity, фильтрации по атрибутам, JSON, фасетов, `UPDATE`, `DELETE`, `REPLACE`, `HIGHLIGHT()`, `CALL KEYWORDS` и percolate-индекса.
- SQL-сценарий кластерной репликации `products_cluster` на двух узлах Manticore.
- Текстовые результаты проверок в `checks/`; скриншоты не используются.

## Запуск

```sh
cd idz-5
docker compose up -d
```


Порты вынесены из стандартного диапазона, чтобы не конфликтовать с предыдущими заданиями:

| Сервис | MySQL/TCP | HTTP | Комментарий |
|---|---:|---:|---|
| `manticore-1` | `19306` | `19308` | основной узел |
| `manticore-2` | `29306` | `29308` | второй узел для кластера |
| `postgres` | `15432` | - | сравнение через `tsvector` + GIN |

Проверка подключений:

```sh
mysql -h 127.0.0.1 -P 19306
curl -s http://localhost:19308/sql -d "query=SHOW TABLES"
# Для ManticoreSearch 6/7 с DDL и SHOW используется raw-режим:
curl -s "http://localhost:19308/sql?mode=raw" -d "SHOW TABLES"
```

Создание RT-индекса:

```sh
mysql -h 127.0.0.1 -P 19306 < sql/01_create_index.sql
```

Загрузка 100 000 товаров и подключение второго узла к кластеру:

```sh
python -m pip install -r requirements.txt
python scripts/load_products.py --count 100000 --host 127.0.0.1 --http-port 19308
```

Автоматический прогон проверок и обновление текстовых отчётов:

```sh
python scripts/run_checks.py --manticore-http http://127.0.0.1:19308 --pg-dsn "postgresql://postgres:postgres@127.0.0.1:15432/postgres"
```

Если оба узла Manticore были одновременно перезапущены, восстановить primary view и снова раскрыть `SHOW STATUS LIKE 'cluster%'` можно без перезагрузки данных:

```sh
python scripts/restore_cluster.py
```

Восстановление делает три вещи: поднимает primary view через `pc.bootstrap`, добавляет `products` обратно в `products_cluster`, если нужно, и присоединяет второй узел по стабильному адресу `172.28.5.11:9312`.

## RT-индекс

Индекс создаётся в `sql/01_create_index.sql`:

```sql
CREATE TABLE products (
    title         text,
    description   text,
    category      string,
    brand         string,
    price         float,
    rating        float,
    reviews_count integer,
    in_stock      bool,
    tags          json,
    created_at    timestamp
) morphology='stem_enru' min_word_len='2' html_strip='1';
```

`morphology='stem_enru'` включает стемминг для английского и русского языков. Поэтому формы вроде `headphones/headphone`, `игровой/игровые` приводятся к более общему корню и лучше находятся одним запросом.

`min_word_len='2'` разрешает индексировать короткие слова от двух символов. Для каталога это важно из-за моделей, серий, размеров и коротких технических обозначений. Слишком маленькое значение увеличивает индекс, но делает поиск по товарным характеристикам полезнее.

`html_strip='1'` удаляет HTML-разметку из текстовых полей перед индексированием. В описаниях товаров часто встречаются `<p>`, `<b>`, списки и маркетинговая верстка; поисковый индекс должен хранить смысловой текст, а не теги.

RT-индекс отличается от plain-индекса тем, что принимает `INSERT`, `REPLACE`, `UPDATE` и `DELETE` без полной переиндексации внешнего источника. Plain-индекс строится отдельным индексатором по источнику данных и удобен для пакетных перестроений, а RT-индекс ближе к NoSQL-хранилищу документов: приложение пишет документы прямо в поисковый движок.

## Данные

Данные генерируются скриптом `scripts/load_products.py`. Генератор детерминированный: используется фиксированный seed, поэтому один и тот же `--count` создаёт одинаковый набор товаров.

В товаре есть:

- `title` и `description` с поисковыми словами на английском и русском;
- фасетные поля `category`, `brand`;
- числовые атрибуты `price`, `rating`, `reviews_count`;
- булево поле `in_stock`;
- JSON `tags` с цветом, материалом, памятью, беспроводным режимом и признаком gaming.

Загрузка выполняется через HTTP `/bulk`. Скрипт не требует внешних библиотек для основной загрузки, но при наличии пакета `manticoresearch` выполняет короткую SDK-проверку соединения, чтобы зафиксировать использование Python-подключения к ManticoreSearch.

## Полнотекстовый поиск

Основные запросы лежат в `sql/02_search_queries.sql`, результаты - в отдельных файлах `checks/`.

Проверяются:

- базовый BM25-поиск: `wireless bluetooth headphones`;
- точная фраза: `"noise cancelling"`;
- proximity: `"portable speaker"~3`;
- сочетание полнотекстового поиска и фильтров: `MATCH('laptop')`, диапазон цены, рейтинг;
- поиск по JSON-атрибуту: `tags.color = 'black'`;
- подсветка найденных фрагментов через `HIGHLIGHT()`;
- разбор ключевых слов через `CALL KEYWORDS`.

Manticore ранжирует документы через BM25-подобную модель и возвращает вес `WEIGHT()`. Для каталога это удобнее обычного `LIKE`, потому что учитываются частота терминов, редкость слов и текстовая релевантность.

## Фасетный поиск

Фасетный поиск нужен в e-commerce для фильтров каталога: после запроса `gaming` пользователь видит доступные категории, бренды, ценовые группы и количество товаров в каждой группе. Это позволяет строить интерфейс фильтрации без отдельных тяжёлых запросов к основной БД.

В `sql/03_facets.sql` есть два варианта:

- обычная агрегация `GROUP BY category` с `COUNT(*)` и `AVG(price)`;
- нативный `FACET category`, `FACET brand`, который возвращает основной результат поиска и распределения по фильтрам.

## Обновление, удаление, замена

Операции из `sql/04_update_delete.sql` демонстрируют NoSQL-аспект RT-индекса:

- `UPDATE` меняет атрибуты существующего документа, например цену и рейтинг;
- `DELETE` удаляет документ из индекса, после чего поиск его не возвращает;
- `REPLACE` заменяет документ целиком по тому же id.

Отличие от PostgreSQL принципиальное: ManticoreSearch не является транзакционной OLTP-СУБД. В PostgreSQL `UPDATE` участвует в ACID-транзакции, может быть откатан, связан с внешними ключами и MVCC. В Manticore `UPDATE` предназначен для поискового индекса и обновляет атрибуты документа без привычной транзакционной модели; в кластере репликация может иметь небольшую задержку, то есть поведение ближе к eventual consistency.

## Репликация ManticoreSearch

В compose поднимаются два узла. Для автоматической репликации используется кластер `products_cluster`:

```sql
CREATE CLUSTER products_cluster;
ALTER CLUSTER products_cluster ADD products;
JOIN CLUSTER products_cluster AT 'manticore-1:9312';
```

DDL для таблицы выполняется на первом узле, затем таблица добавляется в кластер, а второй узел присоединяется к нему, что демонстрирует кластер из 2+ узлов и репликацию RT-таблицы между ними.

Отдельный SQL-сценарий с этими командами вынесен в `sql/07_cluster_replication.sql`.

## Percolate-запросы

Percolate-индекс решает обратную задачу поиска: сначала сохраняются запросы, а затем новый документ проверяется на совпадение с ними. Для каталога это сценарий уведомлений: "сообщить, когда появится игровой ноутбук с похожим описанием".

Пример находится в `sql/06_percolate.sql`.

## Сравнение с PostgreSQL и ClickHouse

PostgreSQL-сценарий лежит в `sql/05_pg_comparison.sql`. На той же структуре данных создаётся `tsvector` и GIN-индекс:

```sql
ALTER TABLE pg_products ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || description)) STORED;
CREATE INDEX idx_pg_products_tsv ON pg_products USING GIN(tsv);
```

ClickHouse в этом задании рассматривается как колоночное хранилище из предыдущих ИДЗ: оно хорошо агрегирует и сканирует большие наборы, но не является специализированным поисковым движком уровня Manticore.

| Характеристика | ManticoreSearch | PostgreSQL (`tsvector`) | ClickHouse |
|---|---|---|---|
| Время поиска на 100K документов | около 4-8 мс в проверке стенда | около 12-25 мс в проверке стенда | хорошо для сканов, хуже для релевантного FTS |
| Релевантность | BM25/`WEIGHT()`, поисковые операторы | `ts_rank`, словари PostgreSQL | в основном фильтрация/скоринг вручную |
| Морфология из коробки | `stem_enru`, морфология в настройке индекса | словари `english`, `russian`, конфигурации FTS | нет полноценного поискового пайплайна из коробки |
| Фасетный поиск | нативный `FACET` | через `GROUP BY` после FTS | сильная сторона через быстрые агрегации |
| JSON-атрибуты | JSON-атрибуты в документе | `jsonb` + индексы | JSON-функции и колоночные структуры |
| Транзакции | нет OLTP-транзакций | да, ACID/MVCC | ограниченно, не OLTP |
| Когда использовать | быстрый поиск, каталог, suggest, highlight, percolate | транзакционные данные и умеренный FTS рядом с OLTP | аналитика, отчёты, большие агрегации |

Вывод: ManticoreSearch стоит использовать как дополнительный поисковый контур рядом с PostgreSQL или ClickHouse. PostgreSQL остаётся источником транзакционной истины, ClickHouse - аналитическим хранилищем, Manticore - специализированным индексом для пользовательского поиска.

## Состав каталога

```text
idz-5/
├── README.md
├── docker-compose.yml
├── requirements.txt
├── config/
│   ├── manticore.conf
│   ├── manticore1.conf
│   └── manticore2.conf
├── sql/
│   ├── 01_create_index.sql
│   ├── 02_search_queries.sql
│   ├── 03_facets.sql
│   ├── 04_update_delete.sql
│   ├── 05_pg_comparison.sql
│   ├── 06_percolate.sql
│   └── 07_cluster_replication.sql
├── scripts/
│   ├── load_products.py
│   ├── run_checks.py
│   ├── restore_cluster.py
│   ├── compose.ps1
│   └── compose.cmd
└── checks/
    ├── connectivity.txt
    ├── cluster_status.txt
    ├── basic_search.txt
    ├── phrase_search.txt
    ├── proximity_search.txt
    ├── filtered_search.txt
    ├── json_search.txt
    ├── facets.txt
    ├── update_delete.txt
    └── pg_vs_manticore.txt
```
