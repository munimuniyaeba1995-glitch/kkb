"""バックテストエンジン。

このファイルの目的は「戦略の成績を、現実に近い条件で見積もる」こと。
現実に近づけるために、次の4つを必ず守っている。

1. 未来を見ない（ルックアヘッドバイアスの排除）
   t日の終値を見て判断したら、約定は t+1日の始値。
   「終値を見てその終値で買う」バックテストは、実際には絶対にできない取引で
   成績を水増ししてしまう。初心者が一番やりがちで、一番致命的な間違い。

2. 単元株で買う
   日本株はふつう100株単位。1株だけ買うことはできない。

3. 手数料とスリッページを引く
   往復のコストを無視すると、勝てない戦略が勝っているように見える。

4. 損切りを入れられる
   1回の負けで再起不能にならないようにするための仕組み。
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from .strategies import Strategy


@dataclass
class Costs:
    """売買にかかるコスト。"""

    # 片道の手数料率。ネット証券の現物取引を想定した控えめな値。
    commission_rate: float = 0.0005
    # 1回あたりの最低手数料（円）。証券会社によっては定額。
    min_commission: float = 0.0
    # スリッページ率。指値どおりに約定せず不利な価格になる分の見積もり。
    # 買いは高く、売りは安く約定するものとして計算する。
    slippage_rate: float = 0.0005
    # 譲渡益にかかる税率（所得税・住民税・復興特別所得税の合計）
    tax_rate: float = 0.20315


@dataclass
class Config:
    """バックテストの設定。"""

    initial_cash: float = 1_000_000.0
    lot_size: int = 100          # 単元株数
    stop_loss: float | None = None   # 例: 0.08 なら取得価格から8%下落で損切り
    costs: Costs = field(default_factory=Costs)


@dataclass
class Result:
    """バックテストの結果一式。"""

    equity: pd.Series          # 日々の資産評価額
    trades: pd.DataFrame       # 個々の売買記録
    prices: pd.DataFrame       # 使った株価データ
    signals: pd.Series         # 戦略が出したシグナル
    config: Config
    strategy_name: str
    code: str


def _commission(trade_value: float, costs: Costs) -> float:
    """約定代金から手数料を計算する。"""
    return max(trade_value * costs.commission_rate, costs.min_commission)


def _affordable_shares(cash: float, price: float, lot_size: int, costs: Costs) -> int:
    """手数料込みで買える最大の株数（単元株の倍数）を返す。"""
    if price <= 0 or cash <= 0:
        return 0

    lots = int(cash // (price * lot_size))
    # 手数料の分だけ足りないことがあるので、買えるまで1単元ずつ減らす
    while lots > 0:
        value = lots * lot_size * price
        if value + _commission(value, costs) <= cash:
            return lots * lot_size
        lots -= 1
    return 0


def run(
    prices: pd.DataFrame,
    strategy: Strategy,
    config: Config | None = None,
    code: str = "",
) -> Result:
    """バックテストを実行する。"""
    config = config or Config()
    costs = config.costs

    if len(prices) < 2:
        raise ValueError("バックテストには最低2営業日分のデータが必要です。")

    signals = strategy.generate_signals(prices).reindex(prices.index).fillna(0.0)

    open_ = prices["Open"].to_numpy(dtype=float)
    low = prices["Low"].to_numpy(dtype=float)
    close = prices["Close"].to_numpy(dtype=float)
    sig = signals.to_numpy(dtype=float)
    dates = prices.index

    cash = config.initial_cash
    shares = 0
    entry_price = 0.0      # スリッページ・手数料込みの実質取得単価
    entry_date = None
    stop_price = None

    equity = np.empty(len(prices), dtype=float)
    trades: list[dict] = []

    def buy(i: int, price: float) -> None:
        nonlocal cash, shares, entry_price, entry_date, stop_price
        fill = price * (1 + costs.slippage_rate)   # 買いは不利に＝高く約定
        qty = _affordable_shares(cash, fill, config.lot_size, costs)
        if qty == 0:
            return
        value = qty * fill
        fee = _commission(value, costs)
        cash -= value + fee
        shares = qty
        entry_price = (value + fee) / qty   # 手数料も取得原価に含める
        entry_date = dates[i]
        stop_price = fill * (1 - config.stop_loss) if config.stop_loss else None

    def sell(i: int, price: float, reason: str) -> None:
        nonlocal cash, shares, entry_price, entry_date, stop_price
        fill = price * (1 - costs.slippage_rate)   # 売りは不利に＝安く約定
        value = shares * fill
        fee = _commission(value, costs)
        proceeds = value - fee
        cash += proceeds
        exit_price = proceeds / shares
        trades.append(
            {
                "買付日": entry_date,
                "売却日": dates[i],
                "株数": shares,
                "取得単価": round(entry_price, 2),
                "売却単価": round(exit_price, 2),
                "損益": round(proceeds - entry_price * shares, 0),
                "騰落率": round((exit_price / entry_price - 1) * 100, 2),
                "理由": reason,
            }
        )
        shares = 0
        entry_price = 0.0
        entry_date = None
        stop_price = None

    # 初日は「前日のシグナル」が存在しないので何もしない。評価額だけ記録する。
    equity[0] = cash

    for i in range(1, len(prices)):
        # --- 寄り付き: 前日終値のシグナルに従って売買する ---
        want = sig[i - 1] > 0.5
        if want and shares == 0:
            buy(i, open_[i])
        elif not want and shares > 0:
            sell(i, open_[i], "シグナル")

        # --- ザラ場: 損切りラインに触れたか確認する ---
        if shares > 0 and stop_price is not None and low[i] <= stop_price:
            # 寄り付きから既に損切り価格を下回っていたら、その安い始値でしか売れない
            fill = min(open_[i], stop_price)
            sell(i, fill, "損切り")

        # --- 大引け: その日の資産評価額を記録する ---
        equity[i] = cash + shares * close[i]

    # 最終日にまだ持っていたら、最後の終値で決済したものとして扱う
    if shares > 0:
        last = len(prices) - 1
        sell(last, close[last], "期間終了")
        equity[last] = cash

    trades_df = pd.DataFrame(trades)
    if trades_df.empty:
        trades_df = pd.DataFrame(
            columns=["買付日", "売却日", "株数", "取得単価", "売却単価", "損益", "騰落率", "理由"]
        )

    return Result(
        equity=pd.Series(equity, index=dates, name="資産評価額"),
        trades=trades_df,
        prices=prices,
        signals=signals,
        config=config,
        strategy_name=strategy.name,
        code=code,
    )


def buy_and_hold_equity(prices: pd.DataFrame, config: Config) -> pd.Series:
    """比較用に「初日に買って持ち続けた場合」の資産推移を計算する。"""
    costs = config.costs
    fill = prices["Open"].iloc[1] * (1 + costs.slippage_rate)
    qty = _affordable_shares(config.initial_cash, fill, config.lot_size, costs)

    if qty == 0:
        # 1単元すら買えない場合は現金のまま
        return pd.Series(config.initial_cash, index=prices.index, name="買い持ち")

    value = qty * fill
    cash = config.initial_cash - value - _commission(value, costs)

    equity = cash + qty * prices["Close"]
    equity.iloc[0] = config.initial_cash

    # 最終日に売る前提なので、売却コストを差し引く
    final_value = qty * prices["Close"].iloc[-1] * (1 - costs.slippage_rate)
    equity.iloc[-1] = cash + final_value - _commission(final_value, costs)

    return equity.rename("買い持ち")
