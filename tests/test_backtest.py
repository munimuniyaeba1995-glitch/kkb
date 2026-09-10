"""エンジンが正しく動くかを検証するテスト。

バックテストは「間違っていても、それらしい数字が出てしまう」のが怖いところ。
特にルックアヘッドバイアス（未来の値を使ってしまう）は、成績を大幅に
水増しするのに、結果を眺めているだけでは絶対に気づけない。
だから機械で検証する。

実行方法:
    python tests/test_backtest.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from kabu import data, indicators  # noqa: E402
from kabu.backtest import Config, Costs, buy_and_hold_equity, run  # noqa: E402
from kabu.strategies import BuyAndHold, Strategy  # noqa: E402

FREE = Costs(commission_rate=0.0, min_commission=0.0, slippage_rate=0.0)


def make_prices(closes: list[float], opens: list[float] | None = None) -> pd.DataFrame:
    """テスト用の株価データを手で作る。"""
    opens = opens if opens is not None else closes
    idx = pd.bdate_range("2024-01-01", periods=len(closes))
    return pd.DataFrame(
        {
            "Open": opens,
            "High": [max(o, c) * 1.01 for o, c in zip(opens, closes)],
            "Low": [min(o, c) * 0.99 for o, c in zip(opens, closes)],
            "Close": closes,
            "Volume": [1_000_000] * len(closes),
        },
        index=idx,
    )


class SignalOnDay(Strategy):
    """指定した日だけ「持ちたい」と言う、テスト専用の戦略。"""

    name = "test"

    def __init__(self, hold_days: set[int]):
        self.hold_days = hold_days

    def generate_signals(self, df):
        return pd.Series(
            [1.0 if i in self.hold_days else 0.0 for i in range(len(df))],
            index=df.index,
        )


def test_no_lookahead_bias():
    """最重要テスト: 判断した日の終値ではなく、翌日の始値で約定すること。"""
    # 3日目(index=2)の始値だけを極端に高くしておく。
    # index=1 の終値でシグナルが出たら、約定はindex=2の始値=9999になるはず。
    prices = make_prices(
        closes=[1000, 1000, 1000, 1000],
        opens=[1000, 1000, 9999, 1000],
    )
    config = Config(initial_cash=10_000_000, costs=FREE)
    result = run(prices, SignalOnDay({1}), config)

    assert len(result.trades) == 1, "取引が1回発生するはず"
    entry = result.trades.iloc[0]["取得単価"]
    assert math.isclose(entry, 9999, rel_tol=1e-6), (
        f"翌日始値9999で約定すべきなのに {entry} で約定している。"
        "未来を見てしまっている可能性がある。"
    )
    assert result.trades.iloc[0]["買付日"] == prices.index[2]


def test_shares_are_multiples_of_lot():
    """単元株（100株）の倍数でしか買わないこと。"""
    prices = make_prices([1234.5] * 10)
    config = Config(initial_cash=1_000_000, lot_size=100, costs=FREE)
    result = run(prices, BuyAndHold(), config)

    qty = result.trades.iloc[0]["株数"]
    assert qty % 100 == 0, f"100株単位で買うべきなのに {qty} 株買っている"
    assert qty == 800, f"1,000,000円で1234.5円の株は800株買えるはずだが {qty} 株"


def test_cash_never_negative():
    """資金以上に買わないこと（借金しない）。"""
    prices = make_prices([100 + i for i in range(50)])
    config = Config(initial_cash=50_000, lot_size=100, costs=Costs())
    result = run(prices, BuyAndHold(), config)

    assert (result.equity >= 0).all(), "資産評価額がマイナスになっている"


def test_costs_reduce_returns():
    """手数料とスリッページを入れると、成績は必ず悪くなること。"""
    prices = make_prices([1000 + i * 5 for i in range(60)])
    config_free = Config(initial_cash=1_000_000, costs=FREE)
    config_paid = Config(
        initial_cash=1_000_000,
        costs=Costs(commission_rate=0.005, slippage_rate=0.005),
    )

    free = run(prices, BuyAndHold(), config_free).equity.iloc[-1]
    paid = run(prices, BuyAndHold(), config_paid).equity.iloc[-1]

    assert paid < free, "コストを入れたのに成績が悪化していない"


def test_stop_loss_triggers():
    """損切りラインを割ったら売ること。"""
    # 1000円で買ったあと、じりじり下げて800円まで落ちる
    closes = [1000, 1000, 980, 950, 900, 850, 800, 780, 770, 760]
    prices = make_prices(closes)
    config = Config(initial_cash=1_000_000, stop_loss=0.10, costs=FREE)
    result = run(prices, BuyAndHold(), config)

    reasons = list(result.trades["理由"])
    assert "損切り" in reasons, f"損切りが発動していない（理由: {reasons}）"

    trade = result.trades[result.trades["理由"] == "損切り"].iloc[0]
    # 取得単価の10%下＝900円あたりで手仕舞いできているはず（多少の余裕を見る）
    assert 850 <= trade["売却単価"] <= 910, f"損切り価格が想定外: {trade['売却単価']}"


def test_buyhold_matches_reference():
    """買い持ち戦略の結果が、比較用の計算と一致すること。"""
    prices = make_prices([1000 + (i % 7) * 30 for i in range(40)])
    config = Config(initial_cash=1_000_000, costs=FREE)

    result = run(prices, BuyAndHold(), config)
    reference = buy_and_hold_equity(prices, config)

    assert math.isclose(result.equity.iloc[-1], reference.iloc[-1], rel_tol=1e-9), (
        f"エンジン {result.equity.iloc[-1]} と参照計算 {reference.iloc[-1]} が食い違う"
    )


def test_rsi_range_and_extremes():
    """RSIが0〜100に収まり、上げ続けた時に100になること。"""
    rising = pd.Series([100 + i for i in range(40)], dtype=float)
    r = indicators.rsi(rising, 14).dropna()

    assert ((r >= 0) & (r <= 100)).all(), "RSIが0〜100の範囲外に出ている"
    assert math.isclose(r.iloc[-1], 100.0, rel_tol=1e-9), "上昇一辺倒ならRSIは100"


def test_sample_data_is_reproducible():
    """サンプルデータが毎回同じであること（再現性がないと検証にならない）。"""
    a = data.load_prices("7203", "2023-01-01", "2023-06-30", source="sample")
    b = data.load_prices("7203", "2023-01-01", "2023-06-30", source="sample")

    assert a.equals(b), "同じ条件なのにサンプルデータが違う"
    assert len(a) > 100, f"営業日が少なすぎる: {len(a)}日"


def test_signals_align_with_trades():
    """シグナルが0の期間に株を持ち続けていないこと。"""
    prices = make_prices([1000 + (i % 5) * 10 for i in range(30)])
    config = Config(initial_cash=1_000_000, costs=FREE)
    result = run(prices, SignalOnDay({5, 6, 7, 8}), config)

    assert len(result.trades) == 1, f"取引は1回のはずが {len(result.trades)} 回"
    trade = result.trades.iloc[0]

    # 判断は必ず1日遅れて実行される:
    #   index5の終値で「買いたい」→ index6の始値で買う
    #   index8の終値まで「持ちたい」→ index9も保有が続く
    #   index9の終値で「もう要らない」→ index10の始値で売る
    assert trade["買付日"] == prices.index[6], f"買付日が想定外: {trade['買付日']}"
    assert trade["売却日"] == prices.index[10], f"売却日が想定外: {trade['売却日']}"


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0

    for t in tests:
        try:
            t()
            print(f"  OK   {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"  NG   {t.__name__}\n       {e}")
        except Exception as e:
            failed += 1
            print(f"  ERR  {t.__name__}\n       {type(e).__name__}: {e}")

    print()
    if failed:
        print(f"{len(tests)}件中 {failed}件 失敗しました。")
        return 1
    print(f"{len(tests)}件すべて成功しました。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
