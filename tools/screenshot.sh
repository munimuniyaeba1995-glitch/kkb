#!/usr/bin/env bash
# 実描画でスクリーンショットを撮る（Linux/Xvfb 用。Windowsでは不要＝普通に起動して確認）
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 \
  res://tests/screenshot.tscn 2>&1 | grep -E "saved|SCRIPT ERROR|Parse Error"
ls tests/output/
