@echo off
rem ヘッドレス自動テスト（Windows）。GODOT に Godot の exe のパスを設定してください。
rem 例: set GODOT=C:\Godot\Godot_v4.3-stable_win64_console.exe
if "%GODOT%"=="" set GODOT=godot
cd /d "%~dp0\.."
"%GODOT%" --headless --path . --editor --quit >nul 2>&1
"%GODOT%" --headless --path . res://tests/test_runner.tscn
exit /b %ERRORLEVEL%
