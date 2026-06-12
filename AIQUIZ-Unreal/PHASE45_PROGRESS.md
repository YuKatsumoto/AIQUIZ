# AIQUIZ Unreal移植 — Phase 4 & 5 完了メモ（Pawn＋カメラ＋入力／ブロック人間＋アニメ）

最終更新: 2026-06-12 (GMT+9)
全体計画: `C:\Users\kykat\.claude\plans\godot-unrealengin-effervescent-lecun.md`

---

## 0. 結論

Phase 4（Pawn＋カメラ＋入力）と Phase 5（ブロック人間＋アニメ）は **完了・検証済み**。
Phase 2 と同じ **ハイブリッド（ロジック=C++ / 見た目=資産）** 方針で C++ `AAiQuizPawn` を実装。
入力符号トラップ・座標変換・アニメ選択を **無描画オートメーションテスト**で機械検証し、
Mixamo キャラ＋ブロック人間の見た目を**スクリーンショット**で、実機起動を **`-game`** で確認した。

| Phase | 内容 | 状態 |
|---|---|---|
| 0-3 | セットアップ/データ/状態機械/ステージ | ✅ 完了 |
| **4** | **Pawn＋カメラ＋入力（C++）** | ✅ **完了** |
| **5a** | **Mixamo キャラ＋状態連動アニメ（run/jump/fall）** | ✅ **完了** |
| **5b** | **ブロック人間（箱）レンダリング** | ✅ **完了** |
| 6-10 | クイズ壁/フルループ/PSX/仕上げ/パッケージ | 未着手 |

---

## 1. Phase 4 — `AAiQuizPawn`（C++）

`Source/AiQuiz/AiQuizPawn.{h,cpp}`。GameMode が状態機械の権威で、Pawn は **入力 push＋可視化**に徹する。

### 1.1 入力（符号トラップ — 計画 §1.4 の罠）
Godot `game_world.gd:118-123` の `Input.is_key_pressed` を**直接ポーリングで1:1移植**（Enhanced Input より
原作に忠実かつ堅牢）。**D / Right → axisX = -1.0、A / Left → +1.0**（物理キーと反転）。
GameMode は `PlayerX += AxisX * 7.6 * dt`（Godot と同一）。**二重反転**（キー反転＋下記 UE_Y の -100）が
打ち消し合い、視覚的に「D で右の `right_door_x = -3.5` ドアへ」動く。C++ で追加の反転をしないこと。

### 1.2 座標変換（毎tick、SetInput の後に状態を読んで配置）
```
UE_X = 100 * GameMode->GetPlayerLocalZ()   // ≈0 固定（トレッドミル：壁が手前へ動く）
UE_Y = -100 * GameMode->PlayerX            // 符号は負（右ドア -3.5 → UE +Y=+350）
UE_Z = -120 + 100 * GameMode->PlayerY      // 床上面 -120、PlayerY は高さ(≥0)
```
`AAiQuizPawn::ComputePawnLocation()`（純関数・テスト対象）。p4_graph.py の誤り（X=-800固定／床offset欠落）を是正。

### 1.3 カメラ（Godot camera_controller.gd 1P・FPS）
FOV **44**、eye **120uu(1.2m)**、head-bob `sin(t*1.2)*0.04m=4uu`（Z）。マウスルックはスライス未実装
（yaw=0 で `move_x=axis.x` が厳密成立。原作の camera-relative 移動は後追い）。

### 1.4 起動（テスト用）
`AAiQuizGameModeBase::BeginPlay` が `bAutoStartInPIE` で自動 `StartRoundWithQuizzes(empty, 0)`＝
**フリーラン**（壁なし＝衝突なし）。移動/ジャンプ/落下/アニメを無限に観察できる。`DefaultPawnClass = AAiQuizPawn`
（C++ コンストラクタ＋ `BP_AiQuizGameMode` の default_pawn_class を AAiQuizPawn に再配線）。PlayerStart=(0,0,-120)。
> 本物のメニューが StartRound を駆動する Phase 7 で `bAutoStartInPIE=false` にすること。

---

## 2. Phase 5 — Mixamo キャラ＋アニメ＋ブロック人間

### 2.1 アセットインポート（`Content/AiQuiz/Character/`）
Mixamo FBX を UE5.7（Interchange）でインポート：`SK_YBot`(180.5cm・足元z=-120で床に一致)＋`SK_YBot_Skeleton`
＋`A_Run`/`A_Jump`/`A_Drown`。**Mixamo は -Y を向くので AnimMesh を yaw +90 で +X 前方へ。**
> ハマり: コミットレットの Interchange アニメインポートは1セッション2本目でクラッシュ（ContentBrowser/Slate）。
> → **1起動1本** (`p5_import_anims.py` を複数回) で回避（インポートは保存後にクラッシュするので資産は残る）。

