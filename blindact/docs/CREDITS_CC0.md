# Third-party CC0 assets

Everything under `assets/cc0/` was downloaded on 2026-11-22 for the forest/outdoor work. All of it is CC0
or the author's own "commercial use, no attribution" licence; attribution is not required, but the authors are
listed here so the credits screen can thank them. Nothing here is under a non-commercial or attribution licence.

- Models: 15 Poly Haven models (the four heaviest — shrub_01, root_cluster_01, pine_roots, bark_debris_01 — were left out) as glTF 2.0 with 1k JPG textures (`assets/cc0/models/<id>/<id>_1k.gltf`, the
  `.bin` and `textures/` sit next to it; keep them together).
- Textures: 12 Poly Haven PBR sets at 1k (`assets/cc0/textures/<id>/<id>_albedo|normal|rough|ao.jpg`, normal
  maps are OpenGL / Y+ like Godot expects).
- Audio: 21 sounds cut from one itch.io pack by Liminal Games (growls and leaf, gravel and mud footsteps; the author states the pack is AI-generated) (`assets/cc0/audio/liminal_horror_sfx/`).

## Poly Haven

Licence as stated by Poly Haven: **CC0 1.0 Universal** (public domain dedication); Poly Haven applies it to
every asset on the site (<https://polyhaven.com/license>). File lists and metadata came from
`api.polyhaven.com`, the files from `dl.polyhaven.org` (MD5-checked). The polyhaven.com pages themselves were
not reachable from the build sandbox, so the per-asset page text was not re-read; the asset page for each is linked.

### Models (glTF, 1k textures)

Size is the glTF bounding box in Godot axes, width (X) x height (Y) x depth (Z), in metres; for files with
several meshes it is the box around all of them (instance the scene and pick the child meshes you need).
Poly Haven's own `dimensions` field (mm, Blender axes) agrees except where a note says otherwise.

| Asset | Author(s) | Source | Licence | Local path | Triangles (glTF) | Poly Haven `polycount` | Size W x H x D (m) | Meshes | Notes |
|---|---|---|---|---|---:|---:|---|---:|---|
| Dead Tree Trunk | Rob Tuytel | <https://polyhaven.com/a/dead_tree_trunk> | CC0 1.0 | `assets/cc0/models/dead_tree_trunk/dead_tree_trunk_1k.gltf` | 101,802 | 101,802 | 3.05 x 0.29 x 0.28 | 1 |  |
| Dead Tree Trunk 02 | Jenelle van Heerden (photography), Rico Cilliers (processing) | <https://polyhaven.com/a/dead_tree_trunk_02> | CC0 1.0 | `assets/cc0/models/dead_tree_trunk_02/dead_tree_trunk_02_1k.gltf` | 83,128 | 155,864 | 4.05 x 1.05 x 1.06 | 1 |  |
| Tree Stump 01 | Rob Tuytel | <https://polyhaven.com/a/tree_stump_01> | CC0 1.0 | `assets/cc0/models/tree_stump_01/tree_stump_01_1k.gltf` | 41,046 | 41,046 | 1.43 x 0.57 x 1.59 | 1 |  |
| Tree Stump 02 | Rob Tuytel | <https://polyhaven.com/a/tree_stump_02> | CC0 1.0 | `assets/cc0/models/tree_stump_02/tree_stump_02_1k.gltf` | 62,345 | 62,345 | 1.52 x 0.52 x 1.39 | 1 |  |
| Shrub 02 | Rico Cilliers | <https://polyhaven.com/a/shrub_02> | CC0 1.0 | `assets/cc0/models/shrub_02/shrub_02_1k.gltf` | 27,254 | 52,317 | 6.05 x 1.70 x 2.29 | 4 | 4 shrub variants side by side; glTF size differs from Poly Haven's listed 5.34 x 2.06 x 2.07 m; alpha-scissor leaves |
| Shrub 03 | Rico Cilliers | <https://polyhaven.com/a/shrub_03> | CC0 1.0 | `assets/cc0/models/shrub_03/shrub_03_1k.gltf` | 8,287 | 16,955 | 1.37 x 0.40 x 0.15 | 4 | 4 separate meshes laid out side by side; alpha-scissor leaves |
| Shrub 04 | Rico Cilliers | <https://polyhaven.com/a/shrub_04> | CC0 1.0 | `assets/cc0/models/shrub_04/shrub_04_1k.gltf` | 27,327 | 47,813 | 0.58 x 0.22 x 0.15 | 1 | glTF is ~0.78x Poly Haven's listed size (0.75 x 0.19 x 0.28 m); alpha-scissor leaves |
| Fern 02 | Rob Tuytel (scanning), Rico Cilliers (modeling) | <https://polyhaven.com/a/fern_02> | CC0 1.0 | `assets/cc0/models/fern_02/fern_02_1k.gltf` | 6,232 | 6,232 | 1.97 x 0.43 x 1.72 | 4 | 4 separate meshes laid out side by side; alpha-scissor leaves |
| Nettle Plant | Rob Tuytel (photography), Rico Cilliers (modeling) | <https://polyhaven.com/a/nettle_plant> | CC0 1.0 | `assets/cc0/models/nettle_plant/nettle_plant_1k.gltf` | 31,304 | 46,195 | 1.08 x 0.22 x 0.10 | 6 | 6 separate meshes laid out side by side; alpha-scissor leaves |
| Moss 01 | Rob Tuytel | <https://polyhaven.com/a/moss_01> | CC0 1.0 | `assets/cc0/models/moss_01/moss_01_1k.gltf` | 204 | 246,170 | 0.21 x 0.04 x 0.03 | 12 | glTF holds only 12 tiny moss tufts (1-4 cm, 204 tris total, alpha BLEND) meant for scattering; Poly Haven lists 246,170 polys and 0.84 x 0.30 x 0.30 m, which must describe more than the glTF contains (probably the scattered patch in the .blend) |
| Rock Moss Set 01 | Kless Gyzen | <https://polyhaven.com/a/rock_moss_set_01> | CC0 1.0 | `assets/cc0/models/rock_moss_set_01/rock_moss_set_01_1k.gltf` | 63,127 | 63,127 | 8.01 x 1.77 x 6.95 | 6 | 6 separate meshes laid out side by side |
| Rock Moss Set 02 | Kless Gyzen | <https://polyhaven.com/a/rock_moss_set_02> | CC0 1.0 | `assets/cc0/models/rock_moss_set_02/rock_moss_set_02_1k.gltf` | 57,647 | 57,647 | 8.28 x 1.37 x 3.41 | 7 | 7 separate meshes laid out side by side |
| Dry Branches Medium 01 | Rico Cilliers | <https://polyhaven.com/a/dry_branches_medium_01> | CC0 1.0 | `assets/cc0/models/dry_branches_medium_01/dry_branches_medium_01_1k.gltf` | 16,803 | 16,803 | 1.06 x 0.34 x 1.30 | 3 | 3 separate meshes laid out side by side |
| Street Lamp 01 | Josh Dean | <https://polyhaven.com/a/street_lamp_01> | CC0 1.0 | `assets/cc0/models/street_lamp_01/street_lamp_01_1k.gltf` | 30,610 | 30,610 | 0.70 x 3.87 x 0.39 | 1 | free-standing post lamp; glass is alpha BLEND, bulb is a separate material |
| Street Lamp 02 | Josh Dean | <https://polyhaven.com/a/street_lamp_02> | CC0 1.0 | `assets/cc0/models/street_lamp_02/street_lamp_02_1k.gltf` | 20,338 | 20,338 | 0.39 x 1.68 x 0.81 | 1 | wall-mounted bracket lamp; origin at the wall mount |

### Textures (1k JPG)

"Covers" is the real-world area one tile of the texture represents (Poly Haven `dimensions`), useful for UV scale.

| Asset | Author(s) | Source | Licence | Local folder | Maps | Covers (m) |
|---|---|---|---|---|---|---|
| Pine Bark | Dimitrios Savva | <https://polyhaven.com/a/pine_bark> | CC0 1.0 | `assets/cc0/textures/pine_bark/` | albedo, normal, rough, ao | 2.00 x 2.00 |
| Bark Brown 02 | Rob Tuytel | <https://polyhaven.com/a/bark_brown_02> | CC0 1.0 | `assets/cc0/textures/bark_brown_02/` | albedo, normal, rough, ao | 1.00 x 1.00 |
| Knotted Pine Bark | Dimitrios Savva | <https://polyhaven.com/a/knotted_pine_bark> | CC0 1.0 | `assets/cc0/textures/knotted_pine_bark/` | albedo, normal, rough, ao | 1.70 x 1.70 |
| Moss Wood | Rob Tuytel | <https://polyhaven.com/a/moss_wood> | CC0 1.0 | `assets/cc0/textures/moss_wood/` | albedo, normal, rough, ao | 1.00 x 1.00 |
| Forest Floor | eye-candy.xyz | <https://polyhaven.com/a/forest_floor> | CC0 1.0 | `assets/cc0/textures/forest_floor/` | albedo, normal, rough, ao | 2.14 x 2.14 |
| Forest Ground 04 | Rob Tuytel (photography, processing), Rico Cilliers (minor adjustment) | <https://polyhaven.com/a/forest_ground_04> | CC0 1.0 | `assets/cc0/textures/forest_ground_04/` | albedo, normal, rough, ao | 3.15 x 3.15 |
| Forest Leaves 02 | Rob Tuytel | <https://polyhaven.com/a/forest_leaves_02> | CC0 1.0 | `assets/cc0/textures/forest_leaves_02/` | albedo, normal, rough, ao | 3.00 x 3.00 |
| Mud Forest | eye-candy.xyz | <https://polyhaven.com/a/mud_forest> | CC0 1.0 | `assets/cc0/textures/mud_forest/` | albedo, normal, rough, ao | 2.35 x 2.35 |
| Rocky Trail | Amal Kumar | <https://polyhaven.com/a/rocky_trail> | CC0 1.0 | `assets/cc0/textures/rocky_trail/` | albedo, normal, rough, ao | 2.00 x 2.00 |
| Stony Dirt Path | eye-candy.xyz | <https://polyhaven.com/a/stony_dirt_path> | CC0 1.0 | `assets/cc0/textures/stony_dirt_path/` | albedo, normal, rough, ao | 2.17 x 2.17 |
| Mossy Rock | Rob Tuytel | <https://polyhaven.com/a/mossy_rock> | CC0 1.0 | `assets/cc0/textures/mossy_rock/` | albedo, normal, rough, ao | 3.00 x 3.00 |
| Dry Decay Leaves | Amal Kumar | <https://polyhaven.com/a/dry_decay_leaves> | CC0 1.0 | `assets/cc0/textures/dry_decay_leaves/` | albedo, normal, rough, ao | 2.00 x 2.00 |

## Audio: Liminal Games, "FREE HORROR SFX - VN - SCARY SOUND EFFECTS"

- Source: <https://liminal-space-dev.itch.io/free-horror-sfx-sounds> (the `.../free-horror-sfx-sounds-vol-1` URL
  redirects to the same page). Files: `horror_sfx_vol_1.zip` and `horror_sfx_vol_2.zip`.
