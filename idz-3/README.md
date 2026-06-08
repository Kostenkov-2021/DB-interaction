# ИДЗ-3. Репликация в ClickHouse

Костенков Данил Денисович, P4150

## Что сделано

В каталоге находится воспроизводимое окружение Docker Compose для репликации ClickHouse:

- 3 узла ClickHouse: `clickhouse1`, `clickhouse2`, `clickhouse3`.
- 3 отдельных узла ClickHouse Keeper: `keeper1`, `keeper2`, `keeper3`.
- Один кластер ClickHouse `idz3_cluster`: 1 шард, 3 реплики, `internal_replication=true`.
- Таблица `idz3.events` на движке `ReplicatedMergeTree`.
- Распределённая таблица `idz3.events_all` для чтения на уровне кластера.
- SQL для создания таблиц и загрузки не менее 150 000 строк.
- Автоматизированные проверки отказоустойчивости: потеря реплики, потеря кворума Keeper и детерминированное восстановление реплики.
- Текстовые результаты в `checks/`; скриншоты не используются.
- Диаграмма топологии PlantUML в `topology.puml`.

Порты на хосте намеренно отличаются от стандартных портов ClickHouse, чтобы не конфликтовать с предыдущими заданиями:

| Узел | HTTP | Нативный TCP |
|---|---:|---:|
| `clickhouse1` | `18123` | `19000` |
| `clickhouse2` | `18124` | `19001` |
| `clickhouse3` | `18125` | `19002` |

Keeper намеренно вынесен в отдельные контейнеры. Такая топология использует больше контейнеров, чем минимальный вариант с совмещением ролей, зато потеря кворума Keeper и потеря реплики ClickHouse становятся независимыми экспериментами.

## Как запустить

```sh
cd idz-3
make up
```

Проверить контейнеры:

```sh
make status
```

Создать реплицированные объекты:

```sh
make create
```

Загрузить начальный набор данных в реплику 1:

```sh
make insert
```

## Ручные проверки

Состояние Keeper:

```sh
docker compose exec -T keeper1 bash -lc "exec 3<>/dev/tcp/127.0.0.1/9181; printf 'ruok\n' >&3; timeout 2 cat <&3 || true"
docker compose exec -T keeper1 bash -lc "exec 3<>/dev/tcp/127.0.0.1/9181; printf 'mntr\n' >&3; timeout 2 cat <&3 || true"
docker compose exec -T keeper2 bash -lc "exec 3<>/dev/tcp/127.0.0.1/9181; printf 'mntr\n' >&3; timeout 2 cat <&3 || true"
docker compose exec -T keeper3 bash -lc "exec 3<>/dev/tcp/127.0.0.1/9181; printf 'mntr\n' >&3; timeout 2 cat <&3 || true"
```

Проверить, что `events` существует на всех репликах:

```sh
docker compose exec -T clickhouse1 clickhouse-client --query "
SELECT hostName(), database, name, engine
FROM clusterAllReplicas('idz3_cluster', system.tables)
WHERE database = 'idz3' AND name = 'events'
ORDER BY hostName()
"
```

Сравнить количество строк и хеши данных между репликами:

```sh
docker compose exec -T clickhouse1 clickhouse-client --query "
SELECT
    hostName() AS host,
    count() AS rows,
    sum(cityHash64(event_time, event_type, user_id, payload)) AS data_hash
FROM clusterAllReplicas('idz3_cluster', idz3.events)
GROUP BY host
ORDER BY host
"
```

Проверить `system.replicas`:

```sh
docker compose exec -T clickhouse1 clickhouse-client --query "
SELECT
    database, table, replica_name,
    is_leader, total_replicas, active_replicas,
    queue_size, inserts_in_queue, merges_in_queue,
    log_pointer, last_queue_update
FROM system.replicas
WHERE database = 'idz3' AND table = 'events'
FORMAT Vertical
"
```

## Автоматизированные проверки отказоустойчивости

Запустить все требуемые эксперименты и сохранить текстовые логи:

```sh
make test-failover
```

Скрипт создаёт или обновляет:

- `checks/keeper_health.txt`
- `checks/replicas_status_node1.txt`
- `checks/replicas_status_node2.txt`
- `checks/replicas_status_node3.txt`
- `checks/replication_initial_consistency.txt`
- `checks/experiment_a.txt`
- `checks/experiment_b.txt`
- `checks/experiment_c.txt`
- `checks/replication_queue.txt`

## Эксперименты

Эксперимент A останавливает `clickhouse3`, вставляет новые строки через `clickhouse1`, проверяет получение данных на `clickhouse2`, запускает `clickhouse3`, кратко останавливает очередь командой `SYSTEM STOP REPLICATION QUEUES`, чтобы зафиксировать `system.replication_queue`, затем снова запускает очередь, выполняет `SYSTEM SYNC REPLICA` и проверяет `queue_size = 0`.

Эксперимент B останавливает `keeper3`, проверяет, что два узла Keeper всё ещё образуют кворум, успешно вставляет строки, останавливает `keeper2`, фиксирует ошибку вставки без кворума и показывает, что локальный `SELECT` продолжает работать.

Эксперимент C останавливает `clickhouse2`, вставляет строки через `clickhouse1`, запускает `clickhouse2`, синхронизирует реплику и сравнивает количество строк и хеши. ClickHouse не допускает конфликтующих историй реплик, потому что вставки упорядочиваются через журнал репликации в Keeper.

## Наблюдение за репликами

Записать периодические снимки `system.replicas` в текстовый лог:

```sh
make watch-replicas
```

Лог сохраняется в `checks/replicas_watch.log`.

## Файлы

- `docker-compose.yml`: 3 узла ClickHouse и 3 узла ClickHouse Keeper.
- `config/keeper/keeper*.xml`: конфигурация RAFT-кворума Keeper.
- `config/clickhouse/cluster.xml`: `remote_servers`, адреса Keeper и сетевой слушатель.
- `config/clickhouse/users.xml`: одинаковая конфигурация пользователя `default` для межрепликовых запросов.
- `config/clickhouse/node*_macros.xml`: макросы каждой реплики для имён шарда и реплики.
- `sql/01_create_table.sql`: база данных, реплицированная таблица, распределённая таблица и проверка существования таблиц.
- `sql/02_insert_data.sql`: начальная детерминированная загрузка 150 000 событий.
- `scripts/generate_events.sh`: параметризованный скрипт вставки событий.
- `scripts/run_failover_tests.sh`: автоматизированные эксперименты A, B и C.
- `scripts/status_replicas.sh`: логирование `system.replicas` в режиме наблюдения.
- `topology.puml`: диаграмма топологии.

## Очистка

```sh
make down
```

Чтобы также удалить Docker-тома:

```sh
docker compose down -v
```
