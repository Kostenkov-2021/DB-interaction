#!/usr/bin/env python3
import argparse
import csv
import json
import random
import time
import urllib.parse
import urllib.request
import urllib.error
from datetime import datetime, timedelta, timezone
from pathlib import Path


CATEGORIES = ["headphones", "speakers", "laptops", "phones", "tablets", "monitors", "keyboards", "cameras"]
BRANDS = ["Aster", "Northline", "Voltix", "SonicPro", "ByteWave", "Lumio", "RedPeak", "Orion"]
COLORS = ["black", "white", "silver", "blue", "red", "green"]
MATERIALS = ["plastic", "aluminium", "steel", "fabric", "glass"]

WORDS = {
    "headphones": ["wireless", "bluetooth", "noise cancelling", "over ear", "deep bass", "microphone"],
    "speakers": ["portable speaker", "bluetooth", "waterproof", "loud sound", "battery", "outdoor"],
    "laptops": ["gaming laptop", "ultrabook", "fast processor", "rtx graphics", "ssd", "portable workstation"],
    "phones": ["smart phone", "phone camera", "black phone", "wireless charging", "oled display", "dual sim"],
    "tablets": ["tablet", "stylus", "portable screen", "reading mode", "long battery", "education"],
    "monitors": ["gaming monitor", "ips panel", "high refresh", "hdr", "office display", "thin bezel"],
    "keyboards": ["mechanical keyboard", "wireless keyboard", "rgb", "quiet switches", "gaming", "compact"],
    "cameras": ["mirrorless camera", "4k video", "stabilization", "portrait lens", "travel", "creator kit"],
}

RU_WORDS = [
    "игровой", "беспроводной", "портативный", "черный", "быстрый",
    "надежный", "каталог", "товар", "скидка", "новинка",
]


