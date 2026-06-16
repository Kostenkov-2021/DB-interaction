SHELL := /bin/sh
COMPOSE ?= docker compose
ROWS ?= 5000000

.PHONY: up down status init load test fault logs clean

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

status:
	$(COMPOSE) ps
	$(COMPOSE) exec -T ch-s1-r1 clickhouse-client --query "SELECT cluster, shard_num, replica_num, host_name, is_local FROM system.clusters WHERE cluster = 'production' ORDER BY shard_num, replica_num FORMAT PrettyCompact"

init:
	$(COMPOSE) exec -T ch-s1-r1 clickhouse-client --multiquery --queries-file /sql/01_create_tables.sql

load:
	$(COMPOSE) exec -T ch-s1-r1 sh /scripts/generate_data.sh $(ROWS)

test:
	$(COMPOSE) exec -T ch-s1-r1 sh /scripts/run_checks.sh

fault:
	$(COMPOSE) exec -T ch-s1-r1 true
	sh ./scripts/fault_injection.sh

logs:
	$(COMPOSE) logs --tail=100

clean:
	$(COMPOSE) down -v
