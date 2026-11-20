#!/usr/bin/env bash
# Render still frames of a scene in a headless container (software Vulkan).
#   tools/capture.sh SCENE OUT_DIR "1.5,3" [WxH] [extra user args...]
# e.g. tools/capture.sh res://scenes/pregame.tscn /tmp/shots "2,5" 1280x720 --state=story
set -euo pipefail
SCENE=${1:?scene}; OUT=${2:?out dir}; SHOTS=${3:-1.2}; RES=${4:-1280x720}; shift 4 || true
GODOT_BIN=${GODOT:-godot}
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
timeout ${CAPTURE_TIMEOUT:-240} xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT_BIN" --path . --audio-driver Dummy --resolution "$RES" --fixed-fps 20 "$SCENE" \
  -- --capture --shots="$SHOTS" --out="$OUT" "$@" 2>&1 | grep -vE "ALSA|alsa|audio_driver|^\s*$" || true
