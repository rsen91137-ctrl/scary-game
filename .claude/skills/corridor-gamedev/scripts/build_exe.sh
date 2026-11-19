#!/usr/bin/env bash
# Import -> fix import options -> import -> export the Windows exe (+ zip).
# Usage: GODOT=/path/to/godot bash .claude/skills/corridor-gamedev/scripts/build_exe.sh
set -euo pipefail
: "${GODOT:?set GODOT to the Godot 4.7.2 binary (see setup_godot.sh)}"
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$ROOT"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
python3 tools/fix_imports.py
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p build/windows
# never pipe the export through `head`: SIGPIPE kills it and leaves Corridor.tmp
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/Corridor.exe > build/export_windows.log 2>&1
grep -iE "^ERROR|SCRIPT ERROR" build/export_windows.log && { echo "export reported errors (see build/export_windows.log)"; exit 1; }
(cd build/windows && rm -f Corridor-windows.zip && zip -q -9 Corridor-windows.zip Corridor.exe)
ls -la build/windows
