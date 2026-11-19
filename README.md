# CORRIDOR

First-person horror game (Godot 4.7, Forward+). This milestone is the **main menu**:
an endless first-person walk down a lakeside pergola corridor at night, rebuilt in 3D
from real photos (`art/reference/`). The corridor never ends: stretches you have passed
are rebuilt ahead of you — sometimes as exact copies of what you just walked through,
sometimes as something new (lamps alive, flickering, dying or dead, banyan trees, things
left on the benches). The light ahead never gets closer. Symptoms come and go at random
and alternate: a violent heartbeat that shakes the screen, vertigo (the corridor tilts and
swims, double vision, muffled sound), tinnitus (a high ringing, everything else drowned
out, the image washes out) — over the score. The menu floats over it:
**开始游戏 / Start Game** and **设置 / Settings**.

## Play

Download `Corridor.exe` (Windows 10/11, x86-64, a GPU with Vulkan or DirectX 12) and run
it. It starts fullscreen. Headphones and a dark room are recommended (that is what the two
icons at the bottom left say).

| Key | Action |
|---|---|
| Mouse / ↑ ↓ / Enter | choose menu items |
| ← → | change a setting |
| Esc | back / leave prompt |

Settings (saved to `%APPDATA%\Godot\app_userdata\CORRIDOR\settings.cfg`): language
(简体中文 / English), brightness, graphics quality (Low → Ultra), fullscreen, V-Sync,
film grain, heartbeat screen shake, master / music / effects volume.

## What's in the scene

* **Corridor**: sandstone-clad pillars whose block faces are rectified straight out of the
  photos, granite plinths, weathered timber beams (also from the photos), rafters with dead
  vines hanging down, curved "美人靠" goose-neck benches, procedural paving with damp patches
  that turn into reflective puddles.
* **Surroundings**: the lake (screen-space reflections), the far shore with a lit railing,
  tree lines, a distant building with a few lit windows, banyan trees with aerial roots under
  green ground uplights, the cold floodlight at the far end (with the phone-camera starburst
  seen in the photos).
* **Atmosphere**: volumetric fog and lake mist, swaying pendant bulbs with individual
  flicker behaviours (steady / flickering / dying) and positional buzz, moonlight through the
  pergola, AgX tonemapping, film grain, lens softness, vignette.
* **Body**: heartbeat (lub-dub) that drives a camera spring kick, FOV punch, zoom/distortion
  pulse and a blood-red vignette; breathing that goes calm → heavy → panting; footsteps.
* **Sound**: everything is synthesised by `tools/gen_audio.py` — score (drones, dissonant
  string clusters, a detuned slowing music box, bowed metal, piano tolls), night ambience
  (crickets, frogs, water, wind), lamps, heartbeat, breathing, footsteps, stingers, UI.
* **Logo**: weathered Cinzel capitals; the "I" is a splatter of blood that swells with each
  heartbeat (`tools/gen_logo.py`).

## Develop

Requirements: Godot **4.7.2** (+ export templates for Windows), Python 3 with `numpy scipy
opencv-python-headless soundfile fonttools pillow`, `ffmpeg` (libvorbis).

```bash
# regenerate assets (all deterministic)
python3 tools/gen_textures.py
python3 tools/gen_audio.py
python3 tools/gen_logo.py
python3 tools/gen_icons.py
python3 tools/subset_fonts.py        # after adding Chinese UI text
godot --headless --path . --import && python3 tools/fix_imports.py && godot --headless --path . --import

# export the Windows build (single exe, pck embedded)
godot --headless --path . --export-release "Windows Desktop" build/windows/Corridor.exe
```

Screenshots without a GPU (software Vulkan, slow): `tools/capture.sh OUT_DIR "1.5" 1280x720 [--z=-20 --noui --settings --lang=en]`.

Project layout:

| Path | |
|---|---|
| `scenes/main_menu.tscn` → `scripts/main_menu.gd` | director: world, timeline/scares, audio mix, post FX, UI |
| `scripts/corridor_builder.gd` | materials, shared meshes, banyan/prop templates, backdrop; runs the segment treadmill |
| `scripts/corridor_segment.gd` | one 6.4 m stretch, rebuilt from a seed (same seed = identical stretch) |
| `scripts/flicker_lamp.gd` | failing lamps (flicker modes, sway, buzz, starburst) |
| `scripts/fp_walker.gd` | first-person camera walk, bob, breathing, heartbeat springs |
| `scripts/body_sounds.gd` | heartbeat + breathing controller |
| `scripts/world_env.gd` | sky, fog, mist, moon, tonemapping, quality presets |
| `scripts/menu_ui.gd`, `horror_button.gd`, `cycle_button.gd`, `ui_widgets.gd` | menu UI |
| `scripts/settings.gd` (autoload) / `scripts/i18n.gd` | settings persistence, audio buses, translations |
| `shaders/` | stone atlas, wood strips, paving, water, sky, foliage, strands, building windows, flare, logo, post |
| `tools/` | asset generators and helpers (ignored by Godot) |
| `.claude/skills/corridor-gamedev/` | notes for Claude Code sessions working on this repo |

## Credits / licences

* Reference photos: the project owner.
* Fonts: Cinzel and Noto Serif CJK SC (subset), SIL Open Font License 1.1 — see `assets/fonts/`.
* All textures other than the photo-derived ones, all audio, the logo and icons are generated by the scripts in `tools/`.
