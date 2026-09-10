"""テクニカル指標。

どれも「過去の値だけ」から計算する。未来の値を混ぜると
バックテストの成績が嘘になるので、そこだけは絶対に守る。
"""

from __future__ import annotations

import pandas as pd


def sma(series: pd.Series, period: int) -> pd.Series:
    """単純移動平均。直近period日の平均値。"""
    if period < 1:
        raise ValueError(f"periodは1以上にしてください: {period}")
    return series.rolling(window=period, min_periods=period).mean()


def rsi(series: pd.Series, period: int = 14) -> pd.Series:
    """RSI（相対力指数）。0〜100の値で、買われすぎ・売られすぎの目安。

    一般に70超で買われすぎ、30未満で売られすぎとされる。
    """
    if period < 1:
        raise ValueError(f"periodは1以上にしてください: {period}")

    diff = series.diff()
    gain = diff.clip(lower=0)          # 値上がり幅（下がった日は0）
    loss = -diff.clip(upper=0)         # 値下がり幅（上がった日は0）

    # Wilder方式の平滑化。一般的なチャートツールと同じ計算になる。
    avg_gain = gain.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()

    rs = avg_gain / avg_loss
    result = 100 - (100 / (1 + rs))
    # 値下がりが1日も無いとavg_lossが0になり計算できない。その場合は上昇一辺倒なので100。
    result[avg_loss == 0] = 100.0
    return result
