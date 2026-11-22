# BLIND ACT v3 — design and work split

The owner wants: many more kinds of jump scare; a much larger flat (many
rooms, an attic, secret passages); a much longer night (free time while he is
away, a cannibal dinner with her head beside your plate, more of our own);
the "press E to grab the knife" bait removed; colour (mostly cool, never all
grey-white); an outdoor walk through a housing estate at night, ringed by a
forest (moonlight, flickering street lamps, mist); a lit doorway where he
opens the door with his face covered in blood; a choice to turn and run, an
axe chase into the forest (Don't Scream's forest is the mood reference:
dense, misty, silent, paths that lose you); sprint (double-tap W) with a
stamina bar; a lower eye height.

Godot 4.7.2 Forward+, everything built in code; textures, meshes and sounds
are generated (Python/numpy, Blender for characters). Godot binary:
`/root/.local/godot/Godot_v4.7.2-stable_linux.x86_64`. Run
`$GODOT --headless --path . --import` after adding assets or class_name
scripts. Stills: `CAPTURE_TIMEOUT=900 GODOT=$GODOT tools/capture.sh SCENE OUT "t1,t2" 960x540 [user args]`
(software Vulkan, about 1 fps, so one capture at a time; the machine has 4
cores shared by several workers).

## Ownership (parallel work; do not edit files you do not own)

