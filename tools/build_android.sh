#!/usr/bin/env bash
# Android用デバッグAPKを書き出す（Godotエディタの「プロジェクト→エクスポート」と同じ処理）。
# 事前に: Androidエクスポートテンプレート、エディタ設定の Android SDK / Java SDK パス、デバッグ用キーストア。
#   GODOT=<godot実行ファイル> KEYSTORE=<debug.keystore> tools/build_android.sh
# キーストアのユーザー名・パスワードは環境変数 KEYSTORE_USER / KEYSTORE_PASS で渡す（ファイルに書かない）。
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build/android
GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE" \
GODOT_ANDROID_KEYSTORE_DEBUG_USER="${KEYSTORE_USER:-androiddebugkey}" \
GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${KEYSTORE_PASS:?KEYSTORE_PASS を設定してください}" \
  "$GODOT" --headless --path . --export-debug "Android" build/android/AshenCrown.apk 2>&1 \
  | grep -E "export:|ERROR|WARNING" | grep -v -E 'Parameter "m"|mesh_get_surface'
ls -la build/android/AshenCrown.apk
