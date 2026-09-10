"""売買戦略。

戦略の仕事は「その日の終値時点で、株を持ちたいか（1）持ちたくないか（0）」を返すことだけ。
実際にいくらで何株買うかはエンジン（backtest.py）が決める。

重要: ここで返す signal[t] は「t日の終値を見た時点の判断」。
エンジンはそれを翌営業日の始値で約定させる。当日の終値では買えない
（終値を見た瞬間にその終値で買うことは現実には不可能なため）。
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from .indicators import rsi, sma


class Strategy:
    """全戦略の基底クラス。"""

    name = "base"

    def generate_signals(self, df: pd.DataFrame) -> pd.Series:
        """0（持たない）か1（持つ）を各日について返す。"""
        raise NotImplementedError


class BuyAndHold(Strategy):
    """最初に買って最後まで持ち続けるだけ。

    比較の基準として最重要。手の込んだ戦略がこれに勝てないなら、
    その戦略には存在価値がない（売買コストの分だけ損をしている）。
    """

    name = "buyhold"

    def generate_signals(self, df: pd.DataFrame) -> pd.Series:
        return pd.Series(1.0, index=df.index)


class SMACross(Strategy):
    """ゴールデンクロス／デッドクロス戦略。

    短期移動平均が長期移動平均を上回っている間だけ株を持つ。
    上昇トレンドに乗る（順張り）発想。
    """

    name = "smacross"

    def __init__(self, short: int = 25, long: int = 75):
        if short >= long:
            raise ValueError(f"短期({short})は長期({long})より小さくしてください。")
        self.short = short
        self.long = long

    def generate_signals(self, df: pd.DataFrame) -> pd.Series:
        short_ma = sma(df["Close"], self.short)
        long_ma = sma(df["Close"], self.long)
        signal = (short_ma > long_ma).astype(float)
        # 移動平均が計算できない最初の期間は判断不能なので持たない
        signal[long_ma.isna()] = 0.0
        return signal


class RSIReversal(Strategy):
    """RSIの逆張り戦略。

    売られすぎ（RSIが低い）で買い、平常値まで戻ったら売る。
    下落トレンドで使うと落ちるナイフを掴み続けるので注意。
    """

    name = "rsi"

    def __init__(self, period: int = 14, buy_below: float = 30, sell_above: float = 55):
        if buy_below >= sell_above:
            raise ValueError(
                f"買い水準({buy_below})は売り水準({sell_above})より低くしてください。"
            )
        self.period = period
        self.buy_below = buy_below
        self.sell_above = sell_above

    def generate_signals(self, df: pd.DataFrame) -> pd.Series:
        r = rsi(df["Close"], self.period)

        # 買い条件を満たした日に1、売り条件を満たした日に0を置き、
        # あいだの日は直前の状態を引き継ぐ（＝持ち続ける）
        signal = pd.Series(np.nan, index=df.index)
        signal[r < self.buy_below] = 1.0
        signal[r > self.sell_above] = 0.0
        return signal.ffill().fillna(0.0)


# CLIから名前で戦略を作れるようにする表
REGISTRY = {
    BuyAndHold.name: BuyAndHold,
    SMACross.name: SMACross,
    RSIReversal.name: RSIReversal,
}


def build(name: str, **kwargs) -> Strategy:
    """名前から戦略を作る。例: build('smacross', short=5, long=20)"""
    if name not in REGISTRY:
        raise ValueError(
            f"戦略 '{name}' は存在しません。使えるのは: {', '.join(REGISTRY)}"
        )
    return REGISTRY[name](**kwargs)
