# AIQUIZ Unreal移植 — Phase 6 & 7 完了メモ（クイズ壁＋判定／フルループ＋HUD）

最終更新: 2026-06-13 (GMT+9)
全体計画: `C:\AIQUIZ\AIQUIZ-Unreal移植計画.md`

---

## 0. 結論

Phase 6（クイズ壁＋判定）と Phase 7（フルループ＋UMG相当HUD）は **完了・検証済み**。
Phase 2-5 と同じ **ハイブリッド（ロジック=C++ / 見た目=手続きC++）** 方針を踏襲し、
壁・壁プール・HUD・メニュー・結果画面・ゲームオーバー演出をすべて **C++ で手続き生成**した
（uasset の手編集に依存しない＝ヘッドレスでビルド/テスト可能）。

| Phase | 内容 | 状態 |
|---|---|---|
| 0-5 | セットアップ/データ/状態機械/ステージ/Pawn/ブロック人間 | ✅ 完了 |
| **6** | **クイズ壁＋判定（壁アクタ・プーリング・破片）** | ✅ **完了** |
| **7** | **フルループ＋HUD（メニュー→ゲーム→結果→リスタート/3-2-1）** | ✅ **完了** |
| 8-10 | PSX＋マグマ/フォグ／仕上げ・死亡爆散／パッケージ | 未着手 |

**検証**: `AiQuizEditor` リビルド緑（UHT含む）、無描画オートメーションテスト **4/4 緑**
（`AiQuiz.Wall.Pooling` / `AiQuiz.Loop.MenuAndResult` 新規 ＋ 既存 `StateMachine` / `Pawn`）、
12エージェントのアドバーサリ忠実性レビュー（44観点）で確定バグ **1件のみ → 修正済み**。

---

## 1. アーキテクチャ（追加クラス）

GameMode が状態機械の権威。見た目は新規アクタ／HUD が GameMode を毎tick読んで描画する。

```
AAiQuizGameModeBase (C++状態機械)
 ├─ BeginPlay: AAiQuizWorld を spawn（壁プール director）／HUDClass=AAiQuizHUD
 ├─ Event Dispatcher: OnStateChanged / OnQuizLoaded / OnCorrect / OnWrong / OnCleared
 ├─ AAiQuizPawn        : 入力push＋可視化＋メニュー/結果キー＋ゲームオーバーカメラ
 ├─ AAiQuizWorld       : MAX_VISIBLE_WALLS(4)+buffer プール。毎tick再配置/背面カル/ラベル/破片
 │    └─ AAiQuizWall   : 梁/柱（灰）＋ドア（色）＋TextRenderラベル＋BreakDoor/ShatterWall
 └─ AAiQuizHUD (AHUD)  : Canvas描画でメニュー/プレイHUD/3-2-1/結果（日本語UTF-8 BOM）
```

### 1.1 座標・符号（Phase 4 と一貫）
`GodotToUE(gx,gy,gz)=FVector(gz*100, -gx*100, gy*100)`（Godot X横→UE −Y、Y上→UE Z、Z奥→UE X、UU=100）。
壁ルートは director が `UE_X=100*(GetWallWorldZ(i)-WorldScrollZ)` に毎tick再配置（床メッシュは動かさない＝トレッドミル）。
ドアラベルは `gz=-0.65`（プレイヤー側 −X）＋yaw180 でプレイヤーに正対。

---

## 2. Phase 6 — クイズ壁＋判定

### 2.1 `AAiQuizWall`（`AiQuizWall.{h,cpp}`）
`scripts/world/quiz_wall.gd` を忠実移植（レビューで全寸法一致を確認）：
- 梁/柱: `total_width24 / door_top2.38 / door_bottom-2.02 / wall_top4.05 / wall_bottom-3.15 / 奥行0.55`、
  柱gap-walk アルゴリズムと `>0` ガードまで一致。
- ドア: 2択 `3.6×4.4×1.2`（中心 left=+3.5 blue=doors[0] / right=-3.5 red=doors[1]）、
  4択 `2.9×4.4×1.2`（`DOOR4_XS=[-5.8,-1.95,1.95,5.8]`、A/B/C/D=青/緑/橙/赤）。
