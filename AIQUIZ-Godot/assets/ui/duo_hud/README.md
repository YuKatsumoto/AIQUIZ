# AIQUIZ 2P status HUD

## Files

- `source/AIQUIZ_Duo_HUD_Compact.aep`: current editable After Effects 2026 motion source. The previous `AIQUIZ_Duo_HUD.aep` is retained.
- `motion.json`: 266 values sampled from ten native AE property tracks at up to 60 Hz, approximately 5.7 KB. Godot interpolates them using elapsed seconds.
- `scripts/ui/duo_player_status_card.gd`: native live labels, vector hearts and player cards.

The native AE source was built and rendered through the official **Higgsfield use After Effects** local MCP package (`fnf-after-effects-mcp` 0.1.1). This task invoked the local MCP through the Node SDK on the user's PC; AE tools were not advertised directly to this conversation. The package is installed under `%LOCALAPPDATA%/Higgsfield/ae-mcp`. No generated bitmap UI, paid cloud generation, or runtime Adobe dependency is used.

## Appearance and behavior

P1 orange `(0.95, 0.55, 0.20)` sits bottom left; P2 blue `(0.20, 0.65, 0.90)` sits bottom right. Cards are 188 x 80 logical pixels, about 55% less area than the previous 244 x 136 design. They are inset 16 horizontally and 36 from the bottom to clear the existing progress bar. Each score appears above its HP. Cards scale down on narrow viewports. Offscreen indicators reserve space above the cards.

- Entrance: 36 px upward slide with a 4 px overshoot, 0.44 seconds; P2 follows 0.067 seconds later.
- Score: 1.26 scale peak, 0.44 seconds, a rising +N label, twelve sparks and an expanding light ring.
- Damage: changed hearts reach 1.30 scale and disappear over 0.30 seconds, with eight diamond fragments and a short horizontal recoil.
- Recovery: changed hearts reach 1.32 scale, settling over 0.40 seconds, with eight sparkles and two expanding rings.
- A soft diagonal highlight and an edge trace play on entrance, score and recovery. Event bursts expire after 0.68 seconds; the bounded pool holds at most eight bursts per card. The idle state has no particles or moving highlight.
- Low HP: numeric `1 / 3`, explicit warning and a restrained border pulse.
- Zero HP: empty hearts and an OUT status.

Game state is authoritative. Neither AE data nor UI animation changes score, HP, collision or recovery rules. Normal 2P TEN/ENDLESS and HP-aware replays use these cards. 1P, tutorial, cooperative scoring and old replays retain their established presentation. Text follows `use_english_ui`.

## Editing the source

Open `source/AIQUIZ_Duo_HUD_Compact.aep` and select `AIQUIZ_Compact_Motion_v2`. It contains separate `P1 compact status` and `P2 compact status` instances. Open `AIQUIZ_P1_Compact_Card` or `AIQUIZ_P2_Compact_Card` to edit native text, surface shapes, individual heart paths, sparkle geometry or animation keys. Identity badges are separate semantic precomps. The source uses Arial Bold and no external media or effects plugins. Score/HP text expressions demonstrate state changes in the five-second preview; live game values, Japanese text metrics and vector effects are rendered by Godot using the exported timing curves.

The current native AE preview and actual-game video are in `artifacts/duo_hud_compact/`. The construction, polishing, sampling and export requests are retained there as JSON plus Node scripts. When changing motion, sample the corresponding AE property at the times in `tracks.json` and regenerate `motion.json` with `export_motion.mjs`. AE's recovery track is `AIQUIZ_P1_Compact_Card / Heart 3`, sampled from 3.0 to 3.4 seconds. The runtime JSON is included by the project's existing `*.json` export filter; the `.aep` source is excluded using `.gdignore`.

See `artifacts/duo_hud_compact/VERIFICATION.md` for the rendered runtime checks, event mapping and deliverable paths.
