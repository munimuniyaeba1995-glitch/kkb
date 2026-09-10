"""株価データを取得する。

取得元は2つ:
  - yfinance : Yahoo Financeから本物の日本株データを取る（要インターネット）
  - sample   : 乱数で作った練習用データ（ネット不要・毎回同じ結果）

一度取ったデータは data/cache/ にCSVで保存し、次回からはそれを読む。
Yahooに何度もアクセスすると弾かれることがあるため。
"""

from __future__ import annotations

import zlib
from pathlib import Path

import numpy as np
import pandas as pd

# バックテストが必要とする列。どの取得元でもこの形に揃える。
COLUMNS = ["Open", "High", "Low", "Close", "Volume"]

CACHE_DIR = Path(__file__).resolve().parent.parent / "data" / "cache"


def to_yahoo_ticker(code: str) -> str:
    """証券コードをYahoo Finance の形式にする。'7203' -> '7203.T'"""
    code = str(code).strip().upper()
    # 4桁の数字だけなら日本株とみなして .T を付ける
    if code.isdigit():
        return f"{code}.T"
    return code


def load_prices(
    code: str,
    start: str,
    end: str,
    source: str = "yfinance",
    use_cache: bool = True,
) -> pd.DataFrame:
    """指定銘柄の日足データを取得する。

    戻り値は Open/High/Low/Close/Volume の列を持ち、日付が昇順に並んだDataFrame。
    """
    if source == "sample":
        return _generate_sample(code, start, end)
    if source != "yfinance":
        raise ValueError(f"未知の取得元です: {source}（'yfinance' か 'sample'）")

    cache_path = CACHE_DIR / f"{code}_{start}_{end}.csv"
    if use_cache and cache_path.exists():
        df = pd.read_csv(cache_path, index_col=0, parse_dates=True)
        return _finalize(df, code)

    df = _fetch_yfinance(code, start, end)

    if use_cache:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(cache_path)

    return df


def _fetch_yfinance(code: str, start: str, end: str) -> pd.DataFrame:
    import yfinance as yf

    ticker = to_yahoo_ticker(code)
    # auto_adjust=True で株式分割・配当を調整した株価になる。
    # これをしないと分割日に株価が半分になって「暴落した」と誤判定してしまう。
    df = yf.Ticker(ticker).history(start=start, end=end, auto_adjust=True)

    if df.empty:
        raise ValueError(
            f"{ticker} のデータが取得できませんでした。\n"
            "  - 証券コードが正しいか（例: トヨタは 7203）\n"
            "  - 期間が営業日を含んでいるか\n"
            "  - インターネットに繋がっているか\n"
            "を確認してください。"
        )

    return _finalize(df, code)


def _finalize(df: pd.DataFrame, code: str) -> pd.DataFrame:
    """取得元による細かな差を吸収して、共通の形に揃える。"""
    df = df.copy()

    # yfinanceの日付はタイムゾーン付きで返ることがある。日足では邪魔なので外す。
    if isinstance(df.index, pd.DatetimeIndex) and df.index.tz is not None:
        df.index = df.index.tz_localize(None)
    df.index = pd.DatetimeIndex(df.index).normalize()
    df.index.name = "Date"

    missing = [c for c in COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"{code}: 必要な列がありません: {missing}")

    df = df[COLUMNS].sort_index()
    # 売買代金がゼロの日＝実質的に取引が成立していない日。約定できないので除く。
    df = df[(df["Volume"] > 0) & df["Close"].notna()]

    if df.empty:
        raise ValueError(f"{code}: 有効な取引日が1日もありませんでした。")

    return df


def _generate_sample(code: str, start: str, end: str) -> pd.DataFrame:
    """練習用のダミー株価を作る。

    実在の値動きではないので、ここで良い成績が出ても何の意味もない。
    エンジンが正しく動くかを確かめるためだけのもの。
    """
    dates = pd.bdate_range(start=start, end=end)
    if len(dates) == 0:
        raise ValueError(f"期間 {start} 〜 {end} に営業日がありません。")

    # 銘柄コードから乱数の種を決める。同じコードなら毎回まったく同じデータになる。
    # 組み込みのhash()は実行のたびに結果が変わるため、値が固定のcrc32を使う。
    rng = np.random.default_rng(zlib.crc32(str(code).encode()))

    n = len(dates)
    daily_return = rng.normal(loc=0.0003, scale=0.018, size=n)  # 年率+7%／ボラ29%くらい
    close = 2000 * np.exp(np.cumsum(daily_return))

    # 終値の周りに始値・高値・安値を散らして、それらしいOHLCにする
    open_ = close * (1 + rng.normal(0, 0.006, size=n))
    noise_high = np.abs(rng.normal(0, 0.007, size=n))
    noise_low = np.abs(rng.normal(0, 0.007, size=n))
    high = np.maximum(open_, close) * (1 + noise_high)
    low = np.minimum(open_, close) * (1 - noise_low)

    df = pd.DataFrame(
        {
            "Open": open_.round(1),
            "High": high.round(1),
            "Low": low.round(1),
            "Close": close.round(1),
            "Volume": rng.integers(500_000, 5_000_000, size=n),
        },
        index=dates,
    )
    df.index.name = "Date"
    return df
