# AIQUIZ Unreal移植 — Phase 4 進捗メモ

最終更新: 2026-06-10 22:30 (GMT+9)
担当フェーズ: **Phase 4 — Pawn＋カメラ＋入力（仮Box）⚠ 操作**
全体計画: `C:\Users\kykat\.claude\plans\godot-unrealengin-effervescent-lecun.md`

---

## 0. 全体フェーズの中での位置づけ

| Phase | 内容 | 状態 |
|---|---|---|
| 0 | UE5.7 BPプロジェクト＋Unreal MCP導入 | ✅ 完了 |
| 1 | データ（DT_QuizBank DataTable） | ✅ 完了（`Content/AiQuiz/Data/DT_QuizBank.uasset` 存在） |
| 2 | 状態機械（無描画 BP_AiQuizGameMode） | ✅ **完了**（C++ `AAiQuizGameModeBase`＋無描画オートメーションテスト。`PHASE2_PROGRESS.md` 参照） |
| 3 | ステージ＋スクロール（マグマ/コンベア/フォグ） | ✅ 完了（液体マグマ刷新まで。`L_Game.umap`） |
| **4** | **Pawn＋カメラ＋入力** | ✅ **完了**（C++ `AAiQuizPawn`。`PHASE45_PROGRESS.md` 参照） |
| **5** | **ブロック人間＋アニメ（run/jump/fall）** | ✅ **完了**（Mixamo＋箱人間。`PHASE45_PROGRESS.md`） |
| 6〜10 | クイズ壁／フルループ／PSX／仕上げ／パッケージ | 未着手 |

> **このメモ（PHASE4_PROGRESS.md）は §1.2 の Pawn 内蔵移動アプローチを記録した古い作業ログ。最終的な
> Phase 4/5 の実装と検証は `PHASE45_PROGRESS.md` を正典とすること**（Pawn は C++ 化され、移動ロジックは
> GameMode に集約、入力は直接キーポーリング、ブロック人間は隠しスケルトン＋箱方式）。

> 注（2026-06-12 更新）: Phase2（状態機械）は **完了**。コアは C++ `AAiQuizGameModeBase` に
> 集約され、`BP_AiQuizGameMode` は同クラス派生にリペアレント済み（`PHASE2_PROGRESS.md`）。
> よって Phase4 の Pawn は **解析的運動を自前で持たず**、毎 tick `GameMode::SetInput()` で入力を
> push し、`PlayerX/PlayerY/GetPlayerLocalZ/State` を読んで可視化する形へ寄せること
> （`p4_graph.py` の Pawn 内蔵移動ロジックは状態機械と二重化するので破棄/置換）。

---

## 1. このセッションで完了したこと

### 1.1 UnrealMCPプラグインのC++拡張（BPグラフ自動構築に必須のコマンド追加）
`Plugins/UnrealMCP/Source/UnrealMCP/` に以下を追加・修正し、リビルド成功。

**新規ブリッジコマンド4種**（`UnrealMCPBlueprintNodeCommands.cpp/.h` ＋ `UnrealMCPBridge.cpp` ディスパッチ登録）:
- `add_blueprint_variable_set_node` — 変数Setノード（exec付き）
- `add_blueprint_branch_node` — Branch（IfThenElse）ノード
- `add_blueprint_sequence_node` — Sequenceノード
- `set_blueprint_node_pin_default` — 任意ノードの入力ピンへデフォルト値設定

**クラッシュ修正3件**（いずれもEXCEPTION_ACCESS_VIOLATIONの根本原因）:
1. `HandleAddBlueprintVariable` の Float 型: `PC_Float` → **`PC_Real` + サブカテゴリ `PC_Double`**。
   UE5では float メンバ変数は PC_Real/PC_Double。旧 PC_Float のままだと不正プロパティができ、
   Kismetコンパイル時・アセットシリアライズ時にエディタごとクラッシュしていた。
2. `FindBlueprintByName`（`UnrealMCPCommonUtils.cpp`）: `"/"` 始まりのフルパスをそのまま受理。
   従来は `/Game/Blueprints/` 固定だったため、`/Game/AiQuiz/Pawn/...` を解決できなかった。
3. `MCPServerRunnable.cpp` 受信バッファ: `Recv(Buffer, sizeof(Buffer)-1, ...)` に修正。
   末尾 `Buffer[BytesRead]='\0'` のオフバイワン回避。

**その他**: `connect_blueprint_nodes` で接続時に disabled なゴーストイベントノード
（自動配置される BeginPlay/Tick テンプレ）を Enabled に昇格。

> ⚠ **既知の地雷**: MCPの `compile_blueprint` コマンドは別箇所で
> `FKismetEditorUtilities::CompileBlueprint` を裸呼びしておりクラッシュする
> (`UnrealMCPBlueprintCommands.cpp:845`)。**コンパイルはMCP経由を使わず、
> Python側 `unreal.BlueprintEditorLibrary.compile_blueprint(bp)` を使うこと。**

