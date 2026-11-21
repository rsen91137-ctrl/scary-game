# 03_gore_monster_colour

## Key points

- Blood is invisible for three independent reasons that must all be fixed together: it is authored near-black (brown water-stain decals with 1.2-1.6 % coverage and a 'dirty handprint', multiplied by dark tints; pool and tub are black mirrors with reflections disabled), every light is blue-heavy (linear R/B 0.48 for bulbs, 0.19-0.24 for window light), and the grade attacks warm hues (saturation 0.72, a 'cold' pass that desaturates reds by up to 70 %, glasses at -2.8 stops with red cut first).
- Estimated on-screen colours today are #000000-#040101 for drag marks, pool and tub water, #020404 for the handprint and #0e131b (hue 214, blue-grey) for the head-throw splats, and even a correct blood albedo would end near #070101; existing captures of the rooms contain 0.000 % red pixels.
- 'All grey-white' is literal: every bright surface is authored at 7 % saturation or less, one wallpaper covers hall, living room and bedroom, and the wall shader only fades it further toward grey.
- Colour script: give each room real chroma on the cold side of the wheel (arsenic green, petrol, bottle green, plum, eau-de-nil, drowned blue), keep bone-pale surfaces as blood canvases, and reserve red for blood alone.
- Replace the global desaturation and the 'cold' pass with a hue-keyed grade that desaturates and teals everything except red, and prefer the Filmic tonemapper; the modelled result with glasses on is blood at #8d030a under a room key and #b90914 under a dedicated gore light.
- Make the dark glasses an optical effect (about -1 stop, a grey-green tint that the red key bypasses, frame, smudges, glints) instead of a 2.8-stop underexposure that stays on for the whole flat.
- Light every gore set-piece deliberately: a near-neutral key within 1.5 m placed for grazing highlights, a cull-masked gore light on corpse and pool meshes, a 5 % emission floor, and SSR plus reflection probes, because wet blood cannot read while reflections are disabled.
- Build a real blood system: a generated decal set (albedo, normal, ORM, emission) that follows bloodstain-pattern grammar, a mesh blood shader for pools, the drag ribbon and translucent tub water, and dynamic drips, creeping pools and footprints left by the player, his cane and the husband.
- The first sight must stop being a fade to black and a teleport to the piano bench (game.gd:974-978, 1044): the player walks in and meets the body on a pale floor under a key light, with three stagings offered and the 'interrupted drag' recommended because the react-to-sound rule forces the player to face it.
- Remake her as a minutes-old strangulation in pale clothes (plum congested face, red sclera, open eyes, tongue, a furrow modelled as geometry with the bass-string garrote still in place), and keep the current grey, clouded textures for her later apparitions.
- Five original husband-monsters (Strung Man, Blind Man, Hammerhand, Caller, Hush) and two wife apparitions (Accompanist, Blind Woman) are designed to be built on the existing rig through build-time proportion edits, attached generated meshes, texture variants and animation-layer changes, selected by the mistake that exposed the player, with Hush and Strung Man the cheapest to build first.
- Colour can be verified inside the container even at 1 fps: add a swatch test card and a pixel-sampling acceptance check (blood hue 350-8, saturation at least 70 %, value at least 30 % with glasses on) before the owner tests on Windows.

## Report

## 1. What makes gore read (research)

