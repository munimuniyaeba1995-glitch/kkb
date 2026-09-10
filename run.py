#!/usr/bin/env python3
"""バックテストを実行するコマンド。

使い方の例:
    python run.py --code 7203 --strategy smacross
    python run.py --code 6758 --strategy rsi --start 2018-01-01 --plot
    python run.py --code 7203 --strategy all          # 全戦略を比較
    python run.py --code 9999 --source sample         # ネット不要の練習用データ
"""

from __future__ import annotations

import argparse
import sys
from datetime import date

from kabu import data, strategies
from kabu.backtest import Config, Costs, run
from kabu.metrics import format_report, summarize


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="日本株のバックテストを行います。",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    p.add_argument("--code", default="7203", help="証券コード（例: トヨタ=7203）")
    p.add_argument("--start", default="2020-01-01", help="開始日 YYYY-MM-DD")
    p.add_argument("--end", default=date.today().isoformat(), help="終了日 YYYY-MM-DD")
    p.add_argument(
        "--source", default="yfinance", choices=["yfinance", "sample"],
        help="データの取得元。sampleはネット不要の練習用ダミーデータ",
    )
    p.add_argument("--no-cache", action="store_true", help="保存済みデータを使わず取り直す")

    p.add_argument(
        "--strategy", default="smacross",
        choices=[*strategies.REGISTRY, "all"],
        help="使う戦略。allなら全部試して比較する",
    )
    p.add_argument("--short", type=int, default=25, help="[smacross] 短期移動平均の日数")
    p.add_argument("--long", type=int, default=75, help="[smacross] 長期移動平均の日数")
    p.add_argument("--rsi-period", type=int, default=14, help="[rsi] RSIの計算日数")
    p.add_argument("--buy-below", type=float, default=30, help="[rsi] この値を下回ったら買う")
    p.add_argument("--sell-above", type=float, default=55, help="[rsi] この値を上回ったら売る")

    p.add_argument("--cash", type=float, default=1_000_000, help="初期資金（円）")
    p.add_argument("--lot", type=int, default=100, help="単元株数")
    p.add_argument(
        "--stop-loss", type=float, default=None,
        help="損切り幅。0.08なら取得価格から8%%下落で売る（未指定なら損切りなし）",
    )
    p.add_argument("--commission", type=float, default=0.0005, help="片道手数料率")
    p.add_argument("--slippage", type=float, default=0.0005, help="片道スリッページ率")

    p.add_argument("--plot", action="store_true", help="グラフをresults/に画像保存する")
    p.add_argument("--trades", action="store_true", help="個別の売買明細も表示する")

    return p.parse_args(argv)


def build_strategy(name: str, args: argparse.Namespace):
    if name == "smacross":
        return strategies.build(name, short=args.short, long=args.long)
    if name == "rsi":
        return strategies.build(
            name,
            period=args.rsi_period,
            buy_below=args.buy_below,
            sell_above=args.sell_above,
        )
    return strategies.build(name)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        prices = data.load_prices(
            args.code, args.start, args.end,
            source=args.source, use_cache=not args.no_cache,
        )
    except Exception as e:
        print(f"データの取得に失敗しました。\n{e}\n", file=sys.stderr)
        if args.source == "yfinance":
            print(
                "確認してください:\n"
                "  - インターネットに繋がっているか\n"
                f"  - 証券コード {args.code} が正しいか（トヨタなら 7203）\n"
                "  - 期間に営業日が含まれているか\n\n"
                "ネットが使えない環境なら、練習用データで動かせます:\n"
                f"  python run.py --code {args.code} --source sample",
                file=sys.stderr,
            )
        return 1

    print(f"データ取得: {args.code}  {len(prices)}営業日  "
          f"({prices.index[0]:%Y-%m-%d} 〜 {prices.index[-1]:%Y-%m-%d})")

    config = Config(
        initial_cash=args.cash,
        lot_size=args.lot,
        stop_loss=args.stop_loss,
        costs=Costs(commission_rate=args.commission, slippage_rate=args.slippage),
    )

    names = list(strategies.REGISTRY) if args.strategy == "all" else [args.strategy]
    results = []

    for name in names:
        try:
            strategy = build_strategy(name, args)
            result = run(prices, strategy, config, code=args.code)
        except Exception as e:
            print(f"戦略 '{name}' の実行に失敗しました: {e}", file=sys.stderr)
            return 1

        results.append(result)
        print(format_report(result))

        if args.trades and not result.trades.empty:
            print("  売買明細:")
            print(result.trades.to_string(index=False))
            print()

        if args.plot:
            from kabu.plot import save_chart

            path = save_chart(result, f"results/{args.code}_{name}.png")
            print(f"  グラフを保存しました: {path}\n")

    if len(results) > 1:
        print_comparison(results)

    return 0


def print_comparison(results: list) -> None:
    """複数戦略の要点だけを並べて比べる。"""
    print("=" * 74)
    print(" 戦略の比較（最大ドローダウンが小さく、リターンが高いものが良い）")
    print("=" * 74)
    print(f"{'戦略':<12}{'総リターン':>12}{'年率':>10}{'最大DD':>10}{'取引':>7}{'勝率':>9}")
    print("-" * 74)

    for r in results:
        s = summarize(r)
        win = f"{s['勝率']:.1f}%" if s["取引回数"] else "-"
        print(
            f"{s['戦略']:<12}"
            f"{s['総リターン']:>11.2f}%"
            f"{s['年率リターン']:>9.2f}%"
            f"{s['最大ドローダウン']:>9.2f}%"
            f"{s['取引回数']:>7,}"
            f"{win:>9}"
        )
    print("=" * 74)
    print(" ※ここで一番成績が良かった戦略を、そのまま実弾で使ってはいけません。")
    print("   同じデータで何度も試すと、そのデータにだけ都合の良い設定が見つかります。")
    print("   詳しくはREADMEの「過剰最適化」を読んでください。")


if __name__ == "__main__":
    raise SystemExit(main())
