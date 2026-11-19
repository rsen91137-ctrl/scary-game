#!/usr/bin/env bash
# Render still frames of the main menu in a headless container (software Vulkan).
#   tools/capture.sh OUT_DIR "1.5,3" [WxH] [extra user args...]
# e.g. tools/capture.sh /tmp/shots "1.2" 960x540 --z=-20 --quality=2 --noui
# Needs: xvfb-run, mesa-vulkan-drivers; GODOT env var or godot on PATH.
set -euo pipefail
OUT=${1:?out dir}; SHOTS=${2:-1.2}; RES=${3:-960x540}; shift 3 || true
GODOT_BIN=${GODOT:-godot}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT_BIN" --path . --audio-driver Dummy --fixed-fps 10 \
  -- --capture --shots="$SHOTS" --out="$OUT" "$@" 2>&1 | grep -vE "ALSA|alsa|audio_driver|^\s*$" || true