def sql(http_base: str, query: str) -> dict:
    req = urllib.request.Request(f"{http_base}/sql?mode=raw", data=query.encode("utf-8"), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc


def sql_script(http_base: str, script: str) -> list[dict]:
    script = "\n".join(line for line in script.splitlines() if not line.strip().startswith("--"))
    results = []
    for statement in script.split(";"):
        statement = statement.strip()
        if statement:
            results.append(sql(http_base, statement))
    return results


def bulk_insert(http_base: str, docs: list[dict], index: str, cluster: str | None = None) -> None:
    lines = []
    for doc in docs:
        action = {"index": index, "id": doc.pop("id"), "doc": doc}
        if cluster:
            action["cluster"] = cluster
        lines.append(json.dumps({"insert": action}, ensure_ascii=False))
    payload = ("\n".join(lines) + "\n").encode("utf-8")
    req = urllib.request.Request(f"{http_base}/bulk", data=payload, method="POST")
    req.add_header("Content-Type", "application/x-ndjson")
    try:
        response = urllib.request.urlopen(req, timeout=120)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc
    with response:
        body = response.read().decode("utf-8")
        if '"errors":true' in body:
            raise RuntimeError(body[:1000])


def configure_cluster(primary_http: str, replica_http: str) -> None:
    for query in (
        "CREATE CLUSTER products_cluster",
        "ALTER CLUSTER products_cluster ADD products",
    ):
        try:
            sql(primary_http, query)
        except Exception as exc:
            print(f"Кластер: команда `{query}` пропущена: {exc}")
    try:
        sql(replica_http, "JOIN CLUSTER products_cluster AT 'manticore-1:9312'")
    except Exception as exc:
        print(f"Кластер: JOIN второго узла пропущен: {exc}")


def make_product(item_id: int, rnd: random.Random) -> dict:
    category = CATEGORIES[item_id % len(CATEGORIES)]
    brand = BRANDS[(item_id * 7) % len(BRANDS)]
    color = COLORS[(item_id * 5) % len(COLORS)]
    material = MATERIALS[(item_id * 3) % len(MATERIALS)]
    terms = WORDS[category]
    main_term = terms[item_id % len(terms)]
    extra_term = terms[(item_id + 2) % len(terms)]
    ru = " ".join(rnd.sample(RU_WORDS, 3))
    gaming = "gaming" in main_term or category in {"laptops", "monitors", "keyboards"} and item_id % 3 == 0
    wireless = "wireless" in main_term or "bluetooth" in main_term or item_id % 4 == 0
    title = f"{brand} {main_term.title()} {item_id:06d}"
    description = (
        f"<p>{title} with {extra_term}, {color} finish and {material} body. "
        f"Designed for catalog search demos: wireless bluetooth headphones, portable speaker, "
        f"noise cancelling mode, laptop performance and phone accessories appear in controlled proportions. "
        f"{ru}.</p>"
    )
    created_at = datetime(2026, 1, 1, tzinfo=timezone.utc) - timedelta(days=item_id % 730)
    return {
        "id": item_id,
        "title": title,
        "description": description,
        "category": category,
        "brand": brand,
        "price": round(990 + (item_id * 37 % 149000) + rnd.random(), 2),
        "rating": round(3.0 + ((item_id * 13) % 20) / 10, 1),
        "reviews_count": (item_id * 17) % 5000,
        "in_stock": item_id % 11 != 0,
        "tags": {
            "color": color,
            "material": material,
            "wireless": wireless,
            "gaming": gaming,
            "memory": ["8gb", "16gb", "32gb", "64gb"][item_id % 4],
        },
        "created_at": int(created_at.timestamp()),
    }


def write_csv(path: Path, count: int, seed: int) -> None:
    rnd = random.Random(seed)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        fieldnames = [
            "id", "title", "description", "category", "brand", "price",
            "rating", "reviews_count", "in_stock", "tags", "created_at",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for item_id in range(1, count + 1):
            row = make_product(item_id, rnd)
            row["tags"] = json.dumps(row["tags"], ensure_ascii=False)
            writer.writerow(row)


def try_sdk_check(host: str, port: int) -> str:
    try:
        import manticoresearch  # type: ignore
        from manticoresearch.api import utils_api  # type: ignore

        config = manticoresearch.Configuration(host=f"http://{host}:{port}")
        client = manticoresearch.ApiClient(config)
        utils = utils_api.UtilsApi(client)
        utils.sql("SHOW TABLES")
        return "SDK-проверка: пакет manticoresearch подключился успешно."
    except Exception as exc:
        return f"SDK-проверка пропущена: {exc.__class__.__name__}: {exc}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate and load product catalog into ManticoreSearch.")
    parser.add_argument("--count", type=int, default=100_000)
    parser.add_argument("--batch-size", type=int, default=2_000)
    parser.add_argument("--seed", type=int, default=4150)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--http-port", type=int, default=19308)
    parser.add_argument("--replica-http-port", type=int, default=29308)
    parser.add_argument("--skip-cluster", action="store_true")
    parser.add_argument("--csv", type=Path, default=Path("generated/products.csv"))
    parser.add_argument("--skip-load", action="store_true")
    args = parser.parse_args()

    if args.count < 100_000:
        raise SystemExit("Для задания нужно не менее 100000 товаров.")

    http_base = f"http://{args.host}:{args.http_port}"
    print(try_sdk_check(args.host, args.http_port))
    write_csv(args.csv, args.count, args.seed)
    print(f"CSV подготовлен: {args.csv} ({args.count} строк)")

    if args.skip_load:
        return

    ddl = Path(__file__).resolve().parents[1] / "sql" / "01_create_index.sql"
    sql_script(http_base, ddl.read_text(encoding="utf-8"))
    target_index = "products"
    target_cluster = None
    if not args.skip_cluster:
        configure_cluster(http_base, f"http://{args.host}:{args.replica_http_port}")
        target_cluster = "products_cluster"

    rnd = random.Random(args.seed)
    batch = []
    started = time.perf_counter()
    for item_id in range(1, args.count + 1):
        batch.append(make_product(item_id, rnd))
        if len(batch) >= args.batch_size:
            bulk_insert(http_base, batch, target_index, target_cluster)
            batch = []
    if batch:
        bulk_insert(http_base, batch, target_index, target_cluster)

    elapsed = time.perf_counter() - started
    result = sql(http_base, "SELECT COUNT(*) AS cnt FROM products")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"Загружено {args.count} товаров за {elapsed:.2f} с")


if __name__ == "__main__":
    main()
