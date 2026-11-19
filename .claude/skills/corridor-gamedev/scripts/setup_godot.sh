#!/usr/bin/env bash
# One-time toolchain setup for a fresh Linux container (Ubuntu 24.04).
# Installs Godot 4.7.2 + the Windows/Linux export templates, software Vulkan
# (lavapipe) + Xvfb for headless screenshots, the CJK font source, ffmpeg and
# the Python packages used by tools/*.py.
# Usage: bash .claude/skills/corridor-gamedev/scripts/setup_godot.sh [install_dir]
# Prints the godot binary path at the end; export it as GODOT.
set -euo pipefail
VER=4.7.2
DIR=${1:-$HOME/.local/godot}
mkdir -p "$DIR"
cd "$DIR"
if [ ! -x "Godot_v${VER}-stable_linux.x86_64" ]; then
  curl -sSL -o godot.zip "https://github.com/godotengine/godot/releases/download/${VER}-stable/Godot_v${VER}-stable_linux.x86_64.zip"
  unzip -o -q godot.zip && rm godot.zip
fi
TD="$HOME/.local/share/godot/export_templates/${VER}.stable"
if [ ! -f "$TD/windows_release_x86_64.exe" ]; then
  mkdir -p "$TD"
  curl -sSL -o templates.tpz "https://github.com/godotengine/godot/releases/download/${VER}-stable/Godot_v${VER}-stable_export_templates.tpz"
  unzip -o -j -q templates.tpz templates/version.txt templates/windows_release_x86_64.exe \
    templates/windows_debug_x86_64.exe templates/linux_release.x86_64 templates/linux_debug.x86_64 -d "$TD"
  rm templates.tpz   # 1.3 GB, we only keep what we need
fi
if command -v apt-get >/dev/null; then
  (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    mesa-vulkan-drivers libvulkan1 xvfb fonts-noto-cjk ffmpeg >/dev/null) || echo "apt install failed (continuing)"
fi
pip3 install -q numpy scipy opencv-python-headless soundfile fonttools brotli pillow 2>/dev/null || true
echo "GODOT=$DIR/Godot_v${VER}-stable_linux.x86_64"
