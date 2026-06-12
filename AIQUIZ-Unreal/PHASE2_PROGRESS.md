# AIQUIZ Unreal移植 — Phase 2 完了メモ（状態機械・無描画）

最終更新: 2026-06-12 (GMT+9)
担当フェーズ: **Phase 2 — 状態機械（無描画）BP_AiQuizGameMode**
全体計画: `C:\Users\kykat\.claude\plans\godot-unrealengin-effervescent-lecun.md`

---

## 0. 結論

Phase 2（状態機械・無描画）は **完了・検証済み**。コア状態機械は **C++** で実装し
（`AAiQuizGameModeBase`）、PIE/MCP/レンダリングに依存しない **C++ オートメーションテスト**で
Godot 原作（`game_state.gd`）との一致を機械的に証明した。状態機械はプロジェクトの
実 GameMode として `L_Game` に配線済み。

| Phase | 内容 | 状態 |
|---|---|---|
| 0 | UE5.7 プロジェクト＋Unreal MCP | ✅ 完了 |
| 1 | データ（DT_QuizBank） | ✅ 完了 |
| **2** | **状態機械（無描画）** | ✅ **完了（本メモ）** |
| 3 | ステージ＋スクロール（マグマ/コンベア/フォグ） | ✅ 完了 |
| 4 | Pawn＋カメラ＋入力（仮Box） | 🔧 作業中（`PHASE4_PROGRESS.md`） |
| 5〜10 | ブロック人間／クイズ壁／フルループ／PSX／仕上げ／パッケージ | 未着手 |

---

## 1. 方針転換：BPオンリー → ハイブリッド（ロジック=C++ / 見た目=BP）

当初計画は「Blueprintオンリー」だったが、Phase 4 で MCP ブリッジによる BP グラフ自動構築が
クラッシュ多発（`PHASE4_PROGRESS.md` §1.1 参照）。状態機械のような数式中心ロジックを巨大な
BP EventGraph で組むのは脆く検証も困難なため、**コア状態機械を C++ に移した**。

- ロジック（状態機械・物理・判定・動的速度・DataTable抽出）= **C++**（`AAiQuizGameModeBase`）
- 見た目・UI・コンテンツ（マテリアル/UMG/アクタ配置/Pawn見た目）= **Blueprint**

ゲーム本体の大半は引き続き BP で組む。C++ は editor ツールではなくゲーム本体に入るが、
ロジックの一点豪華主義であり、将来のオンライン/AIストリーミング（計画 §9-9）にも繋がる。
**ロックインは無い**（後から C++ を増減可能）。

### `DA_GameTuning` は作らない（判断）
計画では別途 `DA_GameTuning`(Data Asset) を挙げていたが、全チューニング定数は
`AAiQuizGameModeBase` の `UPROPERTY(EditDefaultsOnly)` として保持し、`BP_AiQuizGameMode`
のクラスデフォルトで上書きできる。単一の正典（C++）に集約する方が良いと判断し、別資産は
作らない。値は `game_tuning.gd` / `game_state.gd` と 1:1 で突合済み（§3）。

---

## 2. このフェーズで行ったこと

### 2.1 忠実性バグ修正：側面落下 → マグマ死（`AiQuizGameModeBase.cpp::UpdatePlaying`）
従来の C++ は `PlayerX` を ±6.5 にハードクランプし `PlayerY>=0` を常時クランプしていたため、
**プレイヤーが絶対に落下できず**、Godot のマグマ死（`game_state.gd:797 player_y<-8.0`）を
再現できていなかった。Godot は意図的に横クランプを撤廃している
（`game_state.gd:776 "Removed clamp to allow falling off sides"`）。

修正内容:
- 横移動のハードクランプを撤廃（`PlayerX += InputAxisX * PlayerSpeed * Dt`）。
- 床判定 `bOverFloor = |PlayerX| <= FloorHalfWidth(12)` を追加。床外では着地スナップせず落下継続。
- `PlayerY < MagmaDeathY(-8)` で `DoGameOver(Magma)`。
- 壁ヒット時に `PlayerWorldZ` をクランプ（`game_state.gd:899` のクリップ防止）。
- 新規 Tuning 定数: `FloorHalfWidth=12`, `FloorBackZ=-12.5`, `MagmaDeathY=-8`。
- 新規 enum `EAiQuizOverReason { None, WrongDoor, Wall, Magma }`（`AiQuizTypes.h`）と
  `LastOverReason`(BlueprintReadOnly)。Godot のゲームオーバー文言（マグマ/不正解/壁）の
  HUD マッピング用。C++ には非ASCIIリテラルを置かない方針を維持。

