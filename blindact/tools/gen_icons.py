#!/usr/bin/env python3
"""Write the thin-line UI pictograms as SVG (64x64 viewBox, light bone colour).

Godot imports SVGs natively; tools/fix_imports.py sets them to 2x scale with
mipmaps so they stay crisp at any resolution.
Usage: python3 tools/gen_icons.py      (writes assets/ui/icons/*.svg)
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "ui" / "icons"
OUT.mkdir(parents=True, exist_ok=True)

C = "#c9c2ba"   # bone
R = "#a3120f"   # blood
S = 'fill="none" stroke="%s" stroke-linecap="round" stroke-linejoin="round"' % C

ICONS = {
    # 语言 / Language
    "globe": f'''
  <circle cx="32" cy="32" r="23" {S} stroke-width="3.4"/>
  <ellipse cx="32" cy="32" rx="10" ry="23" {S} stroke-width="2.8"/>
  <path d="M9 32 H55 M13 20 H51 M13 44 H51" {S} stroke-width="2.6"/>''',
    # 画面亮度 / Brightness
    "sun": f'''
  <circle cx="32" cy="32" r="10" {S} stroke-width="3.4"/>
  <path d="M32 6 V13 M32 51 V58 M6 32 H13 M51 32 H58 M13.6 13.6 L18.6 18.6 M45.4 45.4 L50.4 50.4 M13.6 50.4 L18.6 45.4 M45.4 18.6 L50.4 13.6" {S} stroke-width="3.4"/>''',
    # 画面质量 / Graphics quality: monitor with a sparkle
    "display": f'''
  <rect x="7" y="11" width="50" height="33" rx="3" {S} stroke-width="3.4"/>
  <path d="M24 55 H40 M32 44 V55" {S} stroke-width="3.4"/>
  <path d="M32 18 L34.6 25.4 L42 28 L34.6 30.6 L32 38 L29.4 30.6 L22 28 L29.4 25.4 Z" fill="{C}"/>''',
    # 全屏显示 / Fullscreen
    "fullscreen": f'''
  <path d="M8 22 V8 H22 M42 8 H56 V22 M56 42 V56 H42 M22 56 H8 V42" {S} stroke-width="3.8"/>
  <rect x="20" y="20" width="24" height="24" rx="2" {S} stroke-width="2.4" stroke-dasharray="4 4"/>''',
    # 垂直同步 / V-Sync
    "sync": f'''
  <path d="M50 26 A19 19 0 0 0 15.5 20" {S} stroke-width="3.6"/>
  <path d="M14 38 A19 19 0 0 0 48.5 44" {S} stroke-width="3.6"/>
  <path d="M15 9 V21 H27" {S} stroke-width="3.6"/>
  <path d="M49 55 V43 H37" {S} stroke-width="3.6"/>''',
    # 胶片颗粒 / Film grain
    "film": f'''
  <rect x="12" y="6" width="40" height="52" rx="2" {S} stroke-width="3.4"/>
  <path d="M22 6 V58 M42 6 V58" {S} stroke-width="2.6"/>
  <path d="M15.5 12 H18.5 M15.5 22 H18.5 M15.5 32 H18.5 M15.5 42 H18.5 M15.5 52 H18.5 M45.5 12 H48.5 M45.5 22 H48.5 M45.5 32 H48.5 M45.5 42 H48.5 M45.5 52 H48.5" {S} stroke-width="3"/>
  <circle cx="29" cy="25" r="1.6" fill="{C}"/><circle cx="35" cy="34" r="1.6" fill="{C}"/><circle cx="30" cy="42" r="1.6" fill="{C}"/>''',
    # 心跳震屏 / Heartbeat shake: heart with an ECG trace
    "heartbeat": f'''
  <path d="M32 54 C20 45 8 36 8 23 C8 15 14 9 21 9 C26 9 30 12 32 16 C34 12 38 9 43 9 C50 9 56 15 56 23 C56 36 44 45 32 54 Z" {S} stroke-width="3.4"/>
  <path d="M4 32 H18 L23 24 L29 41 L35 19 L40 32 H60" fill="none" stroke="{R}" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/>''',
    # 主音量 / Master volume
    "volume": f'''
  <path d="M8 24 H18 L31 12 V52 L18 40 H8 Z" {S} stroke-width="3.4"/>
  <path d="M40 23 A12 12 0 0 1 40 41 M46 16 A21 21 0 0 1 46 48" {S} stroke-width="3.4"/>''',
    # 音乐 / Music
    "music": f'''
  <path d="M24 46 V14 L52 8 V40" {S} stroke-width="3.4"/>
  <path d="M24 22 L52 16" {S} stroke-width="3"/>
  <ellipse cx="17" cy="47" rx="7.5" ry="6" fill="{C}"/>
  <ellipse cx="45" cy="41" rx="7.5" ry="6" fill="{C}"/>''',
    # 音效 / Sound effects: waveform
    "waveform": f'''
  <path d="M8 28 V36 M16 22 V42 M24 12 V52 M32 20 V44 M40 26 V38 M48 16 V48 M56 28 V36" {S} stroke-width="4"/>''',
    # 返回 / Back
    "back": f'''
  <path d="M26 16 L10 32 L26 48 M11 32 H54" {S} stroke-width="3.8"/>''',
}

for name, body in ICONS.items():
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">{body}\n</svg>\n'
    (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")
    print("wrote", name)