| who | owns |
|---|---|
| director (main session) | game.gd, player.gd, scares.gd, night_state.gd, game_ui.gd, i18n.gd, character_rig.gd, scripts/acts/* except act_outside.gd, tools/gen_gore.py, tools/gen_scare_sfx.py, tools/gen_sfx_v3.py |
| interior worker | flat_builder.gd, props.gd, scripts/rooms/*.gd, new texture tools for interiors |
| exterior worker | scripts/exterior_builder.gd, scripts/exterior_props.gd, scripts/acts/act_outside.gd, scenes/outside_test.tscn, scripts/outside_test.gd, tools/gen_forest.py, tools/gen_outside_sfx.py, shaders/foliage*.gdshader, shaders/night_sky.gdshader, assets/textures/forest/*, assets/audio/amb_forest*, step_leaf_*, step_gravel_* |

Prompt keys an interactable may use (the director adds the text):
ACT_SEARCH, ACT_TAKE, ACT_HIDE, ACT_PHONE, ACT_OPEN, ACT_PUSH, ACT_CLIMB,
ACT_PEEP, ACT_READ, ACT_LOOK, ACT_SAFE, ACT_FUSE, ACT_SIT, ACT_SLEEP,
ACT_ENTER, ACT_WASH.

## Interior floor plan (flat coordinates, metres)

x grows east, z grows away from the front door (front door at z = 0, x = 0),
y up. CEIL = 2.75, walls WT = 0.16 thick centred on the lines given.

Existing rooms (do not move them; game.gd relies on their coordinates):
- Hall x[-0.65,0.65] z[0,6.4]. ADD openings: x1 z[1.55,2.45] (study door),
  x0 z[4.95,5.75] (WC door). Move the `photo_her` picture from z 4.75 to 4.25.
- Living x[-5.2,-0.65] z[0,4.6] (piano against x0 at z 1.7-2.7). ADD opening
  x0 z[3.25,4.2] (door to the dining room). Move the sheeted chair from
  (-4.72,0,4.12) to the south-west corner (-4.72,0,0.55).
- Bath x[0.65,3.0] z[3.4,5.8]. ADD a peephole in x1 at z[4.55,4.63],
  y[1.52,1.58] (the hidden passage looks into it).
- Bedroom x[-2.4,2.4] z[6.4,9.8]. ADD an opening in x1 at z[7.0,8.0], top
  2.0, behind the wardrobe; the wardrobe's back panel (now a fixed box at
  (2.37,1.05,7.5)) becomes a hinged secret panel `doors["wardrobe_back"]`,
  closed by default. ADD a peephole in x1 at z[8.95,9.03] y[1.5,1.56].

New rooms:
- Study x[0.65,4.6] z[0,3.4]: door from the hall (x0 z[1.55,2.45]); window
  in x1 z[1.0,2.4] sill 0.9 top 2.2; a bookcase that is a secret door in z1
  at x[3.0,3.85] (hinge Node3D `doors["bookcase"]`, swings into the study;
  store metas "closed_rot" and "open_rot"). Walls: deep navy / indigo damask.
- Guest WC x[-2.4,-0.65] z[4.6,6.4]: door from the hall (x1 z[4.95,5.75]).
  Pale blue tiles.
- Dining room x[-9.8,-5.2] z[0,4.6]: door from the living room (x1
  z[3.25,4.2]); door to the kitchen (z1 x[-7.1,-6.2]); two tall windows in
  x0 at z[0.8,1.8] and z[2.8,3.8] (sill 0.8, top 2.3). Oxblood / burgundy
  damask and warm candlelight: the one warm room.
- Kitchen x[-9.8,-5.2] z[4.6,9.8]: from the dining room (z0 x[-7.1,-6.2]);
  door to the laundry (x1 z[8.8,9.7]); door to the pantry (z1 x[-9.4,-8.5]);
  window in x0 z[6.4,7.8] sill 0.95. Mint / eau-de-nil tiles, a greenish
  tube light and a warmer bulb over the stove.
- Pantry x[-9.8,-7.6] z[9.8,12.0]: from the kitchen (z0 x[-9.4,-8.5]).
  Pale blue-green lime wash.
- Laundry and attic stair x[-5.2,-2.4] z[6.4,11.0]: from the kitchen (x0
  z[8.8,9.7]). The attic stair runs along the east wall in x[-3.35,-2.45],
  bottom at z = 9.6 (floor), rising towards -z to z = 6.45 at y = 2.95. One
  invisible ramp collider (about 43 degrees; the player is a CharacterBody3D
  with floor_max_angle 45) plus visual treads without colliders; a railing on
  its west side. No ceiling over x[-3.35,-2.45] z[6.45,8.6]. Blue-grey paint.
- Hidden passage: A x[3.0,3.85] z[3.4,5.8] and B x[2.4,3.85] z[5.8,9.8].
  New walls: x = 3.85 z[3.4,9.8]; x = 2.4 z[5.8,6.4]; z = 9.8 x[2.4,3.85].
  Ceiling at CEIL with a hatch hole x[3.05,3.75] z[6.3,6.9]; a ladder
  against x = 3.85 under it. Rough boards, bare brick and lath.
- Attic: floor top y = 2.95 (slab y 2.85-2.95 with colliders) over
  x[-5.2,3.85] z[3.4,9.8], with holes for the stair x[-3.35,-2.45]
  z[6.45,8.6] (railing round it) and the hatch x[3.05,3.75] z[6.3,6.9].
  Gable roof, ridge along x at z = 6.6 with its underside at y = 5.65; eaves
  at z = 3.4 and 9.8 on knee walls 0.8 high; gable walls at x = -5.2 and
  3.85 (roof planes and gables have colliders). Partition at x = -0.6 with a
  door at z[6.15,7.0]: garret (guest room) to the west, storage to the east.
  A skylight in the south roof plane over the garret near x[-4.0,-3.2].

Interactables to register (id: prompt) and spots (FlatBuilder.spots):
- study: `study_phone` ACT_PHONE, `files` ACT_SEARCH, `desk` ACT_SEARCH,
  `safe` ACT_SAFE, `bookcase` ACT_PUSH; spots study_desk, study_phone, safe,
  files, bookcase_study (stand in front), bookcase_passage (stand behind).
- WC: spots wc_door (in the hall outside it), wc_stand.
- dining: `dinner_chair` ACT_SIT; spots dinner_seat (floor point of the
  player's chair), dinner_look (a point straight ahead of the seated player),
  his_seat, head_stand (top of a cake stand at the player's left, where her
  head will rest), plate, wine_glass, candles.
- kitchen: `plates` ACT_TAKE, `cutlery` ACT_TAKE, `fridge` ACT_OPEN,
  `kitchen_sink` ACT_WASH; spots stove (where he stands cooking),
  chop_block, kitchen_sink, fridge, plates, cutlery, kitchen_mid.
- pantry: `freezer` ACT_OPEN; spots freezer, pantry_mid.
- laundry: `fusebox` ACT_FUSE, `crowbar` ACT_TAKE; spots fusebox, crowbar,
  stair_bottom (floor in front of the first tread), stair_top (attic floor).
- passage: `ladder_up` ACT_CLIMB, `peep_bath` ACT_PEEP, `peep_bed` ACT_PEEP,
  `wardrobe_back_p` ACT_PUSH (passage side), `bookcase_p` ACT_PUSH (passage
  side); and `wardrobe_back` ACT_PUSH inside the wardrobe. Spots
  ladder_bottom, peep_bath, peep_bed, passage_mid, passage_north.
- attic: `attic_bed` ACT_SLEEP, `skylight` ACT_CLIMB, `diary` ACT_READ,
  `canes` ACT_LOOK, `camera` ACT_TAKE, `hatch_down` ACT_CLIMB, `trunk`
  ACT_SEARCH; spots attic_arrive, attic_bed, attic_bed_head, skylight,
  hatch_top, garret_mid, storage_mid, diary, canes, camera.
- hiding (ACT_HIDE): `hide_garret` (the garret wardrobe), `hide_dining`
  (under the dining table), `hide_pantry` (behind the pantry door / shelves);
  each with spots hide_<x>_in and hide_<x>_front.

Rules: doorways >= 0.9 m; walkways >= 0.9 m between colliders; nothing the
player can be wedged into (either >= 0.8 m wide or sealed solid); door leaves
stand open against walls unless noted; every piece of furniture has a simple
box collider; lights: shadows only on the one or two key lights per room.

## Story of the night (director)

Home (phone) -> outside: through the estate and the misty forest edge to her
block -> stairwell -> her door: it opens on a lit hall, his face and shirt
red with blood. Choice: play blind and go in, or turn and run (he takes an
axe from behind the door: chase down the stairs and into the forest).
Inside: her body in the hall -> piece 1 -> wash -> free time (he goes to the
WC; find evidence or sit still) -> piece 2: the wire; "she wants to play with
you": her head held up by the hair, turning slowly before your eyes ->
kitchen: help set the table -> dinner: her, cooked; her head on a cake stand
beside your plate -> the neighbour at the door -> free time (he takes the
bags down): attic, passage, study safe -> the photograph -> the night in the
attic garret -> three o'clock: the last piece, the last test, the endings.
Exposed anywhere: he locks the front door; escape by the spare key (study
safe), the crowbar (nailed bedroom window, fire escape), the skylight (roof),
or the fuse box (blackout); or hide.

## Exterior (exterior worker)

`ExteriorBuilder` (scripts/exterior_builder.gd, `class_name ExteriorBuilder
extends Node3D`), placed by game.gd at world position (400, 0, 0); build in
local coordinates. Contents: a 1980s housing estate at night (five 5-6
storey blocks round a courtyard, unit entrances with numbers, some lit
windows, balconies, drainpipes, bins, a bike shed, a parked car, benches,
a fence with a gap to the forest), street lamps (some flickering; cold
mercury light, one or two sodium), mist, a moon; a dense mixed forest all
round (pines/spruces and bare deciduous trees with good bark, needles and
leaves, undergrowth, rocks, stumps, fallen logs, leaf litter, paths), and a
forest chase route (150-250 m) from the estate to a road (the escape), with
side paths, dead ends, landmarks and hiding places.

API (the director scripts the acts and the chase against this):
- `func build() -> void` (may be a coroutine: `await ext.build()`).
- `var spots := {}`: his_door (start, outside his block), her_unit_door
  (outside her block's unit 3 entrance), courtyard_mid, forest_gate,
  forest_exit (the road), chase_start (just outside her unit door), and
  hide_1..hide_N (hiding places in the forest).
- interactable Area3D (collision_layer 2, metas "interact" and "id") with
  id `her_unit`, prompt ACT_ENTER, at her unit door.
- `func height_at(x: float, z: float) -> float` (local ground height).
- `func path(from: Vector3, to: Vector3) -> PackedVector3Array` (global
  points; AStarGrid2D over the whole area with trees/rocks/buildings solid;
  y from height_at). Fast enough to call every 0.3 s.
- `func enter(world_env: WorldEnvironment) -> void` / `func exit(...)`:
  switch the environment to the outdoor night (sky, moon light, fog,
  ambient) and back, and toggle the outdoor lights.
- `scripts/acts/act_outside.gd` (`class_name ActOutside extends RefCounted`,
  `func run(game: Node, g: int) -> void`): the walk from his door to her unit
  door (objective keys OBJ_OUTSIDE / HINT_OUTSIDE), returns when the player
  uses `her_unit`.
- a test scene `scenes/outside_test.tscn` (+ scripts/outside_test.gd) that
  builds the exterior and a Player (scripts/player.gd, walk mode) at his
  door, for walk tests and captures.
