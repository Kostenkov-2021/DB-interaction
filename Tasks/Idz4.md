# ИДЗ-4. Шардирование в ClickHouse

## Цель

Развернуть шардированный кластер ClickHouse, разобраться с `Distributed`-движком,
ключами шардирования, стратегиями маршрутизации и убедиться, что данные
распределяются предсказуемо.

## Условия

- Кластер: **2 шарда, по 2 реплики** каждый (итого 4 узла ClickHouse).
- Keeper / ZooKeeper: кворум из 3 узлов.
- Развёртывание: Docker Compose.
- Все результаты — текстовые файлы и конфиги. **Скриншоты запрещены.**

## Задание

### Часть 1. Кластер 2x2

1. Описать кластер в `remote_servers`:
   ```xml
   <cluster_2x2>
     <shard>
       <replica><host>ch-s1-r1</host><port>9000</port></replica>
       <replica><host>ch-s1-r2</host><port>9000</port></replica>
     </shard>
     <shard>
       <replica><host>ch-s2-r1</host><port>9000</port></replica>
       <replica><host>ch-s2-r2</host><port>9000</port></replica>
     </shard>
   </cluster_2x2>
   ```
2. Настроить макросы `{shard}` и `{replica}` для каждого узла.
3. Проверить кластер: `SELECT * FROM system.clusters WHERE cluster = 'cluster_2x2'`.

### Часть 2. Локальные и распределённые таблицы

Предметная область — **события пользовательской аналитики** (clickstream).

1. Создать **локальную** таблицу на каждом шарде:
   ```sql
   CREATE TABLE events_local ON CLUSTER 'cluster_2x2' (
       event_date  Date,
       event_time  DateTime,
       user_id     UInt64,
       session_id  String,
       event_type  LowCardinality(String),
       page_url    String,
       duration_ms UInt32
   ) ENGINE = ReplicatedMergeTree(
       '/clickhouse/tables/{shard}/events_local',
       '{replica}'
   )
   PARTITION BY toYYYYMM(event_date)
   ORDER BY (user_id, event_time);
   ```

2. Создать **распределённую** таблицу:
   ```sql
   CREATE TABLE events_distributed ON CLUSTER 'cluster_2x2'
   AS events_local
   ENGINE = Distributed('cluster_2x2', default, events_local, xxHash64(user_id));
   ```

3. Объяснить в README выбор ключа шардирования `xxHash64(user_id)`:
   почему именно `user_id`, а не `event_date` или `rand()`.

### Часть 3. Наполнение и проверка распределения

1. Вставить **>= 2 000 000 строк** через `events_distributed`.
2. Проверить распределение данных по шардам:
   ```sql
   -- на каждом узле
   SELECT
       hostName() AS host,
       count()    AS rows
   FROM events_local;
   ```
3. Показать, что данные одного `user_id` всегда лежат на одном шарде:
   ```sql
   SELECT
       hostName(),
       uniq(user_id),
       count()
   FROM events_local;
   ```
4. Сохранить результаты в `checks/data_distribution.txt`.

### Часть 4. Запросы через Distributed

Выполнить и зафиксировать:

1. **Глобальный COUNT** — `SELECT count() FROM events_distributed` vs сумма локальных.
2. **GROUP BY с шардированным ключом** — top-10 пользователей по числу событий.
   Показать, что запрос эффективен (данные пользователя на одном шарде).
3. **GROUP BY без шардированного ключа** — top-10 страниц по числу визитов.
   Объяснить, почему здесь происходит shuffle между шардами.
4. **JOIN** — создать справочную таблицу `user_dict` (user_id, name, segment)
   на движке `ReplicatedMergeTree` и выполнить `JOIN` через Distributed.
   Описать проблему «broadcast JOIN» и все возможные способы её решить (например, `GLOBAL IN`).

Сохранить запросы и результаты в `checks/distributed_queries.txt`.

### Часть 5. Ребалансировка и добавление шарда

1. Добавить **третий шард** (2 реплики) в конфигурацию кластера.
2. Обновить `events_distributed` (или пересоздать).
3. Вставить новые данные — показать, что они уходят на 3 шарда.
4. Обсудить в README: что происходит со старыми данными?
   Как выполнить ребалансировку? (Описать подход, реализация не обязательна.)

## Структура репозитория

```
idz4/
├── README.md
├── docker-compose.yml
├── config/
│   ├── keeper/
│   │   └── ...
│   └── clickhouse/
│       ├── cluster.xml
│       ├── s1r1_macros.xml
│       ├── s1r2_macros.xml
│       ├── s2r1_macros.xml
│       └── s2r2_macros.xml
├── sql/
│   ├── 01_create_local.sql
│   ├── 02_create_distributed.sql
│   ├── 03_user_dict.sql
│   └── 04_queries.sql
├── scripts/
│   └── generate_clickstream.{py,sh}
└── checks/
    ├── cluster_info.txt
    ├── data_distribution.txt
    ├── distributed_queries.txt
    └── reshard_demo.txt
```

## Требования к коммитам

Коммиты должны быть **атомарными и осмысленными**.

Плохо:
```
git add .
git commit -m "add all"
```

Хорошо:
```
git commit -m "feat(idz4): add 2x2 cluster config with macros"
git commit -m "feat(idz4): add local and distributed table DDL"
git commit -m "feat(idz4): add clickstream generator (2M rows)"
git commit -m "test(idz4): verify data distribution across shards"
git commit -m "feat(idz4): add third shard and rebalance discussion"
```

## Критерии оценки

| Вес | Критерий |
|-----|----------|
| **15%** | Кластер 2x2 — корректная конфигурация, макросы, `system.clusters` |
| **20%** | DDL — локальные + распределённая таблица, обоснование ключа шардирования |
| **15%** | Генерация данных и проверка равномерности распределения |
| **25%** | Запросы через Distributed — корректность, объяснение shuffle и broadcast JOIN |
| **15%** | Добавление шарда, обсуждение ребалансировки |
| **5%**  | Структура репозитория, README, качество коммитов |
| **5%**  | JOIN и справочная таблица — DDL, запрос, объяснение проблемы |

## Важные моменты

- Топология кластера в PlantUML (`topology.puml`).
- Скрипт ребалансировки данных на новый шард (через `INSERT ... SELECT` между шардами).
- Сравнение производительности запросов с `GLOBAL IN` vs обычный `IN` (с `EXPLAIN`).
- Демонстрация `distributed_ddl` — показать лог в `system.distributed_ddl_queue`.
