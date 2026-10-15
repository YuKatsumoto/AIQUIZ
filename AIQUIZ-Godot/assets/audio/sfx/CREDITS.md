# Sound effect credits

## Ghost shark ride (2026-10-16)

All files in `ghost_shark/` (`ghost_soul_rise`, `ghost_shark_rise`, `ghost_shark_breach`,
`ghost_mount_beam`, `ghost_charge_loop`, `ghost_charge_perfect`, `ghost_dash`, `ghost_hit`,
`ghost_vanish`, `ghost_portal_open`, `ghost_portal_cross`) were synthesized for this project
without external samples. No third-party license restrictions. Rebuild with
`tools/audio/make_ghost_shark_sfx.py` (deterministic noise seeds, 48 kHz stereo, Ogg Vorbis q7;
−3 dBFS peaks, the charge loop −6 dBFS). Runtime gains are in `AudioManager.SFX_CUES` and
`docs/sound_effects.md`.

## Online VS face-off (2026-10-13)

`online/versus_cutin_in.ogg`, `online/versus_charge.ogg`, `online/versus_reveal.ogg` and
`online/versus_reveal_short.ogg` were synthesized for this project without external samples.
No third-party license restrictions. Rebuild with `tools/audio/make_versus_sfx.py`
(deterministic noise seeds, 48 kHz stereo, Ogg Vorbis q7; −3 dBFS peaks, the charge −6 dBFS).
Runtime gains are in `AudioManager.STAGING_SFX_CUES`.

## UI activation, landing, deaths and saw startup (2026-10-12)

`game/heli_land.ogg`, `game/shark_bite.ogg`,
`game/body_burst.ogg` and `game/saw_start.ogg` were synthesized for this
project without external samples. No third-party license restrictions.
Rebuild with `tools/audio/make_event_sfx.py` (deterministic noise seed,
48 kHz mono, Ogg Vorbis q7). The click has a −6 dBFS source peak; the
other files have −3 dBFS peaks. Runtime gains are documented in
`docs/sound_effects.md`.

## Helicopter (2026-10-12)

`helicopter/rotor_loop.ogg` uses **"Helicopter Rotor Loop.flac" by qubodup**,
Freesound 187681: https://freesound.org/people/qubodup/sounds/187681/ .
The author releases it under **CC0 1.0** (verified on the source page on
2026-10-12). Source: the site's high-quality MP3 preview, retained as
`source/helicopter/qubodup_187681_rotor.mp3`. Edits: 48 kHz mono, 65 Hz
high-pass / 7.5 kHz low-pass, soft peak compression, .30 s loop overlap,
peak −3 dBFS, Ogg Vorbis q7. Commercial use and source redistribution are allowed.

All other files in `helicopter/` (`turbine_loop`, `jet_loop`, `jet_ignite`,
`hatch_open`, `hatch_close`, `latch`, `belt_click`, `rope_release`,
`winch_loop`, `grip`) were synthesized for this project, with no external
samples. They have no third-party license restrictions. Rebuild with
`tools/audio/make_helicopter_sfx.py`.

## Start countdown (OtoLogic, CC BY 4.0 — credit required)

