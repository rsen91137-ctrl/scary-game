# 04_suspicion_mic_audit

## Key points

- The owner's test did nothing mainly by design: voice and gaze are judged only inside eight scripted 3–6 s windows (15–29 s of a five-minute night), and "he is watching" only slows decay.
- Staring at his face scores nothing at the door or in the knife test, because the stare rule needs the view to start 16° away from a frozen snapshot point, and it pays only once (+10 to +36).
- The mic detector is edge-triggered and can latch: a scream that starts before a window opens, or steady noise above the threshold, is silently ignored (both reproduced in a Python port of the logic).
- The microphone can be dead or off without the player knowing: no device picker, calibration reports "done" after 7 s unheard, gated or blocked mics dead-end into "play without mic" (which holds keyboard focus), and play shows no mic indicator.
- Not at fault: microphone input is enabled in the project, capture on a muted bus works (measured headless on Godot 4.7.2), and a scream can reach the Normal threshold.
- Several listed tells can never fire (tracking, blood avoidance, stare at the knife), some are judged when he cannot see you, and holding SPACE disables every visual tell.
- Replace test windows with an always-on perception model: sight V and hearing H computed every frame from line of sight, his head cone, light, distance, attention, doors and masking noise.
- Voice must count whenever he can hear it, level-triggered on three calibrated lines: gasp +10, voice +30, scream = exposed on Normal.
- Teach one rule, "sound licenses looking": eye lock, tracking a silent mover and dwelling on corpse, blood or knife raise suspicion only while he can see you, so looking when he is not looking stays free and the gore stays visible.
- Every scare, real or hallucinated, becomes a composure check judged on voice, view jerk, movement change and piano errors, while reducers (cane, wall, neutral gaze, ear turn, soft bump) give the player active ways to act blind.
- Stages at 30, 60 and 100 with ratcheting floors end in a locked door and an immediate chase, and difficulty scales gain, grace times, hearing range and voice penalties.
- Make it provable: injected mic levels and bot camera motion for headless assertions (test 1 is the owner's case), an evidence-gated calibration with device picker and failure diagnosis, and a permanent in-game mic strip.

## Report

## 1. Why the scream and the stare did nothing

**A scream counts only if all of these hold**
1. The mic is enabled and "Begin" was pressed after calibration; "Play without mic" sets `mic_this_run=false` (`pregame.gd:200`, `night_state.gd:116`).
2. Windows' *default* recording device is the right one: no UI sets `mic_device` (`settings.gd:135-139`).
3. The level exceeds `noise + 0.55·(gasp − noise)` for 0.12 s (`mic_monitor.gd:24-33`).
4. It is a *rising edge*: one event per sound (`mic_monitor.gd:66-69`).
5. A "visual" test is open at that instant (`night_state.gd:118-119`). Tests open at eight scripted lines only (`game.gd:955, 1287, 1339, 1365, 1411, 1486, 1653, 1717`), 3–6 s each: 15–29 s of a five-minute night.

Even then, Normal exposes outright (`night_state.gd:124`): voice never raises the meter.

**A stare counts only if** a visual test is open, the view began more than 16° off the target, and it then rests within 9° of a *frozen* point for 1.0 s (`night_state.gd:166-171`). It pays once: +10 to +36.

**Causes, most likely first**
- **A. Design gap (certain).** Outside those windows nothing is judged: `_process` only walks open tests (`night_state.gd:139-152`). `watched`, the only notion that he sees you, merely slows decay (`night_state.gd:138`).
- **B. Staring at his face scores nothing at the door (by construction).** The game aims your view at him itself just before the test opens (`game.gd:947`), so the 16° condition is not met. The knife is placed dead ahead (`game.gd:1287`): never met.
- **C. Edge bug (reproduced in a Python port).** A scream that starts before a window opens is ignored for its whole length. The head (0.45 s of flight first, `game.gd:1629-1653`) and the mirror charge (1 s of build-up, `game.gd:1472-1486`) invite exactly that.
- **D. Latch bug (reproduced).** The noise baseline adapts only below threshold (`mic_monitor.gd:72-79`). Steady noise above it (speakers, fan, auto-gain) holds `active` forever and nothing registers again.
- **E. False "calibration done".** After 7 s it saves and shows 校准完成 even if no gasp was heard (`pregame_ui.gd:247-253`), for example on the wrong device.
- **F. Calibration dead end.** Exact zeros for 2.5 s mean "no microphone" (`mic_monitor.gd:36-37`, `pregame_ui.gd:236-239`); a noise-gated headset or a Windows privacy block does that during "stay quiet". The way out, "play without mic", also holds keyboard focus (`pregame_ui.gd:224`): Space or Enter turns the mic off silently.
- **G. No feedback.** In play there is no mic level and no "mic off" badge; the only trace is an 8-second graph on the death screen (`game_ui.gd:336-349`).
- **H. Unverified Windows risks.** Surround output may make the capture read low; mic and output sample rates differing, or a Bluetooth headset dropping to hands-free; smoothing by frame time although audio arrives in 512-frame blocks slows the detector at high frame rates (`mic_monitor.gd:57`).

**Not at fault (checked headless on Godot 4.7.2):** `enable_input` is on; a capture effect on a muted bus does receive the signal (measured); on Normal a scream reaches the threshold. On Easy a loud calibration can put the threshold above full scale (Easy is locked today).

## 2. Existing tells (Normal)

| Tell | Rule | Effect |
|---|---|---|
| Flinch | view faster than 4 rad/s within 0.9 s, target within 60° | +32·w, once |
| Stare | the rule in section 1 | +26·w, once |
| Track | closing on the frozen point at over 0.6 rad/s for 0.8 s inside 25° | +24·w; unreachable in one approach (25° lasts 0.73 s) |
| Voice | edge inside a visual window | exposed (Easy +55) |
| Fumble | piano error within window + 1 s | +9, 11, 13, 15 |
| Slip / Stopped | other piano errors / three misses running / refusing the wire | ≤ +1.5 (cap 45 %) / +14 / +8 |
| No reaction | glass only: no 20° turn toward it within 2.4 s | +18 |
| Avoid | pass the blood without stepping in or tapping it | +22; unreachable (hall 1.3 m, zone 1.1 m) |
| Ran, Bait, Greed | move 0.6 m during the charge; press E on the fake prompt; take the money | exposed |

Weights w: door 0.4, knife 1.0, face 1.2, money 0.5, tub 0.6, charge 1.4, head 1.3, door charge 1.2. Decay 1.0/s, 0.4/s while watched. The tub is judged with him in another room; the mirror charge against his real position behind you. Never read: `scare_rate, scare_intensity, clue_glow, decoys, warn_watched`.

**Not detected at all:** voice outside windows; facing his face; following him, the knife or the thrown head; dwelling on corpse, blood, knife, photo, mirror; walking straight to things, never touching a wall, using objects never felt (E even requires looking straight at them, `player.gd:289`); stepping back or freezing at silent events; reacting to the lightning flash before its thunder; ignoring any sound but the glass; your footsteps in the chase (`game.gd:1808`). Holding SPACE switches every visual tell off (`night_state.gd:156`); pausing hides a scream.

## 3. Redesign

**The rule the player learns: sound licenses looking. Turn to what a blind man could hear; never follow what is silent.**

**Perception, every physics frame (new `senses.gd`)**
- **V, he sees you (0–1)** = line of sight × his *head* cone (≤35° 1.0, ≤75° 0.5, ≤110° 0.2) × light on your face (from `flat.lamps`, 0.3–1) × range (full to 3 m, 0.3 at 6 m) × attention (testing 1.0, watching 0.8, idle 0.5, busy 0.15). Gaze tells ×0.4 when he is behind you.
- **H, he hears you (0–1)** = (1 − distance / hearing range) × (same room 1, open door 0.7, closed door 0.35, two walls 0.1) × masking (your piano 0.8, his noisy task 0.6).
- The director registers things instead of opening windows: `add_poi(node, weight)`, `sound_event(pos, loudness)`, `composure_check(id, kind, intensity)`; the nine `visual`/`sound` calls in `game.gd` migrate to these. He is "audible" while stepping or talking, "silent" when still or creeping.

**Suspicion 0–100: each channel × V or H × difficulty gain**

| Channel | Starting numbers (Normal) |
|---|---|
| Voice, level-triggered, whenever H > 0 | Gasp ≥0.10 s: +10 (×2 in a composure window; free within 1.5 s of an audible scare). Voice ≥0.25 s: +30, then +15/s. Scream ≥0.30 s: exposed if H ≥ 0.1; fainter, he comes to look |
| Eye lock | face within 6° of his while he is silent, after 0.6 s grace: +9/s (≤4 m), +16/s (≤1.2 m). Sweeping past, or facing him while he speaks, is free |
| Tracking | keeping a silent mover within 12° for 1 s: +12/s (+24/s if he creeps). An audible mover may be followed loosely |
| Dwell | within 6° of a registered thing after 0.5 s grace: +8·w/s. Corpse, head, knife 1.5; blood 1.0; mirror, money 0.7; photo, clock 0.5. Free when V = 0 |
| Composure, 0.15–1.5 s after a scare | view from under 40°/s to over 180°/s: +25 (over 400°/s: +40). Starting, stopping or reversing movement: +20. Piano error +9…15. Voice ×2. Clean pass −8. A total of 60 = exposed |
| Sound obligations | loud event while watched: turn 15° toward it within 2 s, else +12. Reacting to the silent flash: +18. At most one per 20 s |
| Navigation | brisk walk (new: Shift, 1.9 m/s, no cane) while seen: +10/s. Using an object never touched by cane or hand: +12. Passing a placed obstacle untouched: +15 |

**Reducers, only while seen, capped at −3/s:** cane tap −0.5; hand on wall (walking within 0.45 m of one) −1/s; neutral gaze (nothing registered within 15°, slower than 20°/s) −0.5/s; ear turned to a sound (source 25–70° off centre, held 1 s) −5; holding E to feel an object for 0.8 s −3; deliberate soft bump −8 (45 s cooldown; a fourth reads as overacting, +5). Base decay 1.0/s seen, 0.3/s unseen.

**Stages (floors ratchet):** at ease below 30; curious at 30 (he follows you, asks trick questions; floor 15); testing at 60 (silent tests, stays within 2.5 m, decay halves; floor 40); convinced at 100 or on an instant exposure (scream in earshot, taking silent bait, fleeing a silent threat, seen holding evidence). Then he locks the door and the chase starts within 2 s.

**Scares** are `composure_check` calls. Visual ones and hallucinations demand no reaction (he cannot see a hallucination, so any reaction is a reaction to nothing); audible ones demand a turn and allow a gasp. With him absent, only voice counts.

**Difficulty (Easy / Normal / Hard / Nightmare):** gain 0.6/1/1.3/1.6; decay 1.6/1/0.7/0.4; gaze grace 1.0/0.6/0.4/0.25 s; jerk threshold 260/180/140/110°/s; gasp +0/10/20/35; voice +15/30/50/exposed; scream +50/exposed/exposed/exposed; hearing 6/9/12/15 m; idle attention 0.4/0.55/0.7/0.85.

**UI:** a permanent mic strip (live level, three lines, "he can hear / cannot / mic off"); the meter's eyelid shows his attention; a ring fills at screen centre during each grace period, before points are charged; every change prints cause and amount, red for tells, green for reducers. At the door, a lesson with the meter capped at 40 %: face him and it rises, turn your ear and it drains, make a sound and it jumps.

## 4. Headless tests and proof that the microphone is heard

- `MicMonitor` takes its level from a source: the device, or an injected envelope (`inject(db, secs)`, `--mic-script=`). `Player` gains `bot_look_at`, `bot_track`, `bot_jerk`, `bot_walk_to`. Run with `--fixed-fps 60` and a seed; `--trace` writes per-frame suspicion, V, H, channel amounts and mic level for tuning.
- One code-built room, PASS/FAIL per case, non-zero exit on failure:
  1. Scream at 1 m facing him, no scripted event: exposed within 0.5 s (the owner's case).
  2. Same scream through two walls: suspicion unchanged, he comes to look.
  3. Stare 3 s at 1.5 m, lit: at least +20; dark: at most +8; his back turned: 0.
  4. Steady noise 3 dB over the gasp line for 10 s: the detector releases, and a scream on top still registers.
  5. Whole-night bots: "careful" never passes 60; "sighted" is exposed during piece 1; "screamer" at the first scare.

**Calibration: every step gated by evidence, never by a timer**
1. Show the device name with a switcher; the sketch eye's pupil follows the live level.
2. "Say anything" needs +15 dB over the floor for 0.3 s, then shows 听见你了. Otherwise name the cause: could not open (Windows privacy), exact zeros (muted or blocked), flat signal (wrong device).
3. Two seconds of quiet set the floor. A gasp sets the gasp line at 55 % of the way from floor to gasp; voice line = gasp + 6 dB; scream line = gasp + 14 dB or an optional real scream. All lines are clamped below −6 dBFS.
4. Play the loudest stinger; if the mic hears it, ask for headphones.
5. A sandbox where the lines light as the player tries. "Play without mic" needs a confirmation and never has default focus; such runs are labelled on the HUD and the ending, and weigh the other composure signals 30 % higher.

Capture through `AudioServer.set_input_device_active()` and `get_input_frames()` (present in 4.7.2, returns an error code), with a floor that always adapts.

File references are under `/home/user/scary-game/blindact/scripts/`.

## Unknowns / open decisions

- Which of causes C–H actually hit the owner cannot be read from code. A and B are certain, but I do not know when he screamed, whether he pressed Begin or Play without mic, which Windows default recording device was active, or whether he used speakers. A two-minute check on his PC (does the calibration bar move when he speaks; what the death-screen graph shows) would settle it.
- Not verified, for lack of Windows audio hardware and engine source here: the capture level under 5.1/7.1 output, mic/output sample-rate mismatch, Bluetooth hands-free switching, whether gated or privacy-blocked mics deliver exact zeros, and how get_input_frames() behaves on WASAPI. Verified only on Godot 4.7.2 Linux with the Dummy audio driver: the input API exists, and a capture effect on a muted bus receives the full signal.
- The edge and latch bugs were reproduced in a Python port of the mic_monitor.gd logic, not in the running game. Scratch evidence (session scratchpad, may be cleared): /tmp/claude-0/-home-user-scary-game/391d9081-bae4-5e0e-8bf0-908243ecc927/scratchpad/sim/sim.py and /tmp/claude-0/-home-user-scary-game/391d9081-bae4-5e0e-8bf0-908243ecc927/scratchpad/captest/captest.gd
- At the door the stare rule is defeated because the game centres his head for you; I did not measure the exact starting angle after his lean-in, so a rare borderline pass above 16° is possible.
- All redesign numbers are untested starting values. Real-time feel cannot be judged in this container, so they need tuning from traces, bots and the owner's Windows playtest.
- Assumptions: the camera direction stands for the pianist's head direction (dark glasses hide his eyes); the locked difficulties (Easy, Hard, Nightmare) will be unlocked; the map, scare and chase specialists supply the rooms, registered objects and scare schedule this model consumes.
- Owner decision: should a scream within earshot always mean instant exposure on Normal (my default), or a large jump on the meter?
- Owner decision: may the game be played without a microphone at all, and is 30 % extra weight on the other composure signals an acceptable substitute?
- Owner decision: how hard should looking at his face and at the corpse be punished, given that he also wants players to see the gore? My default is free whenever he is not watching, with a 0.5 s glance allowance.
- Owner decision: are a brisk-walk key, a 'feel before use' interaction and a short lesson at her door (about 40 s) wanted?
- Owner decision: should the suspicion meter stay visible on Hard and Nightmare, and should Nightmare keep 'one mistake and you die'?
- Owner decision: should the microphone open only on the calibration screen? Today it opens at launch (/home/user/scary-game/blindact/scripts/settings.gd:43), so Windows shows the mic-in-use indicator from the main menu.