### 1.2 BP_AiQuizPawn の作成（✅ 完了・保存済み）
パス: **`/Game/AiQuiz/Pawn/BP_AiQuizPawn`**（親=Pawn）
- `BodyBox`: StaticMeshComponent = `/Engine/BasicShapes/Cube`、スケール `(0.7, 0.7, 2.4)`
- `FpsCamera`: CameraComponent、相対位置 `(0,0,120)`、FOV `71.4`
- 変数（Float×4）: `AxisX`, `VelY`, `PlayerX`, `PlayerY`
- 生成スクリプト: `Saved/peace3/p4_make_pawn.py`（SubobjectDataSubsystem経由でコンポーネント追加→compile→save）

---

## 2. 作業中（中断地点）

### 2.1 移動ロジックのBPグラフ構築 🔧 **未完了**
スクリプト: **`Saved/peace3/p4_graph.py`**
- Tick から解析的運動（Godot `game_state.gd::_update_playing` 1Pブランチ移植）を組む。
- ノード約50・接続約80を MCPブリッジ経由で自動投入する設計。
- **状態**: Pawn再生成までは走ったが、グラフ投入の本実行が**ユーザー操作で中断**。グラフはまだ入っていない。
- 永続TCP接続＋リクエスト/レスポンス・ロックステップ化＋タイムアウト時1回リトライまで実装済み
  （ブリッジは同時1クライアントのみ。コマンド毎の再接続はaccentループと競合してタイムアウトするため）。

**再開コマンド**（エディタ起動・L_Game ロード済みが前提）:
```
python C:\AIQUIZ\AIQUIZ-Unreal\Saved\peace3\p4_make_pawn.py   # Pawnをクリーン再生成
python C:\AIQUIZ\AIQUIZ-Unreal\Saved\peace3\p4_graph.py       # 移動グラフ投入
```
投入後は Python で compile＋save すること:
```
python C:\AIQUIZ\AIQUIZ-Unreal\Saved\peace3\ue_run.py --stmt "import unreal; p='/Game/AiQuiz/Pawn/BP_AiQuizPawn'; bp=unreal.EditorAssetLibrary.load_asset(p); unreal.BlueprintEditorLibrary.compile_blueprint(bp); unreal.EditorAssetLibrary.save_asset(p)"
```

### 2.2 グラフのロジック仕様（p4_graph.py が組む内容）
Godot定数を1:1移植（`game_state.gd` 確認済み）:
- `AxisX`: A/Left→ +1、D/Right→ -1（入力アセット未使用、PlayerControllerのキー直ポーリング）
- `PlayerX += AxisX * 7.6 * dt`（player_speed=7.6）
- ジャンプ: SpaceBar **just pressed** かつ `PlayerY<=0` かつ `|PlayerX|<=12` → `VelY=7.0`（JUMP_FORCE）
- 重力: `VelY -= 18.0 * dt`（GRAVITY）、`PlayerY += VelY * dt`
- 着地: `PlayerY<=0 && |PlayerX|<=12` → `PlayerY=0, VelY=0`（FLOOR_HALF_WIDTH=12）
- マグマ死: `PlayerY < -8.0` → リスポーン（PlayerX=0, PlayerY=0, VelY=0）
- アクタ反映: `SetActorLocation(X=-800, Y=-100*PlayerX, Z=100*PlayerY)`
  - 座標対応: **Godot Z→UE X（前後）／ Godot X→UE Y（左右）／ Godot Y→UE Z（上下）**、UU=100
  - ⚠ 符号注意: Godotは D/Right で `axis.x -= 1`。本グラフは Y に `-100*PlayerX` を掛けて辻褄合わせ。
    **PIEで「D/Rightが原作の"右"ドアへ動く」かを必ず目視確認**（計画書 §1.4 の罠）。
  - ⚠ X=-800固定とベルト中心UE(400,0,-130)・カメラ位置の整合は **PIEで要確認**（暫定値）。

---

## 3. 残タスク（Phase 4 完了まで）

1. `p4_graph.py` を実行して移動グラフを投入し、compile＋save。
2. **BP_AiQuizGameMode** を作成し `DefaultPawnClass = BP_AiQuizPawn`。
3. `L_Game` の WorldSettings に GameModeOverride を設定。
4. `PlayerStart` を `(-800, 0, 0)` 付近へ配置（Pawnが自動Possessされるよう）。
5. **PIE検証**（スクショ取得）:
   - 横速7.6で左右移動、ジャンプ弧（g18/v7、頂点≒0.78m・約0.78s滞空）
   - **D/Rightが原作の"右"ドア方向**へ動く
   - 側面（|PlayerX|>12）で踏み外し→マグマ落下死→リスポーン
6. Godot原作とのA/B比較（`Godot_v4.6.3-stable_win64.exe` で `AIQUIZ-Godot` 起動、並走）。

---

## 4. インフラ／ツールチェーン（重要・再利用）