- **Physics.** A red surface returns only red light; under blue-heavy light it goes black ([UKy](https://www.pa.uky.edu/sciworks/light/preview/color4aa.htm), [SLH](https://www.sciencelearn.org.nz/resources/2787-light-colour-and-fluorescence)). Blood needs a near-neutral key or a cheat (emission, its own light).
- **Age.** Bright red -> dark brown within hours ([Bremmer 2011](https://pmc.ncbi.nlm.nih.gov/articles/PMC3137592)); gloss sells "wet" more than hue ([Polycount](https://polycount.com/discussion/comment/2217856)). Thin = scarlet, pooled = black-crimson, dry = matte brown.
- **Staging grammar** ([bloodstain patterns](https://www.forensicsciencesimplified.org/blood/principles.html)): round passive drops, drip trails (direction), swipes / wipes / handprints (contact), arterial arcs with run-offs, cast-off lines (a swing; ceilings), voids (something stood there). Each pattern narrates an action, so each can be a clue.
- **Grade.** Red on a pale, plain, complementary field; desaturate the world selectively, never the blood ([Lightworks](https://lwks.com/blog/blood-red-to-morgue-blue-the-role-of-color-in-horror), [No Film School](https://nofilmschool.com/iconic-film-color-grades)).
- **Corpses.** Dead Space: crash and medical reference, "a glimmer of former humanity" ([GameRevolution](https://www.gamerevolution.com/originals/443251-dead-space-creative-director-necromorph-design)); RE7: photogrammetry of make-up and meat ([Kill Screen](https://killscreen.com/capcom-using-photogrammetry-creat)); Mortuary Assistant: randomised haunts ([Bloody Disgusting](https://bloody-disgusting.com/video-games/3726393/the-mortuary-assistant-review-narratively-involving-mechanically-inventive-and-technically-flawed/)); DON'T SCREAM: camcorder grain, dozens of dynamic scares, headless figures, crawling things ([Dread Central](https://www.dreadcentral.com/editorials/493396/dont-scream-unnerves-by-forcing-you-to-stay-quiet/), [Steam](https://store.steampowered.com/app/2497900)), criticised where scares are untied to the place ([DSOGaming](https://www.dsogaming.com/news/dont-scream-is-a-new-unreal-engine-5-powered-horror-game-with-an-interesting-concept/)). My synthesis: a hero body is a tableau: one silhouette, one readable wound, a lit face, a pale or reflective ground, a visible last action.
- **Minutes-old strangulation** = congested cyanosed face, petechiae, a complete horizontal furrow ([AMBOSS](https://www.amboss.com/us/knowledge/forensic-asphyxiology)); lividity shows after ~2 h, fixes at 8-12 h ([StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK554464/)).
- **Monsters.** Almost-human: weightless legs, rigid spine, removed features ([GameBrief](https://www.gamebrief.net/blog/uncanny-valley-horror-games)); the Ring ghost was filmed walking backwards, then reversed ([Den of Geek](https://www.denofgeek.com/movies/ringu-the-ring-best-moment/)). One distortion per creature, a silhouette that reads in backlight, a sound that doubles as a locator.

## 2. Why "no blood" and "all grey" (our build)

| Cause | Where | Effect |
|---|---|---|
| Blood decals are brown water-stain rings and a "dirty handprint" | `tools/gen_decals.py:290-291` (alpha > 0.3 on only 1.2-1.6 % of the image), `:221` (0.12, 0.05, 0.04) | nothing red to tint |
| ...multiplied by dark tints | `flat_builder.gd:1086,1099`, `game.gd:1648` | linear red albedo 0.004-0.04 (fresh blood ~0.25) |
| Pool and tub water are black mirrors | `flat_builder.gd:177` (0.12, 0.006, 0.006), `:741`; reflections off at `interior_env.gd:20`, no SSR | nothing to reflect |
| Every light is blue-green | `flat_builder.gd:371-372,500,855` | linear R/B: COLD 0.48, SICK 0.80, street / moon 0.19-0.24 |
| Global desaturation | `interior_env.gd:47` (0.72) | |
| "cold" fixed at 1.0 | `game.gd:210`, `screen_fx.gdshader:131-133` | warm hues lose 25-70 % saturation, shadows x(0.8, 0.94, 1.08) |
| Glasses 0.8 all night | `game.gd:1027,2070`, `screen_fx.gdshader:119-121` | red x0.8, x0.48, squared: grey 0.5 -> 0.19 (-2.8 stops) |
| Palette | `tools/gen_interior.py:200,348,381,457,526`, `flat_builder.gd:129-171`; one wallpaper for hall, living room, bedroom (`:457,665,811`); `room_surface.gdshader:195` fades it further to grey and has no blood layer | every bright surface <= 7 % saturation |
| Her body | `build_humans.py:605` grey skin, `:747` wine blouse (blood on it, `:761`), `:628` 0.9 mm furrow (1-3 texels), `:75` eyes 55-60 % shut, `:881` clouded; dull cornea `character_rig.gd:274` | no red; an old corpse, not a fresh one |
| Entry | `game.gd:974-978` fade, `:1044` teleport to the bench; body only in the tub (`:1037`) | "black, nothing visible" |

Estimated on screen (numpy model: light -> AgX -> adjustments -> glasses -> cold; diffuse only): drag marks, pool, tub water **#000000-#040101**; handprint **#020404** on wall #121b1c; head-throw splats **#0e131b** (hue 214, blue-grey) on keys #232f3c; his shirt blood (0.9 % of its texels) #070101. A correct albedo (#8A0A0A) would still end at **#070101** (#120506 at four times the light): #560000 in white light -> #3c0000 under our bulb (#1c0001 by the window) -> #2a0000 after saturation -> #070101 after glasses and cold. Existing captures agree: the room tour has 0.000 % red pixels, hues 169-209, saturation 16-23 %.

## 3a. Colour script

Rule: chroma only on the cold side; bone-pale surfaces as blood canvases; **red exists nowhere but blood** (retire the wine blouse, red silk, flowers).

| Zone | Walls / second | Blood canvas | Light |
|---|---|---|---|
| Vestibule | arsenic green #7FA38C / #3F5E4E, woodwork #1E2B26 | bone-and-bottle tiles #D9D4C0 / #24443C | bulb #E6F0DA |
| Corridor | petrol dado #23414A, distemper #A9BDB4, violet runner #4A3550 | white doors #D5DCD2 | sconces #D4E6F0 |
| Music room | bottle damask #2F5148 / #88A898, drapes #1F3D45 | keys #E6E1CC, score #EDE8D5 | lamp #EEF3E6, moon #6F8FD8 |
| Dining | plum flock #4B3A5A / #7B6A8A | cloth #E4E6DF | pendant #E6F0FF |
| Kitchen | eau-de-nil #9CC5AC over #D5DEC2, lino #D8D8CC / #1C1F1E | enamel #EEF2EC | tube #DFF7E2 |
| Bathroom | tile #DCE9E1, band #2E5A4B | all of it | tube #DDF2E4 |
| Bedroom | drowned blue #7F97B5 / #5C708C | linen #DAD9CC | moon, bedside #DCEBFF |
| Workshop | plaster #7C8A80, felt #3E6B4F | paper #E2E2D6 | work lamp #F0F6FF |

Blood: thin #A30F12, pooled #5E0509, tacky #6B0E0C, dried #3D1410, in water #C98C8C.

- **Grade** (replaces `cold`): saturation 1.0; Filmic tonemapper (AgX skews brightly lit blood to orange: #d63d22 where Filmic gives #ce1818); red key `k = smoothstep(.30, .65, (r - max(g,b)) / r)`; world 30 % desaturated, shadows x(0.80, 0.98, 1.02); blood +20 % saturation, gamma 0.85. In the chase the world drains to 65 %.
- **Glasses** as optics, not underexposure: `pow(c, 1.15) * 0.84` (-1 stop), grey-green tint (0.90, 0.97, 0.91) that k bypasses, frame, smudges, glints.
- Modelled result, glasses on: blood **#8d030a** under a room key, **#b90914** under a gore light, against walls #557456, #0f2429, #233c5b.
- **Light.** Every gore set-piece: a neutral key within 1.5 m, placed beyond the blood for grazing highlights; a cull-masked "gore special" on corpse and pool meshes; 5 % emission floor; SSR plus one ReflectionProbe per room.
- **Check.** Swatch test card + pixel sampling of stills: blood hue 350-8, S >= 70 %, V >= 30 %, glasses on.

## 3b. Blood system

- `tools/gen_blood.py`: 1024 px sets (albedo + alpha, normal, ORM, emission): impact spatter x3, arterial arc x2, cast-off x2, drops and trail, swipe, half-cleaned pink wipe, anatomical handprints (press, drag; L/R), bare prints and two shoe treads, wall run, seep under a door, mist.
- `shaders/blood_surface.gdshader` for meshes (ORM decals do not feed SSR, [docs](https://docs.godotengine.org/en/4.4/classes/class_decal.html)): colour by thickness, meniscus normal, roughness 0.08 fresh -> 0.8 dried by `age`, emission floor. Used by pools, the drag ribbon (`MeshUtil.swept_rect`) and the tub (depth absorption, ink clouds, the body visible under the surface). Wall runs: a blood tint on the drip mask `room_surface.gdshader` already has (`:186`).
- Dynamic: drip emitters that spawn drop decals; pools creeping along floorboard gaps; footprints from `player.stepped` / `man.stepped` after wet contact (12 fading steps); red cane-tip dots; his sleeves reddening through the night.
- Where: kill site at the bench (arc up the wallpaper, cast-off on the ceiling, mist on the keys, a void where she sat) -> drag ribbon -> drag prints on door frames -> white bathroom tile; pink mop water in the kitchen.

## 3c. The corpse

| First sight | Pose | Wounds | Light | Do-not-react test |
|---|---|---|---|---|
| **A Threshold** | supine on the vestibule tiles, head to the door (face inverted), hand hooked under the wire | throat cut by the wire, 0.6 m glossy pool, fine spatter on the skirting | bare bulb overhead; landing lamp behind you until he shuts the door | the cane must touch her before you stop (else TELL_AVOID); step over; her arm slips with a thump: turn to it, do not stare |
| **B Audience** | propped in the listening chair, wire ends tied to its back | bib of blood from collar to lap, drips off the fingers | spattered standard lamp at her shoulder; framed by two doorways | "say hello, she is on your left" (she is on the right): bow left; shake the hand he offers |
| **C Interrupted drag** (recommended) | dropped by the ankles, arms trailing toward you, hair along the smear | as A; still dying, eyes follow you, then fix | three corridor light pools: arm, face, wound | his voice and the drag are sounds you must face, so you look: gaze above -10 degrees, silent, no jerk when her hand catches your cuff |

Body upgrades in `build_humans.py`: pale blouse; fresh asphyxia skin (plum above the furrow, pale below); furrow as geometry (3 mm deep) with a 6 mm painted abrasion and runs; the garrote as a mesh (copper-wound bass string, two piano hammers as handles); eyes open, pupils blown, red sclera, wet cornea; mouth 0.5 with the tongue forward; wire cuts across the fingers; wet strands painted over the face; a stump cross-section instead of the sphere cap (`character_rig.gd:771`). Keep today's pallid, clouded set for her apparitions.

## 3d. Monsters (imagined; chosen by the mistake that exposed you)

| | Silhouette; face | Movement | Sound | Build on the rig |
|---|---|---|---|---|
| **Strung Man** (fumbled notes) | wires fan from fingertips to jaw and collarbones; tuning pins for eyes | pose-to-pose snaps on the beat of your last piece | plucked strings, pitch = distance | per-frame `MeshUtil.tube` set between bones; pins on the eye bones; 0.08 s pose blends, idle layers off |
| **Blind Man** (stared) | stooped behind a 2 m cane, ear leading; your glasses healed into his face as two holes, mouth sealed | sweeps the cane (a readable detection arc); head snaps 170 degrees to noise | taps that stop while he listens | lips smoothed and repainted; black inset cups; cane on `wrist.R`; look clamp to 2.9 rad |
| **Hammerhand** (took the wire) | hands below the knees, fingers ending in felt hammers; chest split over strings; jaw drops to a row of keys | fingers never stop; knocks on furniture to find hollow hiding places | wood knocks, soundboard hum | build-time finger scaling x2; ten lathe heads; MultiMesh forearm hammers; slit chest with a frame |
| **Caller** (made a sound) | lumpy head bound in phone cord; receiver fused into an outstretched palm | glides without body bob, arm locked on the last noise | her phone voice; busy tone quickens as he nears | helix mesh hugging the head; reuse the cord tube and `Handset`; arm direction set per frame |
| **Hush** (screamed) | a man-shaped hole; only the blood on his shirt shows | frozen; relocates during flicker-black; once on the ceiling | none: world audio ducked, tinnitus, your microphone is the only sound | unshaded black override; eight frozen poses; bus low-pass |
| **Accompanist** (wife) | hair pinned back, head lolled at the wire's angle, face visible | never walks; only the eyes follow; fingers play | the note of the missing string | pallid textures; eye-only look layer |
| **Blind Woman** (wife) | arms out, head back, clouded eyes | gropes along walls leaving prints; passes if you stay silent | air whistling through the wound | "grope" pose; handprint decals from wrist rays; wound vertex offset |

Avoid the hair-over-face ghost, the faceless suit, the cut smile, the object head. Build Hush and Strung Man first.


## Unknowns / open decisions

- Web pages could not be opened from this session: en.wikipedia.org, lwks.com and www.pcgamer.com failed to resolve and would have to be allowed in the session's network settings. All research therefore rests on search-result summaries plus craft knowledge; no screenshots or video of DON'T SCREAM, Outlast, Visage or MADiSON were examined, and nothing specific was found on corpse design in DON'T SCREAM beyond 'headless figures' and 'crawling things'.
- The on-screen colour estimates come from a diffuse-only numpy model (no specular, SSAO/SSIL, glow or fog) with the AgX, Filmic and ACES curves written from memory of the Godot source. Its absolute brightness is darker than real captures (lit wallpaper measures #5d726e without glasses), so trust the hue and saturation conclusions and the stage-by-stage ratios, not the exact hex values.
- Whether the renderer linearises Decal.modulate was not verified (both cases were computed and both give near-black). That tonemap_white (interior_env.gd:23) has no effect on AgX in 4.7 is inferred from the separate tonemap_agx_white property, which a short headless property probe (no rendering) confirmed exists (16.29, contrast 1.25).
- No new renders were made, per the rules. The only images inspected were older captures already in the session scratchpad; none of them shows the hall handprints, the drag marks, the blood pool or the tub, so their appearance is deduced from code and textures.
- The proposed palette, grade and glasses curve are numerically modelled but unrendered. Switching to Filmic changes contrast everywhere (menu and stairwell included) and needs an A/B on the owner's Windows GPU, as do SSR, reflection probes, decal emission and light cull masks; a cull-masked gore light works only on mesh blood and the corpse, not on decals, which take the lighting of the surface under them.
- The repo's MakeHuman data has only 16 morph targets, one female outfit and two hair meshes. I assumed monster proportions and the neck furrow can be done as numpy vertex edits in build_humans.py (joints are derived from vertex groups), but none of it was prototyped; neck mesh density for a 3 mm furrow, a backward 'drag' walk for the husband and per-finger animation for her are also unproven.
- Export size and VRAM for extra character variants are unknown (the two current characters already carry 38 MB of textures). I assumed the monsters share man.glb and its textures and add only overlays and attached meshes, with at most one or two re-proportioned glb variants.
- Owner decision: how gory to go (wire-cut throat, stump cross-section, the wife still dying on entry) and whether any platform or streaming limits apply.
- Owner decision: which first-sight staging (A Threshold, B Audience, C Interrupted drag; I recommend C) and whether the wife may be alive for the first minute.
- Owner decision: whether blood-tinted light from a spattered lampshade, or any yellow-green practical, breaks the earlier 'no warm colours' wish (the proposed palette stays on the cold side and reserves red for blood).
- Owner decision: how dark the glasses may be (about -1 stop proposed instead of -2.8) and whether 'looking over the rims' should exist as a risky mechanic.
- Owner decision: changing her established look (pale blouse instead of wine, hair pinned back to avoid the long-hair ghost cliche), and how many monsters to build now (two suggested) and whether the monster should depend on how the player was exposed.