- ラベル: `UTextRenderComponent`＋NotoSansJP（§5）。2択は選択肢テキスト、4択は `"A. テキスト"`。
- `BreakDoor(i)`: 正解ドアを非表示＋簡易破片（2×3物理キューブ。Phase 9 で 4×5＋FX）。
- `ShatterWall()`: 背面崩壊（少量破片＋全パーツ非表示）。
- **破片は使い捨てアクタ＋`SetLifeSpan(1.6)`** で壁の破棄後も残存（Godotが破片を親へ追加するのに対応）。

### 2.2 `AAiQuizWorld`（`AiQuizWorld.{h,cpp}`）
`game_world.gd::_update_walls` を移植。`ComputeNeededIndices(...)` を **純粋静的関数**に切り出して単体テスト可能化：
`start_idx=max(0,current-3)`、`MAX_VISIBLE_WALLS(4)+3` スロット、`max_wall_idx=target-1`（10Q固定）、
`local_z>FLOOR_BACK_Z(-12.5)` で採用、`<=FLOOR_BACK_Z+0.1` で `ShatterWall`＋Destroy、毎tick全壁再配置、
現在壁のみラベル更新、`OnCorrect→BreakDoor(answer)`。

### 2.3 GameMode 追加（判定・演出）
`ResolveCollision` で `correct_flash=1/camera_shake=0.22`＋`OnCorrect`＋`AdvanceAfterCorrect`（停止せずPLAYING継続）、
不正解/柱は `VelY=JUMP*0.8, VelZ=-12` ノックバック＋`DoGameOver`。`OnCleared` で target 到達 CLEAR。

---

## 3. Phase 7 — フルループ＋HUD

### 3.1 `AAiQuizHUD`（`AiQuizHUD.{h,cpp}`、AHUD/Canvas）
`gameplay_hud.gd`＋メインメニューを **内容忠実**に移植（ピクセル配置は新規Canvasレイアウト）：
- **メニュー**: 教科/学年/難易度セレクタ（DataTable から distinct 抽出）＋スタート促し＋操作ヒント。
- **3-2-1**: 中央に大カウントダウン（`GetCountdownDisplay()=ceil`）。
- **プレイ**: 問題パネル（自動改行）／スコア `正解: %d  問題: %d/10`／10問プログレスバー／
  連続正解／correct-flash の `正解！`／全画面フラッシュ（緑/赤、`correct_flash/wrong_flash`）。
- **結果**: `GAME OVER`(赤4秒フェード後)／`CLEAR!`(即時) ＋スコア＋統計（正答率/連続正解/時間）＋
  ゲームオーバー文言（不正解/柱→「不正解！ 正解は X」、マグマ→「マグマに落ちてしまった！」）＋解説（`quiz.E`）＋
  `R:リトライ Esc:メニュー`。
- 日本語リテラルは本ファイルに集約し **UTF-8 BOM** で保存（MSVC が正しく解釈）。

### 3.2 GameMode メニューAPI＋演出状態
`GetAvailableSubjects()/GetAvailableGrades()`（DataTable から distinct）／`StartRoundFromMenu()`／`ReturnToMenu()`、
`correct_flash/wrong_flash/camera_shake` 減衰（1.5/1.2/2.8）、`GameOverTimer`＋`ProcessDeadPhysics`
（`move_toward(vel_z,0,dt*15)`＝`FInterpConstantTo`、<2.5s 窓、限界Y）、`PlayTime/MaxStreak/CurrentStreak/TotalAnswered`。

### 3.3 Pawn 入力＋カメラ（`AiQuizPawn.cpp`）
- メニュー: A/D 教科・W/S 学年・Q/E 難易度・Enter/Space 開始。結果: R リトライ・Esc メニュー（`WasInputKeyJustPressed`）。
- ゲームオーバー: `camera_controller.gd` 1P を移植（`ease_t=1-(1-min(1,go_timer*0.5))^3`、`dist=ease*8`、
  後方+上へドリー＋減衰シェイク）。プレイ時は従来のFPS＋head-bob。
- 入力符号トラップ（D→AxisX=-1→右ドア-3.5→UE +Y）は Phase 4 のまま維持（レビューで再確認）。

### 3.4 BP / 配線
`BP_AiQuizGameMode` を `bAutoStartInPIE=false`／`HUDClass=AAiQuizHUD`／`DefaultPawnClass=AAiQuizPawn` に設定済み
（`p7_config_bp.py`）。PIE は **メニューから開始** する本番フローに。デバッグ自動開始は `bAutoStartInPIE=true` で復活可。

---

