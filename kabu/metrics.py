"""成績の評価指標。

見るべき順番は「①最大ドローダウン → ②買い持ちとの差 → ③リターン」。
リターンだけを見ると、たまたま上手くいっただけの戦略に騙される。
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from .backtest import Result, buy_and_hold_equity

TRADING_DAYS_PER_YEAR = 252


def total_return(equity: pd.Series) -> float:
    """期間全体の損益率（%）。"""
    return (equity.iloc[-1] / equity.iloc[0] - 1) * 100


def cagr(equity: pd.Series) -> float:
    """年平均成長率（%）。1年あたりならどれくらい増えたか。"""
    years = (equity.index[-1] - equity.index[0]).days / 365.25
    if years <= 0 or equity.iloc[0] <= 0:
        return float("nan")
    return ((equity.iloc[-1] / equity.iloc[0]) ** (1 / years) - 1) * 100


def max_drawdown(equity: pd.Series) -> float:
    """最大ドローダウン（%）。過去最高値からの最大の落ち込み幅。

    この数字が「実際に耐えなければいけない含み損」。
    -50%なら、資産が半分になる時期を耐え抜く必要があるということ。
    たいていの人はそこで投げ売りするので、この値が大きい戦略は
    机上では勝っていても実運用では続かない。
    """
    return ((equity / equity.cummax()) - 1).min() * 100


def sharpe_ratio(equity: pd.Series) -> float:
    """シャープレシオ。リターンを値動きの荒さで割った、効率の指標。

    1を超えれば優秀とされるが、日次データでは過大に出やすいので参考程度に。
    """
    returns = equity.pct_change().dropna()
    if len(returns) < 2 or returns.std() == 0:
        return float("nan")
    return returns.mean() / returns.std() * np.sqrt(TRADING_DAYS_PER_YEAR)


def summarize(result: Result) -> dict:
    """結果をひとまとめの辞書にする。"""
    equity = result.equity
    trades = result.trades
    bh = buy_and_hold_equity(result.prices, result.config)

    wins = trades[trades["損益"] > 0]["損益"] if not trades.empty else pd.Series(dtype=float)
    losses = trades[trades["損益"] <= 0]["損益"] if not trades.empty else pd.Series(dtype=float)

    gross_profit = wins.sum()
    gross_loss = abs(losses.sum())

    profit = equity.iloc[-1] - equity.iloc[0]
    tax = profit * result.config.costs.tax_rate if profit > 0 else 0.0

    return {
        "銘柄": result.code,
        "戦略": result.strategy_name,
        "期間": f"{equity.index[0]:%Y-%m-%d} 〜 {equity.index[-1]:%Y-%m-%d}",
        "初期資金": equity.iloc[0],
        "最終資産": equity.iloc[-1],
        "損益": profit,
        "税引後損益": profit - tax,
        "総リターン": total_return(equity),
        "年率リターン": cagr(equity),
        "最大ドローダウン": max_drawdown(equity),
        "シャープレシオ": sharpe_ratio(equity),
        "取引回数": len(trades),
        "勝率": (len(wins) / len(trades) * 100) if len(trades) else float("nan"),
        "平均利益": wins.mean() if len(wins) else 0.0,
        "平均損失": losses.mean() if len(losses) else 0.0,
        "プロフィットファクター": (gross_profit / gross_loss) if gross_loss > 0 else float("inf"),
        "買い持ちリターン": total_return(bh),
        "買い持ち最大DD": max_drawdown(bh),
    }


def format_report(result: Result) -> str:
    """結果を人間が読める文字列にする。"""
    s = summarize(result)
    line = "─" * 46

    def yen(v: float) -> str:
        return f"{v:>15,.0f} 円"

    def pct(v: float) -> str:
        return f"{v:>14.2f} %"

    diff = s["総リターン"] - s["買い持ちリターン"]
    verdict = (
        "買い持ちに勝っている" if diff > 0 else "買い持ちに負けている（戦略の意味がない）"
    )

    return f"""
{line}
 バックテスト結果   {s['銘柄']}   戦略: {s['戦略']}
 期間: {s['期間']}
{line}
 【資産】
   初期資金        {yen(s['初期資金'])}
   最終資産        {yen(s['最終資産'])}
   損益            {yen(s['損益'])}
   税引後損益      {yen(s['税引後損益'])}   ※譲渡益税20.315%を引いた概算

 【リターン】
   総リターン      {pct(s['総リターン'])}
   年率リターン    {pct(s['年率リターン'])}

 【リスク】← ここを最初に見る
   最大ドローダウン{pct(s['最大ドローダウン'])}   ※これだけ含み損に耐える必要がある
   シャープレシオ  {s['シャープレシオ']:>14.2f}

 【売買の中身】
   取引回数        {s['取引回数']:>14,} 回
   勝率            {pct(s['勝率'])}
   平均利益        {yen(s['平均利益'])}
   平均損失        {yen(s['平均損失'])}
   PF(総利益÷総損失){s['プロフィットファクター']:>13.2f}   ※1.0未満なら赤字

 【買い持ちとの比較】← ここが本当の評価
   戦略のリターン  {pct(s['総リターン'])}
   買い持ち        {pct(s['買い持ちリターン'])}
   差              {pct(diff)}  → {verdict}
{line}
"""