### 2.2 テスト用シーム：`StartRoundWithQuizzes(InQuizzes, Count)`
DataTable とシャッフルに依存せず、決定論的なクイズ列でラウンドを開始する BlueprintCallable を
追加。リセット処理は `ResetRoundState()` に抽出して `StartRound` と共有。オートメーション
テストとデバッグメニューの両方で使える。

### 2.3 無描画オートメーションテスト：`AiQuizStateMachineTest.cpp`
`IMPLEMENT_SIMPLE_AUTOMATION_TEST(AiQuiz.StateMachine.CoreTransitions)`。`NewObject` した
GameMode を `SetInput`+`TestStep`(dt=1/60) で駆動し、状態遷移をアサート。PIE もレンダリングも
DataTable も不要（`-NullRHI`）。検証シナリオ:

| シナリオ | 期待 | 結果 |
|---|---|---|
| A: Menu→Countdown→Playing | StartRound で Countdown、3秒後 Playing。初速 28/(4+3.5)=3.733 | ✅ |
| B: 正解継続→クリア | 正解ドア(+3.5)で stop せず Playing 継続、3問でスコア3→Clear | ✅ |
| C: 不正解ドア | 逆ドア(-3.5)で GameOver, reason=WrongDoor, スコア据え置き | ✅ |
| D: 柱（ドア間） | x=0 で GameOver, reason=Wall | ✅ |
| E: 側面落下 | x=13(>12) で落下→ GameOver, reason=Magma | ✅ |
| F: ジャンプ弧 | v=7,g=18 の60fps Euler 頂点≒1.303m（連続解1.361の~4%下）、着地で y=0 | ✅ |

### 2.4 GameMode を C++ 状態機械へリペアレント
`BP_AiQuizGameMode` は従来 **素の `GameModeBase`** 派生（`p4_make_gamemode.py`）で、C++ 状態機械に
繋がっていなかった。これを **`AAiQuizGameModeBase`** へリペアレント（`p2_reparent_gamemode.py`）。
`DefaultPawnClass=BP_AiQuizPawn` は保持。これで配線の鎖が完成:

```
L_Game (GameModeOverride) → BP_AiQuizGameMode → [親] AAiQuizGameModeBase (C++状態機械) → [DefaultPawn] BP_AiQuizPawn
```

---

## 3. 定数突合（Godot ↔ C++、すべて一致）

| 定数 | Godot | C++ | 出典 |
|---|---|---|---|
| GRAVITY | 18.0 | Gravity 18.0 | game_state.gd:130 |
| JUMP_FORCE | 7.0 | JumpForce 7.0 | game_state.gd:131 |
| player_speed | 7.6 | PlayerSpeed 7.6 | game_tuning.gd:6 |
| FLOOR_HALF_WIDTH | 12.0 | FloorHalfWidth 12.0 | game_state.gd:132 |
| FLOOR_BACK_Z | -12.5 | FloorBackZ -12.5 | game_state.gd:133 |
| マグマ死 Y | -8.0 | MagmaDeathY -8.0 | game_state.gd:797 |
| wall_start_z | 22.0 | WallStartZ 22.0 | game_tuning.gd:9 |
| wall_spacing | 30.0 | WallSpacing 30.0 | game_tuning.gd:14 |
| 判定オフセット | -0.4 | HitOffsetZ 0.4 | game_state.gd:894 |
| 2択ドア中心 | left 3.5 / right -3.5 | {3.5,-3.5} | game_tuning.gd:17-18 |
| 2択半幅 | 1.8 | 1.8 | game_tuning.gd:15 |
| 4択ドア中心 | [-5.8,-1.95,1.95,5.8] | 同 | game_tuning.gd:20 |
| 4択半幅 | 1.45 | 1.45 | game_tuning.gd:21 |
| 速度clamp | [1.0,8.0] | [1.0,8.0] | game_tuning.gd:11-12 |
| 動的速度 | 28/(t+3.5)*stage_factor | 同 | game_state.gd:566-604 |
| stage_factor | 1+clamp(i/9,0,1)*0.15 | 同 | game_state.gd:596-597 |

