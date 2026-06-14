# AIQUIZ Unreal移植 — Phase 8 / 9 / 10 進捗メモ（PSX・死亡FX・パッケージ）

最終更新: 2026-06-13 (GMT+9)
全体計画: `C:\AIQUIZ\AIQUIZ-Unreal移植計画.md`
実行モデル: **1セッション集中orchestration** — 重い移植/設計をサブエージェント（Workflow）で並列生成し、
C++/エディタ/uasset適用を本セッションで直列・検証。

| Phase | 内容 | 状態 |
|---|---|---|
| 6-7 | クイズ壁＋判定／フルループ＋HUD | ✅ 完了（`PHASE67_PROGRESS.md`） |
| **8** | **PSX（ディザ/減色・頂点スナップ）＋濃霧** | ✅ **アセット生成・コンパイル済み**（視覚調整は PIE） |
| **9** | **死亡爆散＋ドア4×5破片＋背面壁崩壊＋run可変** | ✅ **完了（C++・ビルド/テスト緑）** |
| **10** | **検証＆Windowsパッケージ** | ◧ scriptとチェックリスト整備（実行は長時間・手動） |

---

## Phase 9 — 死亡FX・破片・アニメ（C++、検証済み）

`scripts/world/quiz_wall.gd` / `player_controller.gd` の演出を移植。**ビルド緑・無描画テスト4/4緑（回帰なし）**。
- **ドア破片** `AAiQuizWall::BreakDoor`: 2×3 → **4×5**（Godot非プレビュー `chunks_x4/chunks_y5`）。impulse は
  `(±5, 1.5..6.5, 5..15) m/s`（quiz_wall.gd:366-372 と一致）。破片は使い捨てアクタ＋`SetLifeSpan(1.6)`。
- **背面壁崩壊** `ShatterWall`: 各ドアを 2×2 で散らし全パーツ非表示（churn は LifeSpan＋chunk上限で抑制）。
- **死亡爆散** `AAiQuizPawn::BurstBlockman`: `GameOverTimer>=2.0`（game_world.gd:514 の爆発タイミング）で
  ブロック人間の13箱を各々の現在トランスフォームで物理破片化＋非表示。次ラウンドで自動復元。
- **run再生レート**: `SetPlayRate(clamp(ActiveWallSpeed/3.5, 0.5, 2.5))` 毎tick（player_controller.gd:622-628）。

---

## Phase 8 — PSX＋濃霧（アセット生成・コンパイル済み、視覚調整は PIE）

PSXシェーダを Godot から **UE Custom HLSL へ逐語移植**（サブエージェント並列）。全マテリアルは
ヘッドレス commandlet で生成・`recompile_material` 成功・L_Game に配線・保存済み。詳細HLSLは
`Saved/peace3/_phase8_*.md` 参照。

- **M_PP_PSX**（`/Game/AiQuiz/Materials/`、ポストプロセス）: `psx_postprocess.gdshader` の
  **4×4 Bayer ordered dither ＋ 減色**（`bit_depth=5`→32階調/ch）を Custom ノードで逐語移植。
  Domain=Post Process、Blendable=After Tonemapping、SceneTexture=PostProcessInput0、
  PixelPos=ViewportUV×Size。**L_Game に Unbound `PPV_PSX`** を生成し weighted blendable 登録。
  （HUDはCanvas描画でポスト後に重なるため減色の影響を受けない。）
- **M_PSX_Surface**（頂点スナップ）: `psx.gdshaderinc` のクリップ空間XY/Z量子化を **WPO Custom HLSL** に移植
  （`ResolvedView` 行列でworld→view→snap→world）。`Color` VectorParameter（M_Blockman同名でMID駆動可）、Unlit。
  **生成のみ・未適用**（計画通り「頂点ジッターは後」。任意でstage/wall/pawnへ割当可）。
- **MPC_PSX**: 3スクリプトを **MERGE方式に統一**（並列エージェント間の命名不整合バグを修正）。
  14スカラ＋1ベクトル（bit_depth/dither/snap/fog_near1000/fog_far2000/precision_*・fog_color(0.82,0.85,0.90)）。
- **Stage_Fog**（Phase 3の既存を再設定）: `ExponentialHeightFog` density0.02 / inscattering (0.82,0.85,0.90) で
  Godot の near10→far20 濃霧を近似。

> 視覚一致（ディザ粒度・霧濃度）の最終調整は **PIEで目視**して MPC_PSX / fog_density を微調整。
> `psx_precision_xy` 等は MPC で実行時可変。

---

## Phase 10 — パッケージ（script整備、実行は手動・長時間）

`Saved/peace3/p10_package.ps1`: `RunUAT BuildCookRun -platform=Win64 -clientconfig=Development
-cook -build -stage -pak -iostore -compressed -archive`。**初回cookは15-40分**。終了後に exe/pak と
cookログ内の `DT_QuizBank` 参照を自動チェック。エディタは閉じて実行。

**定数突合チェックリスト**（パッケージ版で再確認、Godotと一致済み・C++ソースが正典）:
gravity18 / jump7 / speed7.6 / X±6.5 / door 2択(±3.5,半1.8)・4択([-5.8,-1.95,1.95,5.8],半1.45) /
wall_start_z22 / spacing30 / hit offset-0.4 / 背面カル-12.5 / マグマ y<-8 / 床上面-1.2・幅24 /
VISIBLE28 / MOVE_BUFFER3.5 / 速度clamp[1,8] / stage_factor1.0→1.15。

---

## 検証状況（正直な区分）

**ヘッドレスで検証済み**:
- Phase 9 C++ … `AiQuizEditor` リビルド緑、`AiQuiz` テスト4/4緑（回帰なし）。
- Phase 8 アセット … 3マテリアル生成＋`recompile_material`成功、L_Game ロード/セーブOK、テスト後もロードエラー無し。

**PIEでの目視が必要（ユーザー作業）**:
- PSX見た目（ディザ/減色/濃霧）の Godot 一致、死亡爆散/破片/カメラの体感、`D/Right`が原作"右"ドアへ、
  ベルト速度/判定タイミング（`godot-ai` 並走推奨）。
- 日本語フォント `F_NotoSansJP` の導入（`PHASE67_PROGRESS.md` §5、エディタD&D / `p6_import_font.py`）。
- `M_PSX_Surface` をメッシュへ割当するか（任意）。

**長時間・手動**:
- `p10_package.ps1` 実行（~15-40分）→ パッケージ版で日本語/DataTable同梱/操作を確認。

---

## 生成・変更物
- 変更(C++): `AiQuizWall.cpp`（4×5破片/壁崩壊）、`AiQuizPawn.{h,cpp}`（BurstBlockman/run可変）
- 新規(uasset): `Content/AiQuiz/Materials/{M_PP_PSX, M_PSX_Surface, MPC_PSX}.uasset`
- 変更(uasset): `Content/AiQuiz/Maps/L_Game.umap`（PPV_PSX 追加、Stage_Fog 濃霧化）
- dev(gitignore): `Saved/peace3/{p8_pp_psx,p8_psx_surface,p8_fog_mpc}.py`, `p10_package.ps1`,
  `_phase8_*.md`(HLSL/recipe), `p9_build.log` 他