`game/countdown_beep.ogg` and `game/countdown_go.ogg` are OtoLogic's
`Countdown01-5` and `Countdown01-6` (https://otologic.jp), licensed under
**CC BY 4.0**: commercial use and editing are allowed, but a release must show
the credit **"OtoLogic"** (e.g. on the in-game credits or the store page).
License terms: https://otologic.jp/free/license.html (checked 2026-10-11).

- Edits: leading 0.1 s of silence trimmed, 2 ms fade-in, both raised by the
  same +17.6 dB, exported as Ogg Vorbis quality 6, 44.1 kHz stereo.
- Originals (with `Countdown01-3`, the five-beep version the game reproduces)
  are kept in `source/otologic/`:
  - `Countdown01-3.mp3` SHA-256 `437A2B7BE8534B82CA7B0677497DEAD4E13B03E20D403E6DADC16751436C8D82`
  - `Countdown01-5.mp3` SHA-256 `096B577084429C387B34F63FC94BD3D1D414A87A15995068AF33D0CE848DEAFC`
  - `Countdown01-6.mp3` SHA-256 `F10515C655A148D099F487333E81DDFD05915432B9AED26A8AF6EF93825C3D6C`

## Doors (OtoLogic, CC BY 4.0 — credit required)

`game/door_correct.ogg` is OtoLogic `Quiz-Ding_Dong02-1(Fast)` and
`game/door_wrong.ogg` is OtoLogic `Quiz-Buzzer02-1(Mid)` (https://otologic.jp,
CC BY 4.0: credit "OtoLogic" in the release). Edits: leading silence trimmed,
2 ms fade-in, normalized to −18 LUFS, Ogg Vorbis q6 44.1 kHz. All versions of both
packs are kept in `source/otologic/`. Added 2026-10-12.

## Wall hit, push, landing (`se_lab/`, not in git)

`se_lab/ui_click.ogg` (「カーソル移動1」, every button) and `se_lab/ui_start.ogg`
(「決定ボタンを押す53」, the menu's game-start button) were added the same way on
2026-10-12 (originals in `source/se_lab/`: `cursor_move1.mp3`, `decision_button53.mp3`).
Edits: leading silence trimmed, 2 ms fade-in, peak −6 dBFS, Ogg Vorbis q6. They replace
the synthesized `ui/click.ogg`, which is no longer used. **Confirm the source** before release.

`se_lab/wall_hit.ogg` (「打撃1」), `se_lab/push_kick.ogg` (「小キック」) and
`se_lab/jump_land.ogg` (「ジャンプの着地」) come from files the user supplied on
2026-10-12 (originals in `source/se_lab/`). The files carry no tags; the names match
効果音ラボ (https://soundeffect-lab.info/agreement/: game use allowed, no credit,
the files themselves may not be redistributed), so like the crowd sounds they are
kept out of this public repository. Edits: leading silence trimmed, 2 ms fade-in,
peak −3 dBFS. **Confirm the source** before release.

The Kenney wall sounds below (`game/bonk_*.ogg`, `game/wall_crash.ogg`) are no
longer used by the game since 2026-10-12.

## Quiz wall landing, saw startup, countdown wall (`se_lab/`, not in git)

Four more files the user supplied on 2026-10-12 (originals in `source/se_lab/`), same terms as
the other `se_lab/` files (the names match 効果音ラボ; keep them out of this public repository):

| File | Original | Use | Edits |
|---|---|---|---|
| `se_lab/wall_land.ogg` | 「ロボットを殴る2」 `robot_punch2.mp3` | a quiz wall landing on the conveyor | leading silence trimmed, peak -3 dBFS |
| `se_lab/barrier_land.ogg` | 「ロボットを殴る3」 `robot_punch3.mp3` (user-supplied 2026-10-12) | the countdown wall landing | leading silence trimmed, peak -3 dBFS |
| `se_lab/saw_start.ogg` | 「車のエンジンをかける1」 `car_engine_start1.mp3` | the saw's startup | first 4.0 s, 0.5 s fade-out, peak -3 dBFS |
| `se_lab/countdown_rumble.ogg` | 「ゴゴゴゴ」 `gogogogo.mp3` | the countdown wall rumbling | first 5.0 s, rising gain -16 dB -> 0 dB (squared), peak -3 dBFS |
| `se_lab/barrier_explosion.ogg` | 「爆発2」 `explosion2.mp3` | the countdown wall exploding | 0.25 s fade-out, peak -3 dBFS |

All are Ogg Vorbis q6. **Confirm the source** before release. `game/saw_start.ogg` (synthesized)
is no longer used by the game.

## Score tower drum roll (`se_lab/`, not in git)

`se_lab/score_roll.ogg` (「ドラムロール」, 2.0-6.3 s) and `se_lab/score_roll_finish.ogg`
(「ロールの締め」, the verdict at 6.9 s) come from files the user supplied on 2026-10-12
(originals in `source/se_lab/`: `drum_roll.mp3`, `roll_finish.mp3`). Same terms as the other
`se_lab/` files (the names match 効果音ラボ; keep them out of this public repository).
Edits: roll cut to 4.3 s with a 0.12 s fade-out and -3.2 dB; finish cut to 3.0 s with a 0.6 s
fade-out and +2.4 dB; 2 ms fade-in, Ogg Vorbis q6. **Confirm the source** before release.

The earlier synthesized roll `game/score_drum_roll.ogg` (Python, no third-party material, no
license restrictions) is no longer used by the game.

## Spectators (`crowd/`)

**Not in git except the CC0 murmur.** This repository is public, and the
Pixabay / 効果音ラボ terms allow using the sounds inside a game but forbid
redistributing the files themselves (効果音ラボ: even after editing), so
`crowd/.gitignore` and `source/crowd/.gitignore` keep them out. No credit is
required for any of them. Downloaded 2026-10-12; originals in `source/crowd/`.

| File | Source | License | Material / edit |
|---|---|---|---|
| `crowd/crowd_murmur_loop.ogg` | Freesound 453906 "crowd int large hall carpeted murmur2 busier" by kyles, https://freesound.org/people/kyles/sounds/453906/ | CC0 1.0 | compressed (4:1 from −32 dB) and limited, then 33–125 s with a 2 s tail crossfaded into the head (90 s loop), −18.2 LUFS |
| `crowd/crowd_race_loop.ogg` | Pixabay "Large crowd applause" (freesound_community, a re-post of Freesound 160493 by Bansemer, CC0), https://pixabay.com/sound-effects/people-large-crowd-applause-6250/ | Pixabay Content License | 35–69 s, 2 s tail crossfaded into the head (32 s loop), −20 LUFS |
| `crowd/crowd_aww.ogg` | Pixabay "Crowd Disappointment Reaction" by Universfield, https://pixabay.com/sound-effects/people-crowd-disappointment-reaction-352718/ | Pixabay Content License | head trimmed, −18 LUFS |
| `crowd/crowd_goal_cheer.ogg` | 効果音ラボ「スタジアムの歓声1」`people-stadium-cheer1.mp3`, https://soundeffect-lab.info/sound/voice/people.html | 効果音ラボ規約 https://soundeffect-lab.info/agreement/ | head trimmed, −18 LUFS |
| `crowd/crowd_win_cheer.ogg` | 効果音ラボ「歓声と拍手1」`people-performance-cheer1.mp3` (same page) | 効果音ラボ規約 | head trimmed, −18 LUFS |
| `crowd/crowd_applause.ogg` | 効果音ラボ「大勢で拍手パチパチ」`clapping-hands1.mp3`, https://soundeffect-lab.info/sound/anime/ | 効果音ラボ規約 | head trimmed, −18 LUFS |

Pixabay Content License (https://pixabay.com/service/terms/): free for
commercial use, no attribution; the content may not be redistributed or sold on
its own. 効果音ラボ terms: free for commercial use including games, no credit;
redistributing the material itself (edited or not), Content ID registration and
AI training are forbidden.

## Wall hits (CC0)

The player hitting a wall
(`game/bonk_1.ogg`, `game/bonk_2.ogg`, `game/wall_crash.ogg`). They were made
from the sources below, all released under **CC0 1.0** (public domain
dedication), so they may be used, edited and sold in commercial games without
attribution. Credit is kept here for provenance.

The files were trimmed, layered, pitch-shifted and loudness-normalised before
export (Ogg Vorbis, quality 5, 44.1 kHz). Cue names and levels live in
`SFX_CUES` in `scripts/autoload/audio_manager.gd`.

| File | Pack | Author | Source | Material |
|---|---|---|---|---|
| `game/bonk_1.ogg`, `game/bonk_2.ogg` | Impact Sounds | Kenney | https://kenney.nl/assets/impact-sounds | `impactTin_medium_000/002` + `impactPunch_medium_000/002` |
| `game/wall_crash.ogg` | Impact Sounds | Kenney | https://kenney.nl/assets/impact-sounds | `impactPlate_heavy_001` (pitched to 0.85) + `impactPunch_heavy_001` |
| `game/wall_crash.ogg` | 75 CC0 breaking / falling / hit sfx | rubberduck | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx | `bfh1_hit_05` |

Downloaded on 2026-10-09. Each source page listed CC0.