## 4. 検証

### 4.1 リビルド（緑）
`Build.bat AiQuizEditor Win64 Development` → UHT 9ファイル生成、全コンパイル/リンク成功。

### 4.2 無描画オートメーションテスト（`-NullRHI`、4/4 緑）
- `AiQuiz.Wall.Pooling`（新規）: `ComputeNeededIndices` の開始7枚/背面カル/末尾 target-1 上限。
- `AiQuiz.Loop.MenuAndResult`（新規）: flash減衰率、3-2-1、正解継続、不正解ノックバック＋死亡物理、
  target到達CLEAR、**DataTable からのメニュー→StartRoundFromMenu→Playing→ReturnToMenu** フルループ。
- `AiQuiz.StateMachine.CoreTransitions` / `AiQuiz.Pawn.CoordsAndAnim`（既存、回帰なし）。

### 4.3 忠実性アドバーサリレビュー（12エージェント／44観点）
壁寸法・色・判定index・プーリング・死亡/flash/timer・HUD内容・Pawnカメラ/符号を Godot 原典と突合。
**確定バグ1件のみ → 修正済み**:
- 壁/柱激突時の文言。Godot 1P は柱激突も不正解ドアも同じ「不正解！ 正解は X」を表示するが、
  移植は `Wall` 理由で原作に無い「壁にぶつかった！」を出していた → HUD で `Wall` も
  「不正解！ 正解は X」に統一（enum `Wall` は原因情報として保持）。
- 軽微: スコア行スペース（3→2 に修正し原作一致）。
- 意図的差分: カウントダウン 3.0s（プランの「3-2-1」準拠。Godot は 3.99s で「4」から表示）。

---

## 5. フォント（NotoSansJP）— エディタでの1手順

ドアラベル／HUD の **日本語描画には Font 資産が必要**（未導入時はエンジン既定フォントにフォールバック＝
日本語は □ になるが ASCII/数字とロジックは正常）。UE5.7 の Font import は **Slate（GUI）必須**で、
`-NullRHI` コマンドレットでは `SlateApplication` アサートでクラッシュするため **ヘッドレス自動化不可**。

→ **エディタで以下のいずれか**（`/Game/AiQuiz/UI/F_NotoSansJP` を Runtime Font として生成）:
1. `C:\AIQUIZ\AIQUIZ-Godot\resources\fonts\NotoSansJP-Regular.otf` をコンテンツブラウザの
   `/Game/AiQuiz/UI` へ **ドラッグ＆ドロップ**（自動で Font＋FontFace 生成）。リネーム→`F_NotoSansJP`。
2. または エディタの Python コンソールで `Saved/peace3/p6_import_font.py` を実行。
（コードは `/Game/AiQuiz/UI/F_NotoSansJP.F_NotoSansJP` を自動ロード。生成すれば即反映。）

---

## 6. 生成・変更物
- 新規: `Source/AiQuiz/AiQuizWall.{h,cpp}`, `AiQuizWorld.{h,cpp}`, `AiQuizHUD.{h,cpp}`,
  `AiQuizPhase67Test.cpp`
- 変更: `AiQuizGameModeBase.{h,cpp}`（events/flash/死亡演出/メニューAPI/HUDClass/director spawn）、
  `AiQuizPawn.{h,cpp}`（HandleMetaInput/ゲームオーバーカメラ）
- 変更: `Content/AiQuiz/Core/BP_AiQuizGameMode.uasset`（bAutoStartInPIE=false / HUDClass=AAiQuizHUD）
- dev(gitignore): `Saved/peace3/p6_import_font.py`, `p7_config_bp.py`, `p67_build*.log`, `p67_test*.log`

---

## 7. 次（Phase 8 以降）
- フォント資産の導入（§5）と PIE 実機での目視（メニュー→10問→クリア／不正解→ゲームオーバー→R/Esc、
  D/Right が原作の"右"ドアへ、ベルト速度/判定タイミングを `godot-ai` 並走で突合）。
- Phase 8: `PP_PSX`（ディザ/減色）＋フォグ＋`M_PSX_Surface`＋`M_Magma`。
- Phase 9: 死亡ラグドール/パーツ分離＋ドア 4×5 破片バースト/背面壁崩壊の本実装、run 再生レート可変。
- 壁マテリアルは暫定で `M_Blockman`(Color param) を流用 → 専用 `M_WallSurface` に置換予定。
