#!/usr/bin/env python3
"""
Fetch daily stock prices from Stooq (no API key).

Public API:
    get_stooq_closes(ticker: str, days: int) -> list[float]

CLI:
    python stooq_cli.py aapl 250
    python stooq_cli.py aapl.us 10
"""

import argparse
import csv
import io
import json
import sys
from datetime import datetime
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError


# ---------------------------
# Internal helpers
# ---------------------------

def _normalize_ticker(ticker: str) -> str:
    """Append .us suffix if no market suffix is present."""
    ticker = ticker.lower().strip()
    if "." not in ticker:
        ticker += ".us"
    return ticker


def _fetch_stooq_csv(ticker: str) -> str:
    url = f"https://stooq.com/q/d/l/?s={ticker}&i=d"
    req = Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (stooq_cli)"},
    )
    with urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def _parse_csv(csv_text: str):
    f = io.StringIO(csv_text)
    reader = csv.DictReader(f)

    rows = []
    for r in reader:
        if not r.get("Date"):
            continue
        try:
            close = float(r["Close"])
            rows.append(
                {
                    "date": r["Date"],
                    "open": float(r["Open"]),
                    "high": float(r["High"]),
                    "low": float(r["Low"]),
                    "close": close,
                    "volume": int(float(r["Volume"])),
                }
            )
        except Exception:
            continue

    rows.sort(key=lambda x: x["date"])
    return rows


# ---------------------------
# PUBLIC FUNCTION (API)
# ---------------------------

def get_stooq_closes(ticker: str, days: int) -> list[float]:
    """
    Download daily prices from Stooq and return last N closing prices.

    Args:
        ticker: Symbol without or with suffix (e.g. "AAPL" or "aapl.us")
        days: Number of most recent trading days

    Returns:
        List of closing prices (float), oldest -> newest
    """
    if days <= 0:
        raise ValueError("days must be > 0")

    ticker = _normalize_ticker(ticker)
    csv_text = _fetch_stooq_csv(ticker)
    rows = _parse_csv(csv_text)

    if not rows:
        return []

    rows = rows[-days:]
    return [r["close"] for r in rows]


# ---------------------------
# CLI
# ---------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ticker")
    ap.add_argument("days", type=int)
    args = ap.parse_args()

    ticker = _normalize_ticker(args.ticker)

    try:
        csv_text = _fetch_stooq_csv(ticker)
        prices = _parse_csv(csv_text)
    except (HTTPError, URLError) as e:
        print(f"Error fetching data: {e}", file=sys.stderr)
        sys.exit(1)

    if not prices:
        print(
            json.dumps(
                {
                    "ticker": args.ticker,
                    "count": 0,
                    "prices": [],
                    "error": "No data returned from Stooq",
                },
                indent=2,
            )
        )
        sys.exit(0)

    prices = prices[-args.days :]

    out = {
        "source": "stooq",
        "ticker": ticker,
        "requested_days": args.days,
        "count": len(prices),
        "prices": prices,
        "generated_at_utc": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
