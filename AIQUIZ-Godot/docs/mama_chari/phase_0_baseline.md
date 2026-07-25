# ママチャリ競争 Phase 0 ベースライン

- 記録日: `2026-07-20`
- 作業ディレクトリ: `C:/AIQUIZ/AIQUIZ-Godot`
- Gitルート: `C:/AIQUIZ`
- ブランチ: `master` (`origin/master` を追跡)
- 開始HEAD: `c06bf550cf90e637a5ca515a2fe77634ebec95c1`
- 開始コミット: `Merge arcade shark attack presentation`

## 1. 既存変更の保全境界

フェーズ0開始時点で、次は既に変更済みだった。すべてユーザー既存作業として扱い、フェーズ0では内容を変更していない。

```text
 M AGENTS.md
 M README.md
 M assets/shark/shark_swim_T_Shark_BaseColor.png.import
 M scripts/autoload/game_manager.gd
 M scripts/core/game_state.gd
 M scripts/effects/particle_spawner.gd
 M scripts/ui/death_wipe.gd
 M scripts/ui/gameplay_hud.gd
 M scripts/ui/hat_select.gd
 M scripts/ui/menu_preview_actor_ai_state.gd
 M scripts/ui/menu_wall_background_preview.gd
 M scripts/world/camera_controller.gd
 M scripts/world/game_world.gd
 M scripts/world/player_controller.gd
 M scripts/world/replay_scene.gd
?? assets/tripo_references/
?? scripts/ui/offscreen_player_marker.gd
?? scripts/ui/offscreen_player_marker.gd.uid
```

開始時の `git diff --stat` は、内容差分のある追跡ファイル14件、約728行追加・215行削除を報告した。`git status` 上は `AGENTS.md` を含む15件が変更扱いで、行末差分と未追跡ファイルはstat集計外に見える場合がある。

フェーズ0が追加したのは `docs/mama_chari/` 配下の設計資料と保全用チェックサムだけで、ゲームコード、シーン、リソース、プロジェクト設定、Tripo参照画像には変更を加えていない。

開始時の各ファイル内容は `phase_0_existing_work.sha256` にSHA-256で保存した。これは既存差分を復元するバックアップそのものではなく、フェーズ1以降に意図しない上書きがないか照合するための指紋である。

## 2. 接続中のGodot基準

Fennaraで次を確認した。

```text
Project: AIQUIZ 3D
Path: C:/AIQUIZ/AIQUIZ-Godot/
Godot: 4.6.3-stable
Renderer: Forward+
Driver: Vulkan
GPU: NVIDIA GeForce RTX 5070
Editor filesystem: ready
Asset tools: ready
```

`res://scenes/game_world.tscn` は49ノード。主要構成は `Player`、`CameraController/Camera3D`、`WallContainer`、`ParticleSpawner`、`GameplayHUD`、`DeathWipeLayer` である。ステージ床はシーンへ固定配置せず、`game_world.gd` から実行時に構築される。

## 3. 現在の競技関連基準

- 現在の競技状態は `STATE_GOAL_RACE`。`STATE_ATHLETIC_RACE` と `race_phase` はまだ存在しない。
- `goal_z` と `goal_winner` は `game_state.gd` が所有し、スナップショットへ `gz` / `gw` として含まれる。
- 標準値は `wall_start_z=22`、`wall_spacing=30`、床幅 `24m`。
- 現在の10問時の旧ゴールは `337m`。
- 2Pの画面前後差が `14m` を超えると、既存のスクロールアウト死亡判定が働く。
- `game_world.gd` はP1のWASD/Space、P2の矢印/Ctrl/KP0を直接ポーリングしている。
- ProjectSettingsのInputMapに保存されているのは `move_left` と `move_right` の2アクションだけ。
- ママチャリ、自転車道路、アスファルトの専用3D素材はまだ存在しない。
- 再利用候補として `assets/hats/helmet.glb`、`assets/hats/traffic_cone.glb`、未追跡の `assets/tripo_references/goal_gate_reference*.png` がある。

## 4. フェーズ0開始時の検証結果

### Fennara project diagnostics

```text
Files scanned: 91
Errors: 0
Warnings: 82
Failed files: 0
```

82件はフェーズ0開始前からある警告で、未使用の変数/引数、整数除算、名前のシャドーイングなど。フェーズ0では警告修正を行わない。

### Fennara scene validation

対象: `res://scenes/game_world.tscn`

```text
Structural issues: 0
3-second headless crash: no
Runtime errors: 0
Runtime warnings: existing warnings only
```

今後の受け入れ基準は、少なくとも新規スクリプトエラー0、シーン構造問題0、起動時クラッシュ0、今回より悪化する新規警告を残さないこととする。

## 5. フェーズ0成果物

- `phase_0_spec.md`: 遊び、操作、コース、勝者判定、実装境界の固定仕様
- `tripo_asset_plan.md`: Tripo生成素材、プロンプト、分割、寸法、採用、取り込み条件
- `phase_0_baseline.md`: 既存差分と検証状態の保全記録
- `phase_0_existing_work.sha256`: フェーズ0開始前から存在した変更内容の照合用ハッシュ

コミット、ブランチ作成、既存差分のステージング、Tripo生成、Godot実装はフェーズ0では行っていない。
