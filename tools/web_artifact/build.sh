#!/usr/bin/env bash
# Web版をスマホのブラウザ用の1フォルダにまとめる（Claudeのアーティファクトなど、1ファイル15MBまでの置き場所向け）。
#   1. Godot で Web 書き出し（build/web/）  2. この処理で build/web_artifact/ を作る
# ゲーム本体(.wasm 35MB)は gzip 圧縮し、ページ側(shell.html)がブラウザ内で展開して起動する。
set -eu
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --export-release "Web" build/web/index.html >/dev/null 2>&1
OUT=build/web_artifact
mkdir -p "$OUT"
cp build/web/index.js "$OUT/engine.js"
cp build/web/index.audio.worklet.js "$OUT/"
gzip -9 -c build/web/index.wasm > "$OUT/game-gz.wasm"
cp build/web/index.pck "$OUT/game-pck.wasm"
sed -e "s/__WASM_SIZE__/$(stat -c %s build/web/index.wasm)/" -e "s/__PCK_SIZE__/$(stat -c %s build/web/index.pck)/" \
  tools/web_artifact/shell.html > "$OUT/ashen-crown.html"
ls -la "$OUT"
