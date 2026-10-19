#!/usr/bin/env bash
# 【クラウド(Linux)環境専用】公式Android SDKがダウンロードできない環境で、APKに署名するための代替ツールを用意する。
# Windows PC では使わない（README の手順どおり公式 Android SDK を入れる）。
#   署名ライブラリ: com.android.tools.build:apksig 2.3.0（Google製, Apache-2.0, Maven Centralから取得）
#   v2署名のみ対応 → Android 7.0 (API 24) 以上で有効
# 使い方: tools/cloud_android/setup.sh <作業ディレクトリ>  → <dir>/sdk を Godot の android_sdk_path に設定
set -eu
DIR="$(cd "$1" && pwd)"
SRC="$(cd "$(dirname "$0")" && pwd)"
B="$DIR/sdk/build-tools/34.0.0"
mkdir -p "$B" "$DIR/sdk/platform-tools"
curl -sSL -o "$B/apksig.jar" https://repo1.maven.org/maven2/com/android/tools/build/apksig/2.3.0/apksig-2.3.0.jar
javac -d "$B" -cp "$B/apksig.jar" "$SRC/MiniApkSigner.java"
cat > "$B/apksigner" <<EOS
#!/bin/sh
exec java --add-exports java.base/sun.security.x509=ALL-UNNAMED --add-exports java.base/sun.security.pkcs=ALL-UNNAMED --add-exports java.base/sun.security.util=ALL-UNNAMED -cp "$B:$B/apksig.jar" MiniApkSigner "\$@"
EOS
chmod +x "$B/apksigner"
printf '#!/bin/sh\necho "adb stub (cloud)"\n' > "$DIR/sdk/platform-tools/adb"
chmod +x "$DIR/sdk/platform-tools/adb"
echo "OK: android_sdk_path = $DIR/sdk"
