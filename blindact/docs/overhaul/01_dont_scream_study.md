# 01_dont_scream_study

## Key points

- DON'T SCREAM rests on one always-on rule (microphone level over a calibrated line = instant restart) plus a clock that only advances while you move, so the player can neither negotiate with the rule nor wait the scares out.
- BLIND ACT's microphone can convict for only 22-29 s of a five-minute run, because night_state.gd:115-125 judges sound only inside visual-test windows and gaze is likewise judged only inside tests; that is why the owner's scream-into-his-face test did nothing, and both channels must be judged continuously.
- Use two microphone bands (a quiet sound draws his attention, a gasp adds suspicion, a real scream exposes and starts the chase) instead of DON'T SCREAM's single line, whose cough, sneeze, laugh and dog false positives are its most common complaint.
- Louder stingers will leak from speakers into the microphone (a DON'T SCREAM player was restarted this way), so calibration needs a speaker-bleed test, a headphone prompt and a short gate after the game's own stingers.
- Calibration must prove itself (shout and watch the bar turn red), the mic bar with its threshold tick must stay on the HUD, a dead or muted mic must be flagged, and 'skip' must become a labelled no-mic mode, because today it silently disables every mic tell.
- Replace the hard-coded pool of four tests at game.gd:1265 with a Scare Director (curated lists per room and phase, tags, no repeats within a run, cooldowns, a rising tier budget) and wire in the unused scare_rate and scare_intensity difficulty keys.
- Density reference: DON'T SCREAM fires 58-75 scares in an 18-minute clear and players still habituate, while BLIND ACT has about seven beats in five minutes; aim for roughly 30 events in 25 minutes with only six to eight full jump scares and the rest audio, peripheral and fake-out events.
- Avoid DON'T SCREAM's proven faults: a consistent pre-scare tell (their blackout, our lamp stutter), one reused scream sample (our single stinger.ogg at six call sites), scares unrelated to the story, nothing to do between scares, and deaths decided by chance.
- A jump scare needs a written frame spec: about a second of ducked sound, a hit with under 10 ms attack and 2-5 kHz energy, a lit face filling 40% of the frame within one frame, an FOV punch and 2-3 glitch frames; the current stinger is a sub-bass boom and the shader's glitch and ghost uniforms are never driven.
- The current grade removes blood: cold = 1.0 plus lenses at 0.8 leave fully lit blood with about 18% of its red and turn skin grey (computed from screen_fx.gdshader, not rendered), so red must be exempted from the cold grade.
- BLIND ACT's watching murderer supplies what DON'T SCREAM lacked: harmless hallucinations can provide scare volume while his gaze provides the stakes, provided every exposure is traceable on the end card and never random.
- A 25-minute story should fail forward (exposure leads to a chase with escape tasks) rather than restart, with progress-gated time and a 4-6 s composure window, sometimes followed by a second opposite-rule stimulus, after every big scare.

## Report

**Access.** WebSearch worked; WebFetch was refused for every host tried. **V** = confirmed in search extracts of the named source (pages not read in full); **M** = from memory, unverified.

## 1. How DON'T SCREAM works

**(a) Microphone**
- Calibration is in-game and first. Target: "every whimper, jump, or even a minor squeak is registered as a scream"; quiet talk "slightly softer than normal" passes (V: Steam page, PC Gamer).
- Detection is a bare level threshold: a volume bar (bottom right) with a divider line; crossing it turns the bar red, flashes the screen red and restarts the run (V: DualShockers, Steam FAQ thread). It cannot tell a scream from a cough, sneeze, laugh, dog or the game's own audio leaking into the mic (V: Steam reviews).
- Added later: device choice, level and mute detection; automatic or manual threshold; "Mic Input Scale"; "Retry Mode" on by default to contest false positives; headset "highly recommended" (V: patch notes).
- No or muted mic: a large icon shows (hideable) and "you just will never die", an honour system (V). Since 1.0 a lower band exists too: whispering or environment noise draws hunters (V).

**(b) Timer, length, win**
- The clock runs only while the player moves: 18 minutes of movement until dawn (store text: reach 08:00 AM). A scream restarts from zero. 1.0 added death by hunters and traps and a draining camcorder battery (V).

**(c) Scare system**
- A "Scare Director" draws from curated lists per area and time slice; zone rules keep animals out of interiors and large scares out of tight spaces; pacing is throttled early and frequency rises through the run (V: Unreal Source interview, 1.0 notes, asobit review).
- Volume: "dozens" officially; one clear logged 58 scares in 18 minutes, a Steam reviewer counted 75 (V): 3-4 a minute.
- Categories (2025 notes): world, camera, creatures, hunters; plus audio-only, traps, fake-outs (V).
- Triggers: zone plus time slice, presumably of the movement clock (V); turning around (V: DualShockers); some fixed points (V: sequel review). Cooldown and no-repeat logic are undocumented.
- Updates: 1.0, 28 Oct 2024 (director, better models and sound, relics, Arachnophobia mode); Sep 2025 (Atmospheric and Chaos modes, No-Hunters toggle, less predictable timer) (V).

Scares players report:
1. Pop-up screamer at arm's length, yelling into the lens or blocking the view; one scream sample serves several; harmless in early access (V: Dread Central, asobit, Prima, Steam thread).
2. Turn-around ambush: it waits behind and launches when the player rotates (V: DualShockers).
3. Double tap: a second scare fired during recovery from the first (V: Dread Central).
4. Spider attack, singled out as the most effective (V: Prima).
5. Spider crawling across the lens, a "camera" scare (V: note.com review).
6. Sudden bang with no source; decoy noises that never pay off; binaural sounds at the ear (V: asobit, Prima, 1.0 notes).
7. Blackout cut: the picture drops to black, then something is there; criticised as a tell (V: Steam thread).
8. Space rupture: abrupt teleport elsewhere in the forest (V: achievement "The Missing").
9. Scarecrow the player can shove (V: achievement "The Menace").
10. Dread set-pieces: bodies hanging from trees, a crashed airliner, a mini-mart interior called the scariest stretch (V: DualShockers, JP reviews).
11. Lethal objects: handling the wrong thing ends the run; sequel traps carry a red glow (V: Prima, Steam guide).
12. Hunters: humans, cult-like patrols and bears that chase and kill, drawn by noise and loitering (V: Steam notes, NamuWiki, sequel reviews).
13. Finale ramp: scares cluster late; one was loud enough to leak from headphones into the mic (V: asobit, Steam review).

**(d) Presentation**
- A photoreal UE5 forest through a 1990s camcorder: noisy VHS image, pitch black outside one light (V); light cone on the camera, timestamp overlay (M).
- At the scare: the actor is already inside the light and close; loud scream sample; noise burst and shake (M); sometimes a blackout first (V).

**(e) Corpses and creatures**
- Hanging bodies, wreckage, "monstrous creatures", ghosts, spiders, bears, human hunters; gore is part of the pitch (V). Pale, gaunt faces with dark sockets and gaping mouths, flattened by the camera light so skin blows out against black (M).

**(f) Reception**
- Steam "Mixed", about 65% of 4,500 reviews; Prima 5.8/10; IGN Italia 55; 40,000 copies in 24 hours (V).
- Works: the rule itself, atmosphere and audio, build-up, the short "one more run" loop.
- Fails: startle is not fear and wears off; "the same few things" and one scream sample; the blackout tell; no threat in early access, then random hunter deaths in 1.0 (hence the toggle); "just press W", no objectives; scares unrelated to place or story (DSOGaming); mic false positives (V).

## 2. LESSONS FOR BLIND ACT

Paths: scripts are in `/home/user/scary-game/blindact/scripts/`, the shader in `/home/user/scary-game/blindact/shaders/`, generators in `/home/user/scary-game/blindact/tools/`.

1. **Microphone always on, in two bands.** The rule frightens only if it is never off duty. `night_state.gd:115-125` counts a sound only while a `visual` test is open: 22-29 s of a five-minute run, so the owner's scream fell outside. Judge continuously, in two bands like DON'T SCREAM since 1.0: a quiet sound draws his attention (he turns, comes over, tests sooner); a gasp over threshold adds 35-50 suspicion (doubled in a silent-scare window, halved just after a loud world sound); a scream (calibrated voice +6 dB for 0.3 s) exposes.
2. **Gaze always on.** `game.gd:2034` computes `state.watched`, but it only slows decay (`night_state.gd:138`); gaze is judged only inside tests, and only if the view "moved onto" the target (`:166`). While watched, add continuous tells: eye contact over 0.8 s, smooth pursuit of his silently moving face or knife, dwelling on the body or blood.
3. **Show the instrument.** HUD mic bar with threshold tick (reuse `pregame_ui.gd:258-269`), red rim on crossing, his head snapping to you within 150 ms. When `digital_silence > 2.5` (`mic_monitor.gd:37`, checked only at `pregame_ui.gd:236`) show a mic-lost icon.
4. **Calibration that proves itself.** Extend `pregame_ui.gd:216-256` (3 s quiet, one gasp) with "now shout: the bar must turn red", a manual threshold slider, and a speaker-bleed test (play the loudest stinger, measure the mic; on bleed ask for headphones or gate the mic 250 ms after own stingers). "Skip" (`pregame.gd:198-200`) silently disables every mic tell (`night_state.gd:116`): make it a labelled no-mic mode shown on the ending card.
5. **Scare Director.** Replace `game.gd:1265` (four tests, two drawn, at a fixed 28% and 62% of piece one) with a table: rooms, phases, channel (audio, peripheral, apparition, contact, environment, fake-out), real or hallucination, required reaction, tier 1-4, cooldown, weight. Draw without replacement, down-weight scares seen in the last two runs, keep gaps of 12-45 s, raise the tier budget through the night, read the unused `scare_rate` and `scare_intensity` (`difficulty.gd:25-46`). Target: pool of 36+, about 30 events in 25 minutes, six to eight at tier 4.
6. **Time gated on progress.** Clock and scare schedule advance on notes played and task steps, not `wait()` (`game.gd:1267-1269`); stopping for 5 s is itself suspicious. No scare can be waited out.
7. **Composure window and double tap.** After each tier 3-4 scare, 4-6 s of heightened judging on every channel (`scare_window`, `night_state.gd:65-68`, covers piano errors only); in 30% follow 0.8-2.5 s later with the opposite rule: a silent apparition, then a real crash he expects you to turn to.
8. **No fixed tell.** DON'T SCREAM's blackout taught players when to brace; ours is the lamp stutter (`game.gd:1470-1474`) and one `stinger.ogg` at six call sites (`game.gd:994, 1333, 1482, 1641, 1715, 1878`). Randomise lead-ins (none 40%, misdirect 30%, build-up 30%, a third of build-ups pay nothing); synthesise eight or more stingers in `tools/gen_sfx.py`.
9. **Specify the scare frame.** Sound: duck the bed 8-12 dB for about a second, then a hit with under 10 ms attack and energy at 2-5 kHz; the present stinger is a 32-92 Hz boom with screech partials at 0.12 gain (`/home/user/scary-game/tools/gen_audio.py:587-601`, CORRIDOR's generator: leave it alone). Picture: face within 0.45 m filling 40% of screen height, key light on in one frame (`_face_light`, `game.gd:1603-1615`, takes 120 ms to reach 0.55), lunge in 80-120 ms, FOV punch, 2-3 frames of `glitch` and `ghost` (in `screen_fx.gdshader`, never driven at `game.gd:2070-2075`).
10. **Let red survive the grade.** `game.gd:210` sets `cold = 1.0`, desaturating warm hues 25-70% (`screen_fx.gdshader:129-135`); lenses at 0.8 (`game.gd:1027`) multiply by 0.48 (`:117-125`). Computed from the shader: fully lit blood (0.52, 0.02, 0.03) leaves at (0.09, 0.03, 0.035), 18% of its red; skin turns grey. Keep the world cold, exempt red, drop the lenses to 0.2 for the scare frame.
11. **Hallucinations for volume, the watcher for stakes, never dice.** Harmless visions allow many scares; his gaze makes each reaction costly: the threat DON'T SCREAM's early access lacked, without the random deaths of its 1.0. Remove chance kills (`_rng.randf() < 0.25`, `game.gd:1825`); add a timestamped list of tells to the end card's mic graph (`game.gd:1889`).
12. **Give scares something to interrupt, from this story.** Tasks that occupy the hands (a phrase, the basin, carrying, tuning the string); scares built from her, the wire, the knife, the phone, using only images the pianist has already seen for real.
13. **Fail forward.** An 18-minute loop can restart; a 25-minute story cannot. Exposure leads to the chase, run like the hunters of DON'T SCREAM TOGETHER: loitering gets you found, and each finished escape task buys 10-15 s of reprieve. Offer one-take as hard mode, with gore, photosensitivity and no-mic options.

**Sources:** [Steam store](https://store.steampowered.com/app/2497900/DONT_SCREAM/) · [1.0 notes](https://steamdb.info/patchnotes/16207888/) · [Steam news: hotfix, 2025 update](https://steamcommunity.com/app/2497900/allnews/) · [Settings Update 1](https://steamcommunity.com/games/2497900/announcements/detail/3798283474561205911) · [Unreal Source interview](https://unrealsource.com/n/dont-scream-small-team-leveraging-unreal-to-deliver-dynamic-scares/) · [PC Gamer](https://www.pcgamer.com/if-you-scream-while-playing-dont-scream-you-have-to-restart-the-game/) · [Prima Games](https://primagames.com/reviews/dont-scream-early-impressions-review-a-neat-premise-with-creepy-framework) · [DualShockers](https://www.dualshockers.com/dont-scream-is-the-best-jumpscare-sim-ive-played-in-ages/) · [Dread Central](https://www.dreadcentral.com/editorials/493396/dont-scream-unnerves-by-forcing-you-to-stay-quiet/) · [Deaf Sparrow](https://www.deafsparrow.com/2024/02/22/dont-scream-literal-title-psychological-horror/) · [DSOGaming](https://www.dsogaming.com/news/dont-scream-is-a-new-unreal-engine-5-powered-horror-game-with-an-interesting-concept/) · [GamesPew](https://www.gamespew.com/2025/09/dontscream-update/) · [Steam design-feedback thread](https://steamcommunity.com/app/2497900/discussions/1/3884977551672152198/) · [Steam FAQ thread](https://steamcommunity.com/app/2497900/discussions/0/6993585599476477127/) · [Steam no-mic thread](https://steamcommunity.com/app/2497900/discussions/0/3939020962908231578/) · [Steam negative reviews](https://steamcommunity.com/app/2497900/negativereviews/?browsefilter=toprated) · [achievements](https://steamcommunity.com/stats/2497900/achievements) · [Wikipedia](https://en.wikipedia.org/wiki/Don%27t_Scream) · [NamuWiki](https://en.namu.wiki/w/DON'T%20SCREAM) · [asobit](https://asobit-project.com/game-strategy/dont-scream/) · [note.com](https://note.com/ryurou777/n/n113de8d172d5) · [Automaton](https://automaton-media.com/articles/newsjp/20231102-270478/) · [Metacritic](https://www.metacritic.com/game/dont-scream/) · [sequel guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3621583274) · [sequel review](https://gamersocialclub.ca/2025/12/12/dont-scream-together-review/)

## Unknowns / open decisions

- Web access was partial: WebSearch worked, but WebFetch could not resolve store.steampowered.com, gamespress.com, primagames.com or www.pcinvasion.com (they would have to be allowed in the session's network settings), so every claim marked V rests on search-result extracts rather than full pages; quotes may be paraphrased and dates can be a day off (most sources give 27 October 2023 for early access).
- Not found in any source: the exact calibration steps and numeric thresholds, the minimum sound duration, what 'Retry Mode' actually does, the Scare Director's cooldown, no-repeat and look-direction rules, and the real size of the scare pool ('dozens' officially; 'over 100' on a fan wiki is unverified).
- No wiki or guide enumerates the scares and I could not watch footage, so the scare list is assembled from reviews, patch notes and achievements; the details marked M (timestamp overlay, on-camera light cone, noise burst and shake at the scare moment, the look of creature faces) are from memory only.
- Which of two note.com player reviews mentions the spider on the lens is uncertain (the search returned both; I linked one), and hunter and creature designs are described only in passing (NamuWiki, reviews of the sequel).
- Assumption: the 'time slice' in the Unreal Source interview refers to the movement-gated clock.
- All BLIND ACT numbers I propose (gasp +35-50, scream = calibrated voice +6 dB for 0.3 s, gaps of 12-45 s, pool of 36+, about 30 events in 25 minutes, 30% double taps, the lead-in mix, the 250 ms gate) are starting values to tune on the owner's Windows machine; nothing was run or rendered here, and the blood-colour figure is computed from the shader formula, not measured from a frame.
- The owner's failed test has two possible causes in code (the scream fell outside a visual-test window, or calibration was skipped so Settings.mic_this_run was false); I could not tell which occurred, though the same change fixes both.
- Owner decision: is a working microphone mandatory, or is a labelled no-mic mode acceptable (and what replaces the voice tell in it)?
- Owner decision: should a real scream expose instantly on every difficulty, or only add a large amount of suspicion on easy?
- Owner decision: how much progress may be lost on exposure or death (checkpoints per act, or one take), given that DON'T SCREAM's full restart suits an 18-minute loop but not a 25-minute story?
- Owner decision: how loud may jump-scare stingers be, and are headphones required (speaker users risk false exposure from audio bleed)?
- Owner decision: may saturated red blood break the earlier 'no warm colours' rule, and are gore and photosensitivity toggles wanted?
