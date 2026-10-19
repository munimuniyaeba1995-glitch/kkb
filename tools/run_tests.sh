#!/usr/bin/env bash
# ヘッドレス自動テスト。GODOT 環境変数で Godot 実行ファイルを指定できる。
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --editor --quit >/dev/null 2>&1   # class_name 登録のためのインポート
"$GODOT" --headless --path . res://tests/test_runner.tscn > tests_output.log 2>&1
status=$?
grep -v -E 'Parameter "m" is null|mesh_get_surface_count' tests_output.log
# ヘッドレスのダミー描画で出る既知の無害なメッセージ（実描画では出ない）は除外
if grep -v -E 'Parameter "m" is null|mesh_get_surface_count' tests_output.log \
    | grep -q -E "SCRIPT ERROR|Parse Error|ERROR:"; then
  echo "エンジンのエラー出力があります（tests_output.log を確認）"
  status=1
fi
rm -f tests_output.log
exit $status
