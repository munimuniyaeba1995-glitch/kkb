#!/usr/bin/env bash
# 実描画でスクリーンショットを撮る（Linux/Xvfb 用。Windowsでは不要＝普通に起動して確認）
#   tools/screenshot.sh          … PC画面（1600x900、マウス操作）
#   tools/screenshot.sh --touch  … スマホ画面（1600x720 = 20:9、タッチUI）
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
if [ "${1:-}" = "--touch" ]; then RES=1600x720; ARGS="-- --touch"; else RES=1600x900; ARGS=""; fi
xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path . --rendering-driver opengl3 --resolution "$RES" \
  res://tests/screenshot.tscn $ARGS 2>&1 | grep -E "saved|perf|SCRIPT ERROR|Parse Error"
