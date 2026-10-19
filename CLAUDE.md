# CLAUDE.md — ASHEN CROWN 開発ルール（AI向け）

オリジナルのダークファンタジー3DアクションRPG。Godot 4.3+ / GDScript / Mobileレンダラー。
**スマホ（Android）優先、PC展開前提。**

## 文書の役割（1つの情報は1つのファイルに）
- `README.md` … 起動方法・操作方法・テスト手順（プレイヤー/開発者が最初に読む）
- `docs/DESIGN.md` … 技術選定・仕様・フォルダ構成・リスク（設計の正）
- `docs/ROADMAP.md` … フェーズ計画と進捗（チェックリスト）
- `JOURNAL.md` … バージョンごとの変更履歴（JOURNAL）
- `CLAUDE.md` … AIが守る開発ルール（本ファイル）

## コード規約
- 素材ファイルに頼らず、メッシュ・UIはコードで生成する（後でアセット差し替え可能に）。
- 攻撃は必ず `AttackData`（予備動作 windup / 判定 active / 硬直 recovery）で定義する。
- 当たり判定は `Actor.run_hit_query()` の形状クエリで行う。見た目だけの判定は禁止。
- 衝突レイヤー: 1=地形, 2=プレイヤー, 3=敵・破壊可能物（ビット値 1/2/4）。
- 数値（HP・ダメージ・スタミナ）は各スクリプト冒頭の定数か `setup()` に集約。
- 既存作品の名称・キャラ・マップ・音楽をコピーしない。
- プラットフォーム判定は `GameSettings` だけで行う。タッチ入力は `TouchControls` に閉じ込め、ゲーム本体は InputMap のアクションだけを読む（移動は `InputSetup.get_move_vector()`）。
- スマホの負荷: 新しいメッシュは分割数を抑え、小物には `visibility_range_end` を付ける。粒子は CPUParticles3D。
- 見た目: キャラクターは `CharacterRig`（archetype で体型を作り分け）、UIの色・枠・フォント・アイコンは `UITheme` を使う。
  Godot 4.3 のモバイル描画は2D図形をまとめられないため、変化の少ないUIは画像にキャッシュする（例: `TouchControls`）。
- 外部素材は CC0 / CC-BY 等のみ。導入時に `docs/CREDITS.md` へ記録。

## 検証（報告前に必ず実行）
```
tools/run_tests.sh        # ヘッドレス自動テスト（全PASSで終了コード0）
tools/screenshot.sh [--touch]   # Xvfb上で起動しスクリーンショット（--touch はスマホ画面）
tools/build_android.sh          # APK書き出し（クラウドでは tools/cloud_android/setup.sh で署名ツールを用意）
```
テストしていない機能を「動作確認済み」と書かない。
