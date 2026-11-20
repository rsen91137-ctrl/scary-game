#!/usr/bin/env bash
# Import -> fix import options -> import -> export the Windows exe (+ zip).
# Usage: GODOT=/path/to/godot bash tools/build_exe.sh
set -euo pipefail
: "${GODOT:?set GODOT to the Godot 4.7.2 binary}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
python3 tools/fix_imports.py
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/BlindAct.exe > build/export_windows.log 2>&1
grep -iE "^ERROR|SCRIPT ERROR" build/export_windows.log && { echo "export reported errors (see build/export_windows.log)"; exit 1; }
(cd build/windows && rm -f BlindAct-windows.zip && zip -q -9 BlindAct-windows.zip BlindAct.exe)
ls -la build/windows