| ツール | パス | 用途 |
|---|---|---|
| UE Python Remote Exec | `Saved/peace3/ue_run.py` | `.py`送信 or `--stmt`。multicast `239.0.0.1:6766`。`bRemoteExecution=True`（DefaultEngine.ini）|
| MCPブリッジ直叩き | `Saved/peace3/mcp_call.py` | TCP `127.0.0.1:55557` に直接コマンド。`--file <batch.json>` 対応。新コマンドをMCPツール定義更新なしで叩ける |
| ビューポート撮影 | `Saved/peace3/vshot.py` ＋ `cam_pose.txt` | `take_high_res_screenshot` |
| プラグインビルド | `G:\UE_5.7\Engine\Build\BatchFiles\Build.bat AiQuizEditor Win64 Development -Project="C:\AIQUIZ\AIQUIZ-Unreal\AiQuiz.uproject" -WaitMutex -NoHotReloadFromIDE` | C++プラグイン変更後（~10–20秒、incremental）|
| エディタ起動 | `G:\UE_5.7\Engine\Binaries\Win64\UnrealEditor.exe "C:\AIQUIZ\AIQUIZ-Unreal\AiQuiz.uproject"` | プラグイン変更時は要再起動 |

**運用ループ（C++プラグイン変更時）**: 保存→`quit_editor()`→Build.bat→エディタ再起動→Remote Exec接続待ち（15秒間隔ポーリング）→`L_Game`ロード→作業。

**ハマりどころ**:
- BPノード作成系コマンドの直後は、ブリッジが応答後に接続を切る挙動（"Client disconnected (zero bytes)"）。
  → `p4_graph.py` は永続接続＋ロックステップで対処済み。
- 古い接続が `CLOSE_WAIT`/`FIN_WAIT2` で残ることがある → エディタ再起動でリセット。
- `add_component_to_blueprint`（MCP）は内部でcompileを走らせるが、Pawnのコンポーネント追加は
  `p4_make_pawn.py` の SubobjectDataSubsystem 方式の方が安定。

---

## 5. 移植元の参照（Godot）

- 数式・定数の正典: `AIQUIZ-Godot/scripts/core/game_state.gd`（`_update_playing` L762〜、定数 L130〜135）
  - `GRAVITY=18.0`, `JUMP_FORCE=7.0`, `player_speed=7.6`(game_tuning.gd), `FLOOR_HALF_WIDTH=12.0`,
    `FLOOR_BACK_Z=-12.5`, マグマ死 `player_y<-8.0`
- カメラ: `AIQUIZ-Godot/scripts/world/camera_controller.gd`（FPS eye height=1.2、FOV44、bob `sin(t*1.2)*0.04`）
  - ※現Pawnのカメラは FOV71.4・Z=120 で暫定。原作FOV44に寄せるか要検討。
- ステージ座標: 床上面 Z=-120（Godot FLOOR_TOP_Y=-1.2）。
  - **マグマ面 = Godot `stage_environment.gd:263` magma.position.y=-10.0 → UE Z=-1000**（床上面との落差 8.8m）。
  - 2026-06-12 修正①: マグマが Z=-360（落差2.4m）で浅くステージが浸かって見えたため Z=-1000 へ降下。
    陽炎(Stage_HeatHaze)も同 delta(-640)で -150→-790 へ。`Saved/peace3/p3_apply_and_shot.py`。
  - **2026-06-12 修正②: Stage_Floor が厚み0.2mの薄板で「マグマの上に浮いて」見えたため、Godot
    `FLOOR_THICKNESS=16` に合わせ厚い箱へ。** loc Z -130→-920、scale Z 0.2→16.0（上面-120維持、
    下面-1720）。マグマ(-1000)を突き抜けてマグマから立ち上がる固い台になる。`Saved/peace3/p3_thicken.py`。
    - `M_ConveyorBelt`(_belt_hlsl.txt) は `top_mask=abs(N.z)` で上面=ベルト/側面=`side_color(0.33,0.34,0.35)`
      を出し分けるので、厚くしても側面は灰色の壁として正しく描画される（Godot 同様）。

---

## 6. 生成物一覧（このセッション）

- 修正: `Plugins/UnrealMCP/Source/UnrealMCP/Private/Commands/UnrealMCPBlueprintNodeCommands.cpp`（+4ハンドラ／Float型修正／接続時Enable）
- 修正: `Plugins/UnrealMCP/Source/UnrealMCP/Public/Commands/UnrealMCPBlueprintNodeCommands.h`
- 修正: `Plugins/UnrealMCP/Source/UnrealMCP/Private/UnrealMCPBridge.cpp`（ディスパッチ登録）
- 修正: `Plugins/UnrealMCP/Source/UnrealMCP/Private/Commands/UnrealMCPCommonUtils.cpp`（FindBlueprintフルパス対応）
- 修正: `Plugins/UnrealMCP/Source/UnrealMCP/Private/MCPServerRunnable.cpp`（バッファ修正）
- 新規: `Saved/peace3/mcp_call.py`（ブリッジ直叩きクライアント）
- 新規: `Saved/peace3/p4_make_pawn.py`（Pawn生成・✅実行済み）
- 新規: `Saved/peace3/p4_graph.py`（移動グラフ構築・🔧未実行）
- 新規(中間): `Saved/peace3/p4_batch1.json`, `p4_vars.json`
- 生成物: `/Game/AiQuiz/Pawn/BP_AiQuizPawn`（✅保存済み、コンポーネント＋変数まで。グラフ未投入）
