"""
DLP TEST SAMPLE - harmless dummy code used to test Purview Endpoint DLP detection.
Contains no real data, credentials or proprietary logic.
"""
import argparse
import csv
import logging
import math
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

RISK_FREE_RATE = 0.02
TRADING_DAYS = 252


@dataclass
class Position:
    symbol: str
    quantity: int
    entry_price: float
    opened_at: datetime = field(default_factory=datetime.utcnow)

    def market_value(self, price: float) -> float:
        return self.quantity * price

    def pnl(self, price: float) -> float:
        return (price - self.entry_price) * self.quantity


class Portfolio:
    def __init__(self, cash: float = 1_000_000.0):
        self.cash = cash
        self.positions: Dict[str, Position] = {}
        self.history: List[Dict] = []

    def buy(self, symbol: str, quantity: int, price: float) -> None:
        cost = quantity * price
        if cost > self.cash:
            raise ValueError(f"Insufficient cash to buy {quantity} {symbol}")
        self.cash -= cost
        if symbol in self.positions:
            pos = self.positions[symbol]
            total_qty = pos.quantity + quantity
            pos.entry_price = (pos.entry_price * pos.quantity + cost) / total_qty
            pos.quantity = total_qty
        else:
            self.positions[symbol] = Position(symbol, quantity, price)
        self.history.append({"side": "BUY", "symbol": symbol, "qty": quantity, "px": price})

    def sell(self, symbol: str, quantity: int, price: float) -> None:
        pos = self.positions.get(symbol)
        if pos is None or pos.quantity < quantity:
            raise ValueError(f"Cannot sell {quantity} {symbol}")
        self.cash += quantity * price
        pos.quantity -= quantity
        if pos.quantity == 0:
            del self.positions[symbol]
        self.history.append({"side": "SELL", "symbol": symbol, "qty": quantity, "px": price})


def moving_average(prices: pd.Series, window: int = 20) -> pd.Series:
    return prices.rolling(window=window).mean()


def sharpe_ratio(returns: pd.Series) -> float:
    excess = returns - RISK_FREE_RATE / TRADING_DAYS
    if excess.std() == 0:
        return 0.0
    return float(math.sqrt(TRADING_DAYS) * excess.mean() / excess.std())


def momentum_signal(prices: pd.Series, fast: int = 10, slow: int = 50) -> pd.Series:
    fast_ma = moving_average(prices, fast)
    slow_ma = moving_average(prices, slow)
    signal = np.where(fast_ma > slow_ma, 1, -1)
    return pd.Series(signal, index=prices.index)


def load_prices(path: str) -> pd.DataFrame:
    if not os.path.exists(path):
        logger.error("Price file not found: %s", path)
        sys.exit(1)
    frame = pd.read_csv(path, parse_dates=["date"], index_col="date")
    return frame.sort_index()


def backtest(prices: pd.Series) -> Optional[float]:
    try:
        signal = momentum_signal(prices)
        daily_returns = prices.pct_change().fillna(0) * signal.shift(1).fillna(0)
        return sharpe_ratio(daily_returns)
    except Exception as exc:
        logger.exception("Backtest failed: %s", exc)
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Dummy momentum backtest")
    parser.add_argument("--prices", default="prices.csv")
    parser.add_argument("--symbol", default="TEST")
    args = parser.parse_args()

    frame = load_prices(args.prices)
    result = backtest(frame[args.symbol])
    print(f"Sharpe ratio for {args.symbol}: {result}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