### 2.2 アニメ選択（AnimBP 不使用・C++ で切替）
AnimBP 状態機械は headless 構築が困難なので、C++ Pawn が `SkeletalMeshComponent::PlayAnimation` で
状態に応じ切替（`AAiQuizPawn::SelectAnim`、純関数・テスト対象）。Godot `animation_rig.gd:291-332` 準拠で
**水平速度でなく PlayerY 高さ＋VelY 符号**で決まる：
```
PlayerY < -1            -> Drowning   (マグマ落下)
PlayerY > 0.01 & VelY>0 -> Jump       (上昇)
PlayerY > 0.01 & VelY<=0-> Fall       (下降, =Jump の下降部)
State==Playing          -> Run
それ以外                -> Idle (暫定 =Run)
```

### 2.3 ブロック人間（箱）— `bUseBlockman`（既定 true）
隠した `SK_YBot`（`AlwaysTickPoseAndRefreshBones` でポーズ源として tick 継続）の各ボーン区間に
**色付き箱(StaticMeshComponent)** を毎tick配置（`GBlockmanSegs` 13区間）。`Box.SetWorldLocationAndRotation`
((A+B)/2, (B-A).Rotation())、scale=(len, 太さ, 太さ)/100。色は P1 パレット（body/head/limb、`player_controller.gd:8-10`）を
`M_Blockman`(Color param) の MID で。`bUseBlockman=false` で Mixamo メッシュ直表示(5a)に切替可。
> Godot の 26関節・authored offset の完全移植（手指・死亡爆散）は後続。現状は主要ボーン区間の箱で blocky な見た目を再現。

---

## 3. 検証

### 3.1 無描画オートメーションテスト（`-NullRHI`、緑）
- `AiQuiz.StateMachine.CoreTransitions`（Phase 2）
- `AiQuiz.Pawn.CoordsAndAnim`（Phase 4/5）:
  - 座標: rest=(0,0,-120)、**右ドア(PlayerX=-3.5)→UE +Y=+350**、左ドア→ -350、apex Z=床+136
  - **フルチェーン: SetInput(-1)=D/Right → PlayerX 減少 → UE +Y**（符号トラップを機械検証）
  - アニメ選択ラダー（Run/Idle/Jump/Fall/Drowning）

### 3.2 スクリーンショット（実ビューポート）
- `p5_runpose.png` Mixamo 走行 / `p5_jumppose.png` 踏切 / `p5_fallpose.png` 空中（5a）
- `p5_bm_ok.png` ブロック人間（箱）走行（5b プロトタイプ＝C++ と同一ロジック）
- いずれも 180cm・足元が床(-120)・+X 前方・ベルト上

### 3.3 実機ランタイム（`-game`）
`Auto-start → Countdown → (約3.7s) → Playing` がクラッシュ無しで完了。ブロック人間構築(13箱+MID)・
毎tickソケット読み・アニメ駆動が正常。

---

## 4. 再現コマンド
```powershell
# ビルド（エディタは閉じておく）
& "G:\UE_5.7\Engine\Build\BatchFiles\Build.bat" AiQuizEditor Win64 Development `
  -Project="C:\AIQUIZ\AIQUIZ-Unreal\AiQuiz.uproject" -WaitMutex -NoHotReloadFromIDE
# 無描画テスト
& "G:\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" "...\AiQuiz.uproject" -NullRHI -unattended `
  -ExecCmds="Automation RunTests AiQuiz" -TestExit="Automation Test Queue Empty"
# 実機（FPS。PIEは F8 でeject→3人称でブロック人間を観察可）
& "G:\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" "...\AiQuiz.uproject" /Game/AiQuiz/Maps/L_Game -game
```
> ⚠ ヘッドレス作業後は必ず `Get-Process UnrealEditor*` を確認・停止（uasset ロック回避）。

---

## 5. 生成・変更物
- 新規: `Source/AiQuiz/AiQuizPawn.{h,cpp}`（Pawn本体）、`AiQuizPawnTest.cpp`（座標/符号/アニメ検証）
- 変更: `AiQuizTypes.h`（`EAiQuizAnim`）、`AiQuiz.Build.cs`（InputCore）、
  `AiQuizGameModeBase.{h,cpp}`（bAutoStartInPIE / BeginPlay 自動StartRound / DefaultPawnClass）
- 変更: `Content/AiQuiz/Core/BP_AiQuizGameMode.uasset`（DefaultPawnClass→AAiQuizPawn）
- 新規: `Content/AiQuiz/Character/`（SK_YBot, Skeleton, A_Run/Jump/Drown, M_Blockman, MI_BM_*, Alpha mats）
- dev: `Saved/peace3/p4_wire_pawn.py, p5_import*.py, p5_probe_mesh.py, p5_blockman.py, p5_bones.py`

---

## 6. 次（Phase 6 以降 / 仕上げ）
- **Phase 6**: クイズ壁（Cube＋TextRender＋プーリング）。Pawn は完成済みなので壁を出すと衝突→判定が即動く
  （GameMode は既に `GetWallWorldZ`/`CheckPlayerDoor`/`ResolveCollision` を持つ）。壁 UE_X(i)=100*(GetWallWorldZ(i)-PlayerWorldZ)。
- 仕上げ: マウスルック、Idle 専用クリップ、ブロック人間の authored-offset 完全移植＋手指、死亡ラグドール/爆散（§5.3）、
  FPS で自分の体を隠す/3人称デバッグカメラ、run の再生レートを `ActiveWallSpeed/3.5` で可変（player_controller.gd:622-628）。