- Author: Liminal Games (itch.io user `liminal-space-dev`).
- Licence as stated on the page, metadata field: "Asset license: Creative Commons Zero v1.0 Universal".
- Licence terms as written in the page text:
  > Use in both commercial and free projects / Modify sounds as needed / No attribution required /
  > Please don't redistribute or resell the pack itself
- The page says the sounds are **AI-generated** ("AI Disclosure: AI Assisted, Graphics, Sounds"). Stores such as
  Steam ask developers to disclose pre-generated AI content, so list these if they ship.
- Only a curated subset is kept here, cut and processed for the game (not the pack as distributed): mixed to mono,
  DC removed, high-pass filtered (30-80 Hz, the source files carry sub-sonic rumble), trimmed or cut to single
  steps with short fades, the wind beds turned into seamless crossfaded loops, peak-normalised to -1 dBFS,
  Ogg Vorbis q6, 44.1 kHz. Duplicates in the pack (Gravel 5-8 = 1-4, Ambient Wind 7 = 8) were ignored.
- The `*_loop` files loop seamlessly; set `loop = true` on the stream (or in the import settings) for gapless
  playback instead of restarting on `finished`.

| Local file (`assets/cc0/audio/liminal_horror_sfx/`) | What it is | Length (s) | Cut from (pack file, seconds) |
|---|---|---:|---|
| `growl_long_1.ogg` | long deep sustained monster growl, slow swell-in (fundamental ~75 Hz) | 4.87 | vol_1: Monster Growl/Monster Growl (10).mp3 (whole file, trimmed) |
| `growl_long_2.ogg` | long rough growl that tails off at the end | 4.69 | vol_1: Monster Growl/Monster Growl (3).mp3 (whole file, trimmed) |
| `growl_long_3.ogg` | long sustained mid-pitched growl | 4.76 | vol_1: Monster Growl/Monster Growl (8).mp3 (whole file, trimmed) |
| `growl_long_4.ogg` | long deep sustained growl (~90 Hz) | 5.03 | vol_1: Monster Growl/Monster Growl (9).mp3 (whole file, trimmed) |
| `growl_mid_1.ogg` | very deep growl (~60 Hz) with a falling tail | 2.80 | vol_1: Monster Growl/Monster Growl (5).mp3 (whole file, trimmed) |
| `growl_mid_2.ogg` | brighter, more mid-range growl | 2.06 | vol_1: Monster Growl/Monster Growl (7).mp3 (whole file, trimmed) |
| `growl_short.ogg` | short snarl | 0.89 | vol_1: Monster Growl/Monster Growl (4).mp3 (whole file, trimmed) |
| `step_leaves_1.ogg` | single footstep in leaves, crisp broadband crunch (walking pace) | 0.51 | vol_1: Leaves Footsteps/Leaves Footsteps (1).mp3 (0.54-1.04) |
| `step_leaves_2.ogg` | single footstep in leaves, crisp broadband crunch (walking pace) | 0.49 | vol_1: Leaves Footsteps/Leaves Footsteps (1).mp3 (1.53-2.03) |
| `step_leaves_3.ogg` | single footstep in leaves, crisp broadband crunch (walking pace) | 0.48 | vol_1: Leaves Footsteps/Leaves Footsteps (1).mp3 (3.02-3.50) |
| `step_leaves_4.ogg` | single footstep in leaves, crisp broadband crunch (walking pace) | 0.51 | vol_1: Leaves Footsteps/Leaves Footsteps (1).mp3 (3.50-4.01) |
| `step_leaves_5.ogg` | slow, longer leaf-crunch step | 0.76 | vol_1: Leaves Footsteps/Leaves Footsteps (2).mp3 (1.09-1.85) |
| `step_leaves_6.ogg` | slow leaf step (wide-stereo source, mixed to mono) | 0.66 | vol_1: Leaves Footsteps/Leaves Footsteps (4).mp3 (2.59-3.25) |
| `step_mud_1.ogg` | single step from the pack's mud set (soft transient, noisy tail) | 0.68 | vol_2: Mud foosteps/Mud Footsteps (5).mp3 (6.36-7.04) |
| `step_mud_2.ogg` | single step from the pack's mud set (soft transient, noisy tail) | 0.71 | vol_2: Mud foosteps/Mud Footsteps (7).mp3 (4.49-5.20) |
| `step_mud_3.ogg` | single step from the pack's mud set (heel-toe double transient) | 0.70 | vol_2: Mud foosteps/Mud Footsteps (4).mp3 (5.25-5.95) |
| `step_mud_4.ogg` | single step from the pack's mud set (soft transient, noisy tail) | 0.70 | vol_2: Mud foosteps/Mud Footsteps (5).mp3 (3.50-4.20) |
| `step_gravel_1.ogg` | single footstep from the gravel set (crunch transient, noisy tail) | 0.52 | vol_2: Gravel Footsteps/Gravel Footsteps (1).mp3 (3.10-3.62) |
| `step_gravel_2.ogg` | single footstep from the gravel set (crunch transient, noisy tail) | 0.65 | vol_2: Gravel Footsteps/Gravel Footsteps (3).mp3 (3.23-3.88) |
| `step_gravel_3.ogg` | single footstep from the gravel set (crunch transient, noisy tail) | 0.66 | vol_2: Gravel Footsteps/Gravel Footsteps (3).mp3 (4.52-5.17) |
| `step_gravel_4.ogg` | single footstep from the gravel set (two-part crunch) | 0.56 | vol_2: Gravel Footsteps/Gravel Footsteps (1).mp3 (4.74-5.30) |

## Checked but not added

- <https://sami-hiltunen.itch.io/free-audio-asset-collection>: redirects to `nihil-existentia.itch.io`, which the
  sandbox network refused, so its licence could not be read and nothing was downloaded.
