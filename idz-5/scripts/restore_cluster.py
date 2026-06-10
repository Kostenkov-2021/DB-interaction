#!/usr/bin/env python3
import argparse
import json
import urllib.error
import urllib.request


def sql(http_base: str, query: str) -> list[dict]:
    req = urllib.request.Request(f"{http_base}/sql?mode=raw", data=query.encode("utf-8"), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc


def try_sql(http_base: str, query: str) -> None:
    try:
        result = sql(http_base, query)
        print(f"OK: {query}")
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as exc:
        print(f"SKIP/ERROR: {query}")
        print(exc)


def main() -> None:
    parser = argparse.ArgumentParser(description="Restore ManticoreSearch cluster status after full Docker restart.")
    parser.add_argument("--primary-http", default="http://127.0.0.1:19308")
    parser.add_argument("--replica-http", default="http://127.0.0.1:29308")
    parser.add_argument("--cluster", default="products_cluster")
    parser.add_argument("--table", default="products")
    parser.add_argument("--primary-node", default="172.28.5.11:9312")
    args = parser.parse_args()

    try_sql(args.primary_http, f"CREATE CLUSTER {args.cluster}")
    try_sql(args.primary_http, f"SET CLUSTER {args.cluster} GLOBAL 'pc.bootstrap' = 1")
    try_sql(args.primary_http, f"ALTER CLUSTER {args.cluster} ADD {args.table}")
    try_sql(args.replica_http, f"JOIN CLUSTER {args.cluster} AT '{args.primary_node}'")
    try_sql(args.primary_http, f"SET CLUSTER {args.cluster} GLOBAL 'pc.bootstrap' = 1")
    try_sql(args.primary_http, "SHOW STATUS LIKE 'cluster%'")


if __name__ == "__main__":
    main()
