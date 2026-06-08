#!/usr/bin/env python3
"""Сгенерировать детерминированные INSERT-операторы для таблицы orders_raw."""

from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

PRODUCTS = [
    ("Laptop Pro 15", Decimal("125000")),
    ("Wireless Mouse", Decimal("1900")),
    ("Mechanical Keyboard", Decimal("6500")),
    ("USB-C Hub", Decimal("4200")),
    ("Monitor 27", Decimal("31000")),
    ("Desk Mat", Decimal("1200")),
    ("Web Camera", Decimal("7900")),
    ("Headphones", Decimal("11500")),
    ("Smartphone X", Decimal("84000")),
    ("Tablet Air", Decimal("56000")),
    ("External SSD 1TB", Decimal("9800")),
    ("Router AX3000", Decimal("7200")),
]

STATUSES = ["new", "paid", "shipped", "delivered", "cancelled"]


def sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def row(order_id: int) -> str:
    customer_no = (order_id - 1) % 250 + 1
    order_date = date(2026, 1, 1) + timedelta(days=(order_id - 1) % 150)
    item_count = 1 + order_id % 3
    items = []

    for line_no in range(1, item_count + 1):
        name, price = PRODUCTS[(order_id + line_no - 1) % len(PRODUCTS)]
        quantity = 1 + ((order_id + line_no) % 4)
        items.append((name, price, quantity))

    total = sum(price * quantity for _, price, quantity in items)
    product_names = ", ".join(name for name, _, _ in items)
    product_prices = ", ".join(str(price) for _, price, _ in items)
    product_quantities = ", ".join(str(quantity) for _, _, quantity in items)

    values = [
        str(order_id),
        sql_text(order_date.isoformat()),
        sql_text(f"Customer {customer_no:03d}"),
        sql_text(f"customer{customer_no:03d}@shop.test"),
        sql_text(f"+7-900-{(order_id - 1) % 1000:03d}-{(order_id * 17) % 100:02d}-{(order_id * 31) % 100:02d}"),
        sql_text(f"City {(order_id - 1) % 25 + 1}, Street {(order_id - 1) % 80 + 1}, building {(order_id - 1) % 40 + 1}"),
        sql_text(product_names),
        sql_text(product_prices),
        sql_text(product_quantities),
        str(total),
        sql_text(STATUSES[order_id % len(STATUSES)]),
    ]
    return "(" + ", ".join(values) + ")"


def main() -> None:
    print("INSERT INTO orders_raw (order_id, order_date, customer_name, customer_email, customer_phone, delivery_address, product_names, product_prices, product_quantities, total_amount, status)")
    print("VALUES")
    print(",\n".join(row(order_id) for order_id in range(1, 1201)) + ";")


if __name__ == "__main__":
    main()
