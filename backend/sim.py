from __future__ import annotations

import math
import random
from typing import Tuple

from backend import stooq


def get_prices_stooq(ticker: str, days: int = 252) -> list[float]:
    return stooq.get_stooq_closes(ticker, days)


def fake_price_history(ticker: str, days: int = 252) -> list[float]:
    seed = sum(ord(c) for c in ticker.upper())
    rng = random.Random(seed)

    price = 100.0 + (seed % 50)
    prices = [price]
    for _ in range(days - 1):
        r = rng.gauss(0.0003, 0.02)
        price *= (1.0 + r)
        if price < 1:
            price = 1.0
        prices.append(price)
    return prices


def mean_and_std(values: list[float]) -> Tuple[float, float]:
    n = len(values)
    if n < 2:
        return 0.0, 0.0
    m = sum(values) / n
    var = sum((x - m) ** 2 for x in values) / (n - 1)
    return m, math.sqrt(var)


def monte_carlo_gbm_metrics(
    prices: list[float],
    horizon_days: int = 30,
    simulations: int = 10_000,
) -> dict:
    if len(prices) < 3:
        raise ValueError("Need at least 3 prices")

    log_returns = [math.log(prices[i] / prices[i - 1]) for i in range(1, len(prices))]
    mu, sigma = mean_and_std(log_returns)

    s0 = prices[-1]
    dt = 1.0

    terminal_prices: list[float] = []
    loss_count = 0

    for _ in range(simulations):
        s = s0
        for _ in range(horizon_days):
            z = random.gauss(0.0, 1.0)
            s *= math.exp((mu - 0.5 * sigma * sigma) * dt + sigma * math.sqrt(dt) * z)
        terminal_prices.append(s)
        if s < s0:
            loss_count += 1

    terminal_prices.sort()
    expected_price = sum(terminal_prices) / simulations
    prob_loss = loss_count / simulations

    p5 = terminal_prices[max(0, int(0.05 * simulations) - 1)]
    var95_pct = (p5 - s0) / s0
    var_95 = max(0.0, s0 - p5)

    return {
        "current_price": round(s0, 2),
        "expected_future_price": round(expected_price, 2),
        "probability_of_loss": round(prob_loss, 4),
        "var_95": round(var_95, 2),

        # legacy keys (optional)
        "expected_price": round(expected_price, 2),
        "prob_loss": round(prob_loss, 4),
        "var95_pct": round(var95_pct, 4),

        "horizon_days": horizon_days,
        "simulations": simulations,
    }
