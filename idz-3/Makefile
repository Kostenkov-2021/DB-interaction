COMPOSE=docker compose

.PHONY: up down status create insert test-failover watch-replicas

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

status:
	$(COMPOSE) ps
	$(COMPOSE) exec -T clickhouse1 clickhouse-client --query "SELECT hostName(), version()"

create:
	$(COMPOSE) exec -T clickhouse1 clickhouse-client --multiquery --queries-file /sql/01_create_table.sql

insert:
	$(COMPOSE) exec -T clickhouse1 clickhouse-client --multiquery --queries-file /sql/02_insert_data.sql

test-failover:
	sh ./scripts/run_failover_tests.sh

watch-replicas:
	$(COMPOSE) exec -T clickhouse1 sh /scripts/status_replicas.sh /checks/replicas_watch.log 2 30
