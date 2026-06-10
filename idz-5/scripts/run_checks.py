#!/usr/bin/env python3
import argparse
import json
import time
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKS = ROOT / "checks"


SEARCH_CASES = {
    "basic_search.txt": """SELECT id, title, WEIGHT() AS w
FROM products
WHERE MATCH('wireless bluetooth headphones')
ORDER BY w DESC
LIMIT 10""",
    "phrase_search.txt": """SELECT id, title, WEIGHT() AS w
FROM products
WHERE MATCH('"noise cancelling"')
LIMIT 10""",
    "proximity_search.txt": """SELECT id, title, WEIGHT() AS w
FROM products
WHERE MATCH('"portable speaker"~3')
LIMIT 10""",
    "filtered_search.txt": """SELECT id, title, price, rating
FROM products
WHERE MATCH('laptop') AND price BETWEEN 30000 AND 80000 AND rating >= 4.0
ORDER BY rating DESC
LIMIT 10""",
    "json_search.txt": """SELECT id, title, tags
FROM products
WHERE MATCH('phone') AND tags.color = 'black'
LIMIT 10""",
}


def manticore_sql(http_base: str, query: str) -> tuple[dict, float]:
    req = urllib.request.Request(f"{http_base}/sql?mode=raw", data=query.encode("utf-8"), method="POST")
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc
    return result, (time.perf_counter() - started) * 1000


def manticore_script(http_base: str, script: str) -> tuple[list[dict], float]:
    script = "\n".join(line for line in script.splitlines() if not line.strip().startswith("--"))
    started = time.perf_counter()
    results = []
    for statement in script.split(";"):
        statement = statement.strip()
        if statement:
            result, _ = manticore_sql(http_base, statement)
            results.append(result)
    return results, (time.perf_counter() - started) * 1000


def manticore_script_best_effort(http_base: str, script: str) -> tuple[list[dict], float]:
    script = "\n".join(line for line in script.splitlines() if not line.strip().startswith("--"))
    started = time.perf_counter()
    results = []
    for statement in script.split(";"):
        statement = statement.strip()
        if not statement:
            continue
        try:
            result, elapsed = manticore_sql(http_base, statement)
            results.append({"statement": statement, "elapsed_ms": round(elapsed, 3), "result": result})
        except Exception as exc:
            results.append({"statement": statement, "error": str(exc)})
    return results, (time.perf_counter() - started) * 1000


def write_report(path: Path, title: str, query: str, result: dict, elapsed_ms: float) -> None:
    path.write_text(
        f"{title}\n"
        f"{'=' * len(title)}\n\n"
        f"Запрос:\n{query};\n\n"
        f"Время выполнения: {elapsed_ms:.3f} мс\n\n"
        f"Результат:\n{json.dumps(result, ensure_ascii=False, indent=2)}\n",
        encoding="utf-8",
    )


def write_mutation_demo(path: Path) -> None:
    path.write_text(
        """UPDATE, DELETE, REPLACE
=======================

Сценарий: sql/04_update_delete.sql

Отчётный `run_checks.py` по умолчанию не выполняет мутационные операции, чтобы не менять состояние реплицируемого RT-индекса во время проверки чтения. Для ручной демонстрации используйте:

python scripts/run_checks.py --run-mutations

UPDATE:
SELECT id, title, price, rating FROM products WHERE id = 42;
UPDATE products_cluster:products SET price = 49990, rating = 4.9 WHERE id = 42;
SELECT id, title, price, rating FROM products WHERE id = 42;

DELETE:
SELECT id, title FROM products WHERE id = 43;
DELETE FROM products_cluster:products WHERE id = 43;
SELECT id, title FROM products WHERE id = 43;

REPLACE:
REPLACE INTO products_cluster:products (...) VALUES
(44, 'Replaced gaming laptop with RTX graphics', ...);
SELECT id, title, price, rating, tags FROM products WHERE id = 44;

Комментарий:
RT-индекс поддерживает документные изменения без полной переиндексации. В кластере запись выполняется через имя `products_cluster:products`, чтобы изменение реплицировалось на второй узел. В отличие от PostgreSQL это не OLTP-транзакции с MVCC и rollback, а обновление поискового индекса.
""",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Run IDZ-5 checks and write text reports.")
    parser.add_argument("--manticore-http", default="http://127.0.0.1:19308")
    parser.add_argument("--replica-http", default="http://127.0.0.1:29308")
    parser.add_argument("--pg-dsn", default="")
    parser.add_argument("--run-mutations", action="store_true")
    args = parser.parse_args()

    CHECKS.mkdir(exist_ok=True)

    for query in (
        "CREATE CLUSTER products_cluster",
        "SET CLUSTER products_cluster GLOBAL 'pc.bootstrap' = 1",
        "ALTER CLUSTER products_cluster ADD products",
    ):
        try:
            manticore_sql(args.manticore_http, query)
        except Exception:
            pass
    try:
        manticore_sql(args.replica_http, "JOIN CLUSTER products_cluster AT '172.28.5.11:9312'")
    except Exception:
        pass
    try:
        manticore_sql(args.manticore_http, "SET CLUSTER products_cluster GLOBAL 'pc.bootstrap' = 1")
    except Exception:
        pass

    connectivity_query = "SHOW TABLES"
    result, elapsed = manticore_sql(args.manticore_http, connectivity_query)
    write_report(CHECKS / "connectivity.txt", "Проверка подключений", connectivity_query, result, elapsed)

    cluster_query = "SHOW STATUS LIKE 'cluster%'"
    result, elapsed = manticore_sql(args.manticore_http, cluster_query)
    write_report(CHECKS / "cluster_status.txt", "Статус кластера ManticoreSearch", cluster_query, result, elapsed)

    for filename, query in SEARCH_CASES.items():
        result, elapsed = manticore_sql(args.manticore_http, query)
        write_report(CHECKS / filename, filename.replace("_", " ").replace(".txt", ""), query, result, elapsed)

    facets_query = (ROOT / "sql" / "03_facets.sql").read_text(encoding="utf-8")
    result, elapsed = manticore_script(args.manticore_http, facets_query)
    write_report(CHECKS / "facets.txt", "Фасетный поиск и агрегации", facets_query, result, elapsed)

    update_query = (ROOT / "sql" / "04_update_delete.sql").read_text(encoding="utf-8")
    if args.run_mutations:
        result, elapsed = manticore_script_best_effort(args.manticore_http, update_query)
        write_report(CHECKS / "update_delete.txt", "UPDATE DELETE REPLACE", update_query, result, elapsed)
    else:
        write_mutation_demo(CHECKS / "update_delete.txt")

    comparison = {
        "manticore": "Запросы выполнены через HTTP API, реальные значения времени см. выше.",
        "postgresql": "Для фактического EXPLAIN ANALYZE используется sql/05_pg_comparison.sql после загрузки CSV.",
        "clickhouse": "Сравнение приведено в README как колоночное хранилище для аналитики.",
    }
    write_report(
        CHECKS / "pg_vs_manticore.txt",
        "Сравнение PostgreSQL и ManticoreSearch",
        "См. sql/05_pg_comparison.sql и README.md",
        comparison,
        0.0,
    )


if __name__ == "__main__":
    main()
