# 02_jumpscare_craft

## Key points

- Measured on the shipped files: the one stinger (reused at 7 call sites) has 94% of its energy below 80 Hz and a 274 ms attack, so A-weighted it is only 8 dB above the rain bed, about as loud as a single piano note and 5 dB quieter than the husband's talking voice — a soft boom, not a startle.
- Measured in code: the biggest scare moves the camera 0.02° (0.3 px at 1080p; player.gd:139,271), FOV never changes, and post adds only ±4.5 px jitter, 5% zoom and a 20% red tint — the proposed spec (FOV 70→58°, ±2.2° shake, flash frames) is roughly 100 times that.
- Computed from the shaders: saturation 0.72 + sunglasses 0.8 + cold 1.0 (interior_env.gd:47, screen_fx.gdshader:116-135) turn lit blood into RGB(16,7,8) and a lit face into RGB(38,40,43), and the bathroom mirror reflects nothing (interior_env.gd:20, flat_builder.gd:769), so the knife-in-the-mirror scare cannot be seen at all.
- A scare that lands is 10–60 s of dread, 0.8–2.5 s of silence with nothing audible in the last 0.5 s, an image complete in one frame with a ≤5 ms-attack stinger in the same frame, a 0.5–0.9 s hold with the subject rushing the lens, an aftermath, then 30–45 s of relief; today the face eases in over 0.16 s and sits there for 5 s (game.gd:1325-1341).
- Loudness is contrast: majors need about +14 dB over voice and piano and +28 dB over the bed, which requires lowering every other bus about 10 dB (all assets are peak-normalised), a dry limited Scare bus, bed ducking, and a 'raise the volume until you hear the whisper' step in calibration.
- Stinger energy must sit at 1–5 kHz with 40–110 Hz roughness and a sub layer no more than 0.3× the mid layer — a numpy prototype of that recipe is 11 dB(A) louder than today's stinger at the same peak — with at least 10 variants and about 40% diegetic stingers so the player cannot habituate.
- Every scare must be a declared test — V (seen only: any reaction is a tell), A (really audible: he must turn to it, a flinch is forgiven, reacting before the sound is the tell), HA (imagined sound: he must not turn) — with the husband's own head-turn as the player's reality check.
- The microphone is judged only while a visual test is open (night_state.gd:115-125), which is why screaming into his face did nothing; it has to be judged continuously within his earshot, weighted by the class of the last scare.
- Scare shake must be kept out of the flinch detector: `ang_speed` is read from the camera basis (player.gd:273-277) and a ±2.2° shake at 25 Hz peaks at 6 rad/s against a 4 rad/s flinch threshold, so our own effect would expose the player.
- The Scare Director guarantees the lit corpse within 20 s of the door opening, a first minor within 90 s and a first major within 240 s, then 5–7 minors and 2–3 majors per 10 minutes (about 28 minors, 9–11 majors and 4 set pieces in a 45-minute run, against about three stingered moments now), with no repeated major, 20–25% fake-outs and a per-run seed.
- Visibility must be designed in: every major rides a light event (lightning, bulb surge, camera flash, lights-out-then-on), gets its own layer-masked key light, fills 55–80% of screen height, opens the grade for 0.8 s, and — when hallucinated — spawns on the player's gaze ray during a blackout frame.
- Pre-warm every scare actor, material, overlay and audio stream behind the loading fade (Godot's pipeline precompilation skips material overrides and canvas shaders, and `_sfx()` loads streams at call time, game.gd:235-264), and cap flashes at 3 per second by default with an opt-in for more.

## Report

## 1. Sound recipes (numpy/scipy, into tools/gen_sfx.py)
**Mix law.** Sub layer ≤0.3× the mid layer (a loud sub eats the headroom — today's fault); sum → `tanh(1.6x)` → 15% wet through IR = noise·e^(−6.91t/1.8), LP 3.5 kHz. Three seeds per recipe, `pitch_scale` 0.94–1.06; 40% of scares use diegetic stingers (piano crash, bell, shutter, bang).
- **S1 Slam**: sine 38+82·e^(−t/0.06) Hz, τ 0.45 s, `tanh(3x)`; thuds 110/180/260/410/640 Hz; LP-2.5 kHz noise τ 0.07 s; 3 ms HP-3 kHz click.
- **S2 Shriek**: 8 sines at f0×{1, 1.47, 2.09, 2.56, 3.14, 3.93, 4.71, 5.4}, f0 900–1400 Hz, vibrato 5–9 Hz, +3–8% glide; 8 saws in a quarter-tone cluster (MIDI 84–91), band-passed 1.5–6 kHz; noise 2–7 kHz; all × AM 40–110 Hz, depth 0.6 (the roughness band of screams); attack 3 ms, τ 0.5 s.
- **S3 Scream**: saw f0 600→1400 Hz in 60 ms, 2% jitter, falling 400 Hz at the end; f0/2 subharmonic and noise at ×0.35; `iirpeak` formants 1050/1750/3000/4100 Hz; AM 50–90 Hz; 0.8–1.3 s. Her voice: this source through the LPC envelope of an espeak "aaa" (gen_voice.py:57-95).
- **S4 Braam**: saws 55/58.3/61.7/110.4/116.9 Hz, LP sweeping 2500→300 Hz, tanh, τ 1.2 s.
- **S5 Reverse suck**: decaying 0.8–8 kHz noise, reversed; ends ≥0.6 s before the hit or runs straight into it.
- **S6 Snap**: 1 ms click + HP-4 kHz noise τ 10 ms + 0.5 s of S2.
- **S7 Bang**: click + modes 180/310/470/740 Hz (τ 60–120 ms) + rattle (noise 2–5 kHz gated at 40 Hz).
- **S8 Ear**: breath noise 1.5–6 kHz; near ear bass-boosted; far ear 26 samples late, LP 2.5 kHz, −12 dB.
- **Beds**: D1 sub drone 41/43.6/61.7 Hz with tanh harmonics; D2 Shepard riser (7 octave-spaced sines, +1 octave per 30 s); D3 bowed quarter-tone cluster, 9–16 s swells.
- **Gore**: G1 squelch = 20–60 grains of 5–25 ms (noise through `iirpeak` 400–1800 Hz + 90→60 Hz blub + click); G2 thick drip = 600→450 Hz chirp, τ 25 ms; G3 bone = 2–4 cracks 8–30 ms apart (click + 1.2–3.5 kHz ring + 140 Hz thud); G4 wet thud = `stab` + G1.
- **Dying gasp**: 0.5 s crescendo inhale (noise through 600/1400/2600 Hz) → 1.4 s rattle (pulse train 45→18 Hz, 15% jitter, same formants) → exhale.

## A. Scare catalogue
K: R real, H hallucination. Trg: SC scripted, LK look, LA look-away-and-back, PX proximity, DR door, MR mirror/window, BH behind-you, PF peripheral, FO fake-out, 2H second hit. T: tier in §C (d = dread only). dg = diegetic.

**Tests.** **V** (seen only) — tells: a view jerk, gaze within 9° past the fixate time, a stop or back-step within 0.8 s, any voice, 2 piano errors in 3 s, obeying a bait prompt. **A** (really audible) — turn to within 40° in 2.4 s (night_state.gd:187); flinch and gasp forgiven; reacting *before* the sound is the tell. **HA** (imagined sound) — turning >25° is the tell. Reality check: his head turns to real sounds within 0.4 s; imagined sound is dry and identical in both ears.

|#|Scare|K|Trg|Staging|Snd|T|Test|C|I|
|-|-|-|-|-|-|-|-|-|-|
|1|Threshold tableau|R|SC|Door opens on a LIT hall: she sits slumped facing you, wire in her neck; he watches your face. Then her arm drops.|D1; G4 dg|d→m|V: don't freeze. A: turn to the thud|M|4|
|2|She turned|H|LA×3|Each pass: head turned to you; eyes open; gone, a drag trail.|S6|m|V|S|3|
|3|Cane caught|H|PX|Her hand clamps your cane tip; her head snaps up.|S1+S2|M|V: no look down|M|4|
|4|Face at the ear|R|SC|(game.gd:1315) At the frame edge, 25 cm, key-lit, eyes on your lenses; 0.8 s.|S8 dg, S2|M|A to his breath; no eye contact|S|4|
|5|Head on the keys|R|SC|(game.gd:1565) Crash; blood spatters the score and your lens.|S4 dg+S1|M|A: stop, turn, resume when told|S|5|
|6|Four hands|H|LK|Her wire-cut hands play beside yours; look and they slam.|S4|m→M|V: keep the beat|M|3|
|7|String whip|R|SC|A bass string snaps across the view. Teaches A.|S6 dg|m|A|S|2|
|8|Lid slam|R|SC|He drops the fallboard at your fingers; bait "[S] pull back".|S7 dg|M|V until the bang|M|3|
|9|Guess who|H|LA×3|Figure in the lacquer reflection, nearer each glance; then fingers cover your eyes: notes hidden 2 s.|S8, S1|M|V: play blind|M|4|
|10|Mirror, knife|R|MR|(game.gd:1462; needs a real mirror) Dark 0.4 s; he is at your shoulder, blade up. Bait "RUN".|S1+S2|M|V: no turn 2.6 s|M|5|
|11|Camera flash|R+H|SC×3|He photographs you; each flash floods the room and shows her nearer behind him.|shutter dg; S2|m,m,M|V: no blink, no flinch|S|4|
|12|Lightning figure|H|MR|On lightning (game.gd:2043) someone is pressed to the window; thunder follows 0.8–3 s later.|thunder dg|m|V at the flash, A at the thunder|S|3|
|13|Uncovered mirror|H|LA×3|Cloth slides off the hall mirror (flat_builder.gd:676); a man in it halves his distance each look; a palm bangs the glass.|S7+S2|M|mic|M|4|
|14|Cabinet fall-out|H|DR, FO|Two empty cabinets with a riser; from the third she topples into the camera 0.4–1.2 s after opening.|S5; S1+S3+G1|M|V, mic|M|5|
|15|Keyhole eye|R|DR|"Listen at the door": something red through the keyhole; an eye fills it (reuse eye.gdshader).|G1; S1+S2|M|V: hold still 1.5 s|M|4|
|16|Tub curtain|H|PF, FO|The curtain bulges, a hand on the rim; behind it only rocking water.|G2|d|mic|S|3|
|17|Second footsteps|H|BH|Steps behind you, one extra when you stop. Third turn: her face at 30 cm.|S2+S3|m→M|HA: don't turn|M|5|
|18|Whisper|H|BH|"别回头" at one ear while he faces you (assets exist).|S8|m|HA|S|2|
|19|Landline|R/H|SC|The bell bursts out of silence. Real: he turns, "answer it". Imagined: he doesn't move.|phone_ring dg|m|A or HA|S|3|
|20|Tape scream|R|choice|Playing back the recorder blasts her scream; he hears it.|S3 dg|M|hide it in 5 s|S|4|
|21|Corridor crosser|H|PF|A pale figure crosses between far doors: 0.4 s, 7 m, lamp-lit.|thump|m|V: don't stop|S|2|
|22|Peeker|H|PF, PX|A head leans from a door frame at knee or ceiling height, withdraws when looked at; third pass: a hand shoots out.|S6; S1+S2|m→M|V|M|4|
|23|Bulb countdown|H|lights-out|Each 0.3 s dark gap she is nearer (8, 5, 2.5 m); dark 1.2 s; her screaming face fills the frame.|S1+S2+S3|M|V; he is behind you|M|5|
|24|Glasses off|R|SC|He lifts them: 2–3× brighter, full colour, the wall red. A lighter passes before your eyes, then flicks at them.|S2|d→M|V: don't track|S|5|
|25|All doors open|H|LA|Turn back: every corridor door stands open; one step and they slam toward you, 120 ms apart.|S7×4|M|mic|M|4|
|26|Under the sheet|R→H|PX, LA|The cane tap turns wet on a sheeted shape: probe, step over. Later it has sat up.|G1; S6|m|avoiding = TELL_AVOID|S|3|
|27|False tell|H|UI|Meter slams to 95%, "他听见了", glitch: nothing happened; fake "RUN" prompt (game_ui.gd:176). Twice a run at most.|S2|M|obeying = tell|S|3|
|28|Behind the eyelids|H|eyes shut >4 s|A face surfaces in the black and lunges.|S1+S3|M|mic|S|4|
|29|False death|H|SC, once|A full kill cam, black — and you are still at the piano; he asks why you stopped.|as lethal|L|resume in 3 s|S|5|
|30|Monster turn|R→H|exposure|Lights die 0.8 s; he stands head tilted 90°, arms too long, sockets black; 0.6 s stare; scream; sprint.|S3 −5 st, S4|L|chase|L|5|
|31|Eye at the slats|R|hide, 2H|His eye at the wardrobe gap 2–4 s (mic threshold −6 dB); he leaves; 40%: the door is ripped open 1.5 s later.|S1|M|silence|M|5|
|32|Kill cams ×4|R|caught|Wire from behind, knife, dragged out by the ankle, head to the keys; ≤2 s, cut to black.|S1–S4, gasp|L|—|M|5|

## B. Scare Director rules (new scripts/scare_director.gd; replaces `_piano_tests`, game.gd:1264)
**State.** Phase BUILD/PEAK/RELAX; stage 0–4; mode WATCHED/ALONE/CHASE; arousal A = 20 s mean of (mic − baseline)/12 dB ×0.5 + mouse jitter ×0.3 + piano errors ×0.2; panic H (0 until the corpse, +0.15 per major, stage floors 0/.2/.4/.6/.8); used ids; last two trigger classes; at most one major and two minors armed.

**Inputs.** Zone, position, speed, gaze and per-anchor dwell, `state.watched`, his distance and sight line, `eyes_closed`, piano state, mic level.

**Tick (2 Hz).**
1. RELAX (30–45 s after a major): nothing arms.
2. Due: a minor every U(45,90) s, a major every U(180,300) s (150–240 in stages 3–4), divided by `scare_rate` (declared in difficulty.gd, never read today); 25% sooner if A <0.2 for 3 min, 20% later after two exposures on one beat.
3. Candidates: stage and mode fit, id unused, H ≥ its minimum, class not in the last two, spawn point outside the frustum (sight-ray checked).
4. Score = weight × fit (distance, gaze) × 2 if an earlier link of its chain was seen (2, 9, 11, 13, 17, 22) × U(0.7,1.3). Arm the best: place actors, start its fear emitter (a 3D bed that swells with proximity).
5. Fire on its predicate + U(0.2,1.2) s. Unfired after 75 s: disarm silently — a fake-out.
6. On fire: tier presentation; `state.visual()`, `state.sound()` or a new phantom test; PEAK 5–8 s; RELAX.

**Predicates.** LK: within 20° of gaze for 0.15–0.3 s at 1.5–8 m. LA: seen ≥0.3 s, then >60° away for ≥1 s. PF: spawn 30–48° off-gaze, vanish under 15°. PX: <1.2 m. BH: no turn >90° for 6 s, audio leads 1.5–4 s, reveal on a turn >120°. DR: door >35° open.

**Guarantees.** Corpse lit and in view ≤20 s after her door opens. First minor ≤90 s, first major ≤240 s (forced from 5/14/23). Per 10 min: 5–7 minors, 2 majors (3 late); a 45-min run ≈28 minors, 9–11 majors, 4 set pieces (1, 10, 24, 30). No major repeats; a minor may return once, ≥10 min later, as another variant. ≥90 s between majors; none within 8 s of a hint; 20–25% of cues are fake-outs; one unwarned major per stage; idling >25 s brings the husband to check; a per-run seed shuffles pool and anchors.

## C. Presentation spec (60 fps; new `ScareFX`)
| |Minor|Major|Lethal|
|-|-|-|-|
|Lead-in|bed −6 dB, 0.3–0.8 s|10–60 s dread; bed to silence over 1 s, hold 0.8–2.5 s; nothing audible in the last 0.5 s (a sound 30–500 ms before the hit inhibits startle)|none, or a 0.6 s freeze|
|Trigger → image, sound|≤2 frames, same frame|≤1 frame (visibility toggle, never a fade), same frame, never >40 ms late|hard cut|
|Stinger over bed / over voice|+22 / +8 dB|+28 / +14 dB|+30 / +16 dB|
|Momentary level; attack|−15 LUFS; ≤10 ms|−9 LUFS; ≤5 ms|−7 LUFS; ≤3 ms; peak −1 dBFS|
|Layers|S6|S1+S2 (+S3)|S1+S2+S3+S4|
|Subject height; luminance|8–20%; ≥0.25|55–80%; ≥0.45 on ≤0.08|fills frame; ≥0.55|
|Flash|—|2 frames (0.85,0.95,1.0) α 0.6, then red (0.6,0,0) α 0.35 fading 0.4 s|2 frames white α 0.9, 3 black, image|
|FOV (base 70°)|→67° in 0.08 s|→58° in 0.10 s, hold 0.25 s, back in 0.9 s|→48°|
|Shake (trauma², 22–28 Hz)|±0.6°|±2.2°, roll 3°, 0.5 s|±4°, roll 7°|
|Aberration (base 0.0012); vignette (0.55)|0.003; 0.6|0.012; 0.9|0.02; 1.0|
|Grade|—|desaturate 0.5 in the silence; on the hit, for 0.8 s: sunglasses 0.8→0.25, cold 1→0.3, saturation 0.72→1.1 (blood RGB(16,7,8)→(67,10,12))|same|
|Hold; approach|0.25–0.6 s|0.5–0.9 s (longer and the mesh gets inspected); 6–10 m/s to 0.4 m, eyes on the lens|1.2–2 s; 12 m/s|
|Aftermath|+20 bpm for 6 s|6.2 kHz ring −18 dB 3–5 s; world LP 800 Hz, 4 s; 140 bpm; second hit at +1.8–3.5 s for ≤1 in 4|black 1.5 s|
|Test window; cooldown|2.5 s; 20–40 s|4 s; 90–150 s|—|

**Build notes.** A dry "Scare" bus with a hard limiter; every other bus down 10 dB (assets are peak-normalised, gen_sfx.py:23) and a "raise the volume until you hear the whisper" step in calibration. A layer-masked key light on the actor, room lights −70% during the hold; every major rides a light event (lightning, bulb surge, flash). Free look always — the reaction must be the player's own; hallucinated majors spawn on the gaze ray during a blackout frame so they cannot be missed. Shake goes on a node that `ang_speed` (player.gd:273) does not read. At most 3 flashes per second unless the player opts in.

**Ship check per scare.** Seen (lit, big, on the gaze), heard (1–5 kHz, ducked bed), sudden (one frame), short, rare, and consequential (it opens a test).

Sources: [scream roughness](https://pmc.ncbi.nlm.nih.gov/articles/PMC4562283), [prepulse inhibition](https://www.wikiwand.com/en/Prepulse_inhibition), [darkness and startle](https://ajp.psychiatryonline.org/doi/10.1176/ajp.155.6.812), [L4D director](https://developer.valvesoftware.com/wiki/L4D2_Director_Scripts), [Alien: Isolation](https://www.gamedeveloper.com/design/the-perfect-organism-the-ai-of-alien-isolation), [P.T.](https://www.gamesradar.com/a-pt-camera-hack-reveals-lisa-is-always-behind-you-and-its-absolutely-terrifying), [Layers of Fear](https://gamedeveloper.com/audio/terrifying-players-with-unstable-level-design-in-i-layers-of-fear-i-), [Dead Space](https://gameinformer.com/b/features/archive/2009/12/11/feature-noises-in-the-dark-exploring-the-sounds-of-dead-space.aspx), [DON'T SCREAM 1.0](https://80.lv/articles/jumpscares-can-now-kill-you-in-this-photorealistic-indie-horror), [Godot pipeline stutter](https://docs.godotengine.org/en/4.4/tutorials/performance/pipeline_compilations.html).

## Unknowns / open decisions

- WebFetch failed for every host tried (cdn.fastly.steamstatic.com, www.readkong.com, en.wikipedia.org, www.gamedeveloper.com — these would have to be allowed in the session's network settings), so outside facts rest on WebSearch summaries; I could not read Booth's Left 4 Dead slides, the Alien: Isolation write-up or developer interviews in full.
- Confirmed by search: scream roughness at 30–150 Hz, prepulse inhibition at 30–500 ms (strongest near 120 ms), faster-rising and broadband sounds startling more, darkness and threat enlarging startle, L4D's build-up/peak/relax loop, Alien: Isolation's menace gauge, P.T.'s ghost fixed behind the camera, Layers of Fear changing rooms only while unobserved, Dead Space's fear emitters, DON'T SCREAM's calibration, move-to-advance clock and 1.0 'Scare Director' (its rules are unpublished), and Godot's pipeline-compilation limits (4.4 docs; the project is on 4.7.2).
- From memory, medium confidence: L4D's 30–45 s relax and 3–5 s peak (the Valve wiki search only returned an example script with other values), the roughly 80–90 dB and ≤10 ms rise needed for a true startle reflex, the 3-flashes-per-second photosensitivity limit, and AudioEffectHardLimiter being available in this Godot version.
- All audio figures are numpy measurements of the shipped .ogg files and of a scratch prototype (A-weighted RMS over 400 ms, 10–90% attack, K-weighted momentary estimate, mono); nothing was listened to, only S1–S4 were measured, the other recipes were only run for sanity, and results on the owner's speakers or headphones are untested.
- The colour figures come from porting the shader math to numpy and assume the listed pixel values enter the grade as written; no frame was rendered, because captures were ruled out for this task.
- Every presentation number (FOV, shake, flash, hold, loudness offsets, director intervals) is a starting value from craft practice, to be tuned by the owner on Windows; at normal home volume a +14 dB stinger may still sit below the physiological startle threshold, so the design leans on contrast, onset speed and surprise.
- Assumed: 60 fps on the owner's machine; I do not know whether the owner and his friend play on headphones or laptop speakers, which lose nearly everything below about 150 Hz.
- Assumed about the larger map and story: at least one corridor of 8 m or more with three doors, two real mirrors (SubViewport planar reflections, GPU cost unmeasured), cabinets, a keyhole door, anchors exported by the builder, and at least three stretches where the husband is out of sight.
- Build costs are estimates; the uncertain ones are new MakeHuman-derived pieces (a hands-only mesh, the monster face and proportions) and the four kill cams.
- Making 'Head on the keys' a stop-and-turn test and forgiving flinches at truly audible events reverses today's tell logic (game.gd:223, night_state.gd:73-80) and has to be agreed with the suspicion redesign.
- Owner decision: how explicit the gore may be (wire in the neck, severed head, blood on the lens), and whether the 'false death' and fourth-wall tricks (fake meter spike, fake prompts) are welcome or would read as bugs.
- Owner decision: whether a detected startle exposes him at once or adds suspicion by difficulty, and whether real (non-imagined) events may also carry an 'in-head' stinger the husband cannot hear.
- Owner decision: default stinger loudness and flashing (a toggle is proposed either way), and whether the dark-glasses dimming may be lightened or opened during scares — it is the main reason nothing can be seen.
