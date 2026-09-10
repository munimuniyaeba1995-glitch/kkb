"""結果をグラフ画像にする。

グラフ内の文字を英語にしているのは、日本語フォントが入っていない環境だと
文字が全部「□□□」になってしまうため。数字とグラフの形が読めれば十分。
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # 画面のない環境でも画像を保存できるようにする
import matplotlib.pyplot as plt  # noqa: E402

from .backtest import Result, buy_and_hold_equity  # noqa: E402


def save_chart(result: Result, path: str | Path) -> Path:
    """株価＋売買地点と、資産推移の2段グラフを保存する。"""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    fig, (ax_price, ax_equity) = plt.subplots(
        2, 1, figsize=(13, 9), sharex=True, gridspec_kw={"height_ratios": [1, 1]}
    )

    # 上段: 株価と売買した地点
    ax_price.plot(result.prices.index, result.prices["Close"], lw=1.1,
                  color="#333333", label="Close")

    trades = result.trades
    if not trades.empty:
        buys = trades["買付日"]
        sells = trades["売却日"]
        ax_price.scatter(buys, result.prices["Close"].reindex(buys), marker="^",
                         s=70, color="#2e7d32", zorder=3, label="Buy")
        ax_price.scatter(sells, result.prices["Close"].reindex(sells), marker="v",
                         s=70, color="#c62828", zorder=3, label="Sell")

    ax_price.set_title(f"{result.code}  /  strategy: {result.strategy_name}")
    ax_price.set_ylabel("Price (JPY)")
    ax_price.legend(loc="upper left")
    ax_price.grid(alpha=0.3)

    # 下段: 戦略と買い持ちの資産推移を重ねる（これが一番大事な比較）
    bh = buy_and_hold_equity(result.prices, result.config)
    ax_equity.plot(result.equity.index, result.equity, lw=1.6,
                   color="#1565c0", label="Strategy")
    ax_equity.plot(bh.index, bh, lw=1.3, color="#9e9e9e",
                   ls="--", label="Buy & Hold")
    ax_equity.axhline(result.config.initial_cash, color="#bbbbbb", lw=0.9)

    ax_equity.set_ylabel("Equity (JPY)")
    ax_equity.set_xlabel("Date")
    ax_equity.legend(loc="upper left")
    ax_equity.grid(alpha=0.3)

    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)

    return path