注: 軸/符号（D/Right が原作の"右"ドアへ）と m↔cm(UU=100) の SetActorLocation 反映は **Phase 4**
（Pawn の可視化・入力）で目視確認する。Phase 2 はロジック（メートル空間）のみを対象。

---

## 4. 再現コマンド（インフラ）

```powershell
# C++ リビルド（ヘッダ変更時は UHT 込み）
& "G:\UE_5.7\Engine\Build\BatchFiles\Build.bat" AiQuizEditor Win64 Development `
  -Project="C:\AIQUIZ\AIQUIZ-Unreal\AiQuiz.uproject" -WaitMutex -NoHotReloadFromIDE

# 無描画オートメーションテスト
& "G:\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" "C:\AIQUIZ\AIQUIZ-Unreal\AiQuiz.uproject" `
  -NullRHI -unattended -nopause -nosplash -nosound `
  -ExecCmds="Automation RunTests AiQuiz.StateMachine.CoreTransitions" `
  -TestExit="Automation Test Queue Empty" -abslog="...\Saved\peace3\p2_test.log"
# 期待: ログに  Test Completed. Result={Success}

# GameMode リペアレント / 配線検証（ヘッドレス Python コミットレット）
& "G:\UE_5.7\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" "...\AiQuiz.uproject" `
  -run=pythonscript -script="...\Saved\peace3\p2_reparent_gamemode.py" -unattended -NullRHI
& "G:\UE_5.7\...\UnrealEditor-Cmd.exe" "...\AiQuiz.uproject" `
  -run=pythonscript -script="...\Saved\peace3\p2_verify_chain.py" -unattended -NullRHI
```

### ハマりどころ
- **ファイル保存の Error Code 32（共有違反）**: ヘッドレス実行が Python 例外で異常終了すると
  `UnrealEditor.exe`(+`CrashReportClientEditor`) がゾンビ化し uasset をロックし続ける。
  次の保存が `MoveFile ... Error Code 32` で失敗する。→ `Stop-Process` で残骸を掃除してから再実行。
  **作業後は必ず `Get-Process UnrealEditor*` を確認して掃除する。**
- コミットレットでは `compile_blueprint` が dirty を立てないことがある → `save_asset(path, False)`
  で強制保存（`only_if_is_dirty=False`）。
- `BlueprintGeneratedClass.get_super_class()` / `Blueprint.parent_class` は Python 非公開。
  親確認は `isinstance(cdo, unreal.AiQuizGameModeBase)` ＋ C++ 由来プロパティ読みで行う。

---

## 5. 生成・変更物（このフェーズ）

- 変更: `Source/AiQuiz/AiQuizTypes.h`（`EAiQuizOverReason` 追加）
- 変更: `Source/AiQuiz/AiQuizGameModeBase.h`（Floor/Magma 定数・`LastOverReason`・
  `StartRoundWithQuizzes`・`ResetRoundState`・`DoGameOver(Reason)`）
- 変更: `Source/AiQuiz/AiQuizGameModeBase.cpp`（UpdatePlaying のマグマ死実装・リセット抽出）
- 新規: `Source/AiQuiz/AiQuizStateMachineTest.cpp`（無描画オートメーションテスト 6 シナリオ）
- 変更: `Content/AiQuiz/Core/BP_AiQuizGameMode.uasset`（親を C++ 状態機械へリペアレント）
- 新規(dev): `Saved/peace3/p2_reparent_gamemode.py`, `p2_verify_chain.py`
- ログ: `Saved/peace3/p2_build.log`, `p2_test.log`, `p2_reparent.log`, `p2_verify.log`

---

## 6. 次の作業（Phase 4 へ引き継ぎ）

状態機械は完成したので、Phase 4 では **Pawn が毎 tick `SetInput(AxisX,Jump)` を GameMode に
push し、GameMode の状態（`PlayerX/PlayerY/GetPlayerLocalZ/State`）を読んでアクタ/カメラを
配置**する形に寄せる（現状 `p4_graph.py` は移動ロジックを Pawn 側に持たせる設計だが、
状態機械が C++ GameMode に集約された今は **Pawn は入力 push と可視化に徹する**のが筋）。
ここで初めて 軸/符号（D/Right→原作の"右"）と UU=100 の境界変換を目視確認する（計画 §1.4 の罠）。
