# AIQUIZ 3D — Unreal Engine 5 移植（Blueprintオンリー縦切りスライス＋Unreal MCP連携）

## Context（背景・目的）

現行の `AIQUIZ-Godot`（Godot 4.6 / GDScript 約61ファイル・22,000行）を **Unreal Engine 5 へ移植し、開発の主軸をUEへ移行**したい。

ゲームの正体は「迫り来る**クイズの壁**の、正解の**ドア**を通り抜けるトレッドミル型（ランナー系）知育3Dアクション」。床と壁が手前（-Z）へ流れ、プレイヤーは左右移動＋ジャンプで正解ドアを抜ける。正解＝ドア爆散して継続、不正解／壁激突／側面マグマ落下＝爆散してゲームオーバー。規定問数クリアでゴール。

**重要な現実**：Godot→UEは機械的移植ではなく**実質フルリライト**。ただしエンジン非依存の資産は再利用できる：クイズJSON、Mixamo FBX、フォント、バックエンド（Cloud Runプロキシ・Firebase・リレーサーバー）、全物理定数・演出を網羅した既存仕様書 `aiquiz_game_specification.md`。

**今回のゴール**：全機能をいきなり作らず、**縦切りスライス**を1本通す。
> メインメニュー → ゲーム開始 → 3Dトレッドミルランナー → 2/4択クイズ壁の出題/スクロール/正誤判定/正解時ドア爆散 → スコア＆進捗 → クリア／ゲームオーバー／リスタート。データはオフラインのみ。PSX調＋コンベア床＋マグマ＋フォグ。
これで「UEで操作感・移植が成立するか」を最小コストで検証し、以降フル機能を積み増す土台を作る。

### 確定した方針（ユーザー回答済み）
- **エンジン**: Unreal Engine 5（PC/Windows優先）
- **UEバージョン**: **5.7 を推奨**（Unreal MCP連携を最大化。最新の編集系MCPは5.7対応が充実）。5.5も導入済みで、MCP/プラグインが不安定な場合の安定版フォールバック。
- **スコープ**: 縦切りスライス
- **実装方式**: **Blueprintのみ**（C++/Visual Studio不要。反復最速）。※後からC++追加はいつでも可能でロックインは無い。将来のオンライン/AIストリーミングはプラグインか薄いC++で対応。
- **キャラクター**: **ブロック人間（箱の見た目）＋Mixamoアニメ＋死亡爆散を最初から再現**。BPオンリーでは「箱をスキニングしたスケルタルメッシュ」方式が素直（§4）。
- **Unreal MCP連携**: **あり**（godot-aiと同様に、私がUEエディタをMCP経由で操作してBlueprint/アクタ/マテリアル/DataTable等を構築する。§2）。

---

## 1. 全体アーキテクチャ（Blueprintオンリー）

### 1.1 Blueprint資産構成
ゲームロジックは全てBlueprint。Godotで「スクリプトのアルゴリズム」だった物はBP関数/EventGraphへ、「`.tscn`/`Label3D`/`Control`/マテリアル」だった物はBPアクタ/UMG/マテリアルへ。
- **BP_AiQuizGameMode**（GameMode BP, Gameマップ）：状態機械の所有者。EventTick→`UpdatePlaying`等の関数を呼ぶ。
- **BP_AiQuizGameInstance**（GameInstance BP）：レベル遷移（メニュー→ゲーム）を跨いで保持。選択中の教科/学年/難易度、クイズ用DataTable参照、スコア等。※UGameInstanceSubsystemはC++専用なので、BPオンリーではGameInstance BPで代替。
- **BP_AiQuizPawn**（Pawn BP）：プレイヤー。CharacterMovement不使用、解析的運動。Camera Component内包。
- **BP_AiQuizPlayerController**：Enhanced Input処理。
- **BP_QuizWall**（Actor BP）：梁/柱/ドアのStaticMeshComponent＋TextRenderでラベル＋判定＋爆散。
- **BP_Stage**（Actor BP）：床/コンベア/マグマ＋`SetScrollZ`。
- **ABP_Blockman**（Animation BP）：idle/run/jump/fallのステートマシン（§4）。
- **WBP_MainMenu / WBP_GameplayHUD / WBP_GameOver**（UMG）。
- **DA_GameTuning**（Data Asset, BP）or **S_GameTuning**（BP Struct定数）：仕様書の全定数。
- **マテリアル**：`M_PSX_Surface`・`PP_PSX`・`M_ConveyorFloor`・`M_Magma`（マテリアルエディタ＝ノードベース。BP/C++に非依存）。`MPC_PSX`（Material Parameter Collection）。
- **Enhanced Input資産**：`IMC_Default`・`IA_MoveX`・`IA_Jump`・`IA_Restart`・`IA_Pause`。
- **イベント連携**：Godotのsignalは **Event Dispatcher**（`OnStateChanged/OnQuizLoaded/OnCorrect/OnWrong/OnCleared`）で。

### 1.2 プロジェクト構成
- 新規プロジェクト **`C:\AIQUIZ\AIQUIZ-Unreal\`**（既存Godotと並ぶ兄弟フォルダ）。
- UE 5.7 / Games→Blank / **Blueprint** / スターターコンテンツ無し / 名称 `AiQuiz`。
- `C:\AIQUIZ\.gitignore` に追加：`AIQUIZ-Unreal/Intermediate|DerivedDataCache|Saved/`（BPオンリーなら Binaries/.vs は基本不要。MCPのC++プラグイン導入時は `Binaries|Intermediate` も）。
- Contentフォルダ構成：`Content/AiQuiz/{Core, Pawn, World, Character, UI, Data, Materials, Input, Maps}`。
- `Menu` / `Game` の2マップ。

### 1.3 トレッドミルの実装モデル（最重要・最初に固める）
**Godotの実体**：ワールドは動かない。単一float `world_scroll_z += active_wall_speed * dt`。全ては「ワールド座標 − world_scroll_z」で描画：
- 壁：`wall.z = (wall_start_z + index*wall_spacing) − world_scroll_z`
- 床：メッシュ固定。**マテリアルの `ScrollZ` だけ**を進めてベルトをパン
- プレイヤー：`player_z` も同速で進み、表示は `player_local_z = player_z − world_scroll_z`。当たり判定は**ワールド座標**で `player_z >= wall_z − 0.4`

**UE方針：このモデルをそのまま移植。** ワールドルートや床メッシュは動かさない。
- `WorldScrollZ`（float変数）。毎tick、プールした壁アクタ（≤7）を `(WallZ − WorldScrollZ)` に再配置（安価）。
- 床スクロール＝**マテリアルのパンのみ**：MIDの `Set Scalar Parameter Value ("ScrollZ", WorldScrollZ)`。
- Pawnは二重表現：`PlayerWorldZ` 保持、表示Z=`(PlayerWorldZ − WorldScrollZ)*UU`。当たりはワールド座標で比較。

### 1.4 単位系・座標軸（一度だけ決めて固定）
- Godotはメートル、UEはセンチ。**`UU = 100`**、乗算は `SetActorLocation` の境界でのみ。BP内部の状態変数は全てメートルのまま（仕様書と1:1）。
- 軸対応：**Godot Z → UE X（前後）／ Godot X → UE Y（左右）／ Godot Y → UE Z（上下）**。BPマクロ/純関数 `GodotToUE(gx,gy,gz)→Vector` を1つ用意。
- **符号の罠（実コード確認済み）**：Godotは A/Left で `axis.x += 1`、D/Right で `axis.x -= 1`、ドアXも反転（`left_door_x=3.5, right_door_x=-3.5`）。UEマッピング確定後、「**D/Rightで原作が"右"と呼ぶドアへ動く**」を必ず目視確認。

---

## 2. Unreal MCP 連携

godot-aiと同様に、UEエディタをMCP経由で操作し、Blueprint・アクタ・マテリアル・DataTable・Enhanced Input・UMG・Niagaraを**自動構築/編集**できるようにする。**BPオンリーのこのプロジェクトでは特に有効**（コードを書く代わりにMCPでBP資産を組める）。

### 2.1 候補と推奨
現在この環境にUnreal MCPは未接続（godot-aiのみ稼働）。新規導入する。主要候補：

| MCPサーバー | 形態 / 対応UE | 強み |
|---|---|---|
| [remiphilippe/mcp-unreal](https://github.com/remiphilippe/mcp-unreal) | Goバイナリ（依存ゼロ）/ **UE5.7** | ヘッドレスbuild&test・Blueprint編集・アクタ操作・プロシージャルメッシュ・UE APIドキュメント検索 |
| [ChiR24/Unreal_mcp](https://github.com/ChiR24/Unreal_mcp) | TypeScript＋C++ Automation Bridge | **280コマンド/13カテゴリ**（Blueprint・Material・Niagara・StateTree・DataTable・プロファイル）— 本計画の全システムを網羅 |
| [chongdashu/unreal-mcp](https://github.com/chongdashu/unreal-mcp) | Python / Claude等 | コミュニティ実績豊富。Blueprint・アクタ・エディタ制御 |
| [mirno-ehf/ue5-mcp](https://github.com/mirno-ehf/ue5-mcp) | UEプラグイン＋MCPラッパ / **Claude Code向け明記** | プレーン英語でBlueprint編集。軽量 |

**推奨**：UE5.7で進めるなら **remiphilippe/mcp-unreal**（5.7対応明記＋ヘッドレスbuild/test＋APIドキュメント検索が移植検証に有用）を第一候補、機能網羅で **ChiR24/Unreal_mcp** を対抗。Phase 0で1〜2個を実際に接続し、(a)対象UEバージョン対応、(b)Blueprint新規作成/編集とDataTable/Material操作の可否、(c)メンテ状況 を確認して1つに確定する。

### 2.2 セットアップ手順（Phase 0で実施）
1. 選定MCPのリポジトリを取得し、**ソースを確認**（第三者がエディタを操作する。OSSなのでレビュー可能）。
2. UEプラグイン部分を `AIQUIZ-Unreal/Plugins/` に配置 or Fab/Marketplace版を導入。多くは UEの **Python Editor Script Plugin** か **Remote Control API**、または専用C++ブリッジプラグインを使う。
   - ※このブリッジが内部でC++を使っても**editorツール側**であり、ゲーム本体（BPオンリー）には影響しない。
3. MCPサーバーを起動（Goバイナリ/Python/Node）。
4. Claude Codeに登録：`claude mcp add unreal-ai -- <サーバ起動コマンド>`（godot-aiと同じ要領。`C:\AIQUIZ\.mcp.json` への記載でも可）。
5. 接続確認：エディタ状態取得・テスト用アクタ生成・スクショ取得が通ること。

### 2.3 ワークフローでの使い方
- Blueprintクラス/変数/関数/コンポーネント/ノードグラフの生成・編集、アクタ配置、マテリアル/Material Instance作成、DataTableインポート、Enhanced Input資産作成、PIE実行・スクショ・ログ取得を**MCP経由で自動化**。
- 検証ループ：MCPでエディタ操作 → PIE実行 → スクショ/ログ取得 → 原作Godot（godot-ai MCPで並走）と比較。

### 2.4 注意（安全・BPオンリーとの両立）
- 第三者MCP/エディタプラグインの導入・起動は**あなたの承認を得てから**実施（ローカル開発ツール。ソースはOSS）。
- MCPブリッジのC++プラグインは editor 専用ツールで、**ゲーム本体のBPオンリー方針は維持**される。
- MCPが不安定/未対応な操作は、エディタ手動操作にフォールバック。

---

## 3. システム別マッピング（Godot → UE Blueprint）

| スライス機能 | 移植元（Godot） | UE実装（Blueprint） |
|---|---|---|
| 状態機械 | `scripts/core/game_state.gd`（最重要・1Pブランチのみ） | `BP_AiQuizGameMode`：EventTick→`Update(dt,AxisX,bJump)` 関数群。状態はenum`E_GameState`＋変数 |
| 中央状態 | `game_state.gd` メンバ変数 | GameMode/GameInstanceの変数群：`PlayerX/Y/Z, WorldScrollZ, CurrentWallIndex, Score, ActiveWallSpeed, flash/shake` |
| 定数 | `game_tuning.gd`, `constants.gd`, 仕様書 | `DA_GameTuning`（Data Asset）。値は仕様書から |
| プレイヤー移動 | `player_controller.gd` ＋ `_update_playing` | `BP_AiQuizPawn`（解析的。CharacterMovement不使用） |
| クイズ壁 | `scripts/world/quiz_wall.gd` | `BP_QuizWall`（Cube生成＋TextRender＋判定＋爆散） |
| ステージ | `stage_environment.gd`, `stage_constants.gd` | `BP_Stage`（床/コンベア/マグマ、`SetScrollZ`） |
| データ供給 | `quiz_provider.gd`, `quiz_item.gd` | `BP_AiQuizGameInstance` の `GetQuizzes` 関数＋`DT_QuizBank`（DataTable）＋`S_QuizItem`（BP Struct） |
| カメラ | `camera_controller.gd`（1P） | Pawn上のCamera Component（FPS追従＋bob＋shake＋ゲームオーバーdolly） |
| HUD/メニュー | `gameplay_hud.gd`, `ui/main_menu.tscn` | `WBP_*` ＋ GameMode/GameInstanceのEvent Dispatcher |
| PSX | `addons/psx/shaders/psx*.gdshader(inc)` | `M_PSX_Surface`（頂点スナップ＋アフィンUV：Custom HLSLノード）＋`PP_PSX`（Bayerディザ＋減色） |
| コンベア床 | `shaders/conveyor_belt_floor.gdshader` | `M_ConveyorFloor`（`ScrollZ`で縞パン） |
| マグマ | `shaders/magma.gdshader` | `M_Magma`（ボロノイ亀裂＋4色グラデ＋エミッシブ＋Bloom） |

### 3.1 状態機械（移植の中核）
`game_state.gd` を移植。スライスで使う状態：`MENU, PRELOADING, WAITING_START, COUNTDOWN, PLAYING, CORRECT, GAME_OVER, CLEAR`（`FLYOVER`省略、`GOAL_RACE`除外）。enum `E_GameState`。
- `_update_playing`（1P）：スクロール前進、`player_x += axisX*7.6*dt`、手動重力/ジャンプ（`vel_y -= 18*dt; y += vel_y*dt`、ジャンプで `vel_y=7.0`）、マグマ死 `player_y<-8.0`、壁衝突 `player_z >= wall_z − 0.4` → 判定。
- 判定（`_check_player_door`）：2択 中心±3.5・半幅1.8／4択 `[-5.8,-1.95,1.95,5.8]`・半幅1.45。正解→`score++`・`advance_after_correct`（**停止せずPLAYING継続**）。壁/不正解→`_game_over`（ノックバック`vel_y=JUMP*0.8, vel_z=-12`）。`choice_locked`で二重加点防止。
- `advance_after_correct`→`current_wall_index++`、補充、`load_current_quiz`、`target_count`到達で `clear_game`。
- flash/shakeは毎tick減衰（HUD/カメラが参照）。
- **BP実装の指針**：巨大な単一EventGraphにせず、状態ごとに**関数へ分割**（`UpdatePlaying`/`ResolveCollision`/`AdvanceAfterCorrect`等）。数式は純関数化して可読性確保。

### 3.2 クイズ壁
`quiz_wall.gd` を移植：梁/柱/ドアをCube StaticMeshComponentで生成（寸法は `_build_wall_around_doors`：全幅24、door_top2.38/bottom−2.02、wall_top4.05/bottom−3.15、奥行0.55、ドア1.8×2.2×0.60）。色はMID。選択肢テキスト→ドア毎に **TextRender Component**（`Label3D`対応、`UFont`=NotoSansJP全グリフ、プレイヤー側を向ける）。分数スタック表示は後回し（`"1/2"`インライン）。`SetQuiz` で択数に応じ再構築。正解爆散（`break_door`）＝4×5のCubeアクタ生成→Simulate Physics→Add Impulse→1.5秒後スケール0→Destroy。背面崩壊（`shatter_wall`）＝同パターン（初期は `local_z ≤ -12.5` で非表示＋Destroyのスタブ可）。`game_world.gd::_update_walls` のプーリングをGameMode BPで再現（`MAX_VISIBLE_WALLS(4)`＋バッファ、必要インデックス算出、再配置、背面カル、**アクタプール**）。

### 3.3 ステージ / カメラ / UI / PSX
- **ステージ**（`stage_environment.gd`）：床（幅24・上面Y=−1.2、スライスは固定長160・中心z=4）、コンベア`M_ConveyorFloor`（入力`ScrollZ`のみ）、マグマ平面`M_Magma`（死判定は解析的`player_y<-8.0`なので見た目専用）、濃いフォグ（色`(0.82,0.85,0.90)`、near10→far20、`ExponentialHeightFog`）。
- **カメラ**（`camera_controller.gd`1P）：PLAYING＝目`(player_x, player_y+1.2, player_local_z)`・FOV44・bob`sin(t*1.2)*0.04`・shake。GAME_OVER＝ease-out引き＋減衰shake。
- **UI**：`WBP_GameplayHUD`（問題/選択肢/スコア/進捗/メッセージ/プリロード/ゲームオーバー）、`WBP_MainMenu`（教科・学年・難易度・Start→`OpenLevel(Game)`）、`WBP_GameOver`。Good/Bad評価・履歴（Firebase/解析）は省略。NotoSansJPフォント。データはEvent Dispatcher＋BPゲッターで供給。
- **PSX**：①`M_PSX_Surface`（クリップ空間XY量子化＝WPO＋Custom HLSL、アフィンUV補間、低スペックシェーディング）②`PP_PSX`（PostProcessVolume、4×4 Bayer＋`bit_depth5`減色、ほぼ逐語移植）。着手順は**減色post＋フォグ＋低スペック面が先**、頂点ジッター＋真アフィンは後。`psx_*`は`MPC_PSX`。

---

## 4. キャラクター（ブロック人間）— スケルタルメッシュ方式

ユーザー選択により、プレースホルダではなく**箱の見た目のブロック人間＋Mixamoアニメ＋死亡爆散を最初から再現**。BPオンリーでは per-frameのボーン転写コードを避け、**スキニング済みスケルタルメッシュ**にするのが素直。移植参照：仕様書§5、`emote_blockman_preview.gd`、`player_controller.gd`。

### 4.1 ブロック人間メッシュ（推奨：スケルタルメッシュ化）
- 既存の `assets/animations/Y Bot.fbx`（Mixamoスケルトン）を土台に、**頭/胴/腕/脚を色分けした箱**を各ボーンへリジッドスキニング（Blenderで一度作成）→FBXでUEへインポート＝スケルタルメッシュ＋スケルトン。
- 仕様書§5.1の26関節構成（Pelvis根〜指階層〜つま先、Hat Mount）に対応する箱を配置。色はマテリアルスロット/MID。
- **利点**：MixamoアニメがこのスケルトンでそのままAnimBP再生／リターゲット可能（per-frame転写コード不要）。
- **代替（DCC不使用）**：BPで箱階層をプロシージャル生成し、非表示SkeletalMeshComponentのMixamoアニメから `GetSocketTransform`(bone名) を毎フレーム読んで各箱へ適用（`build_player_skeleton`/`apply_skeleton_pose`相当）。Blender不要だがBPロジックは増える。

### 4.2 アニメーション（`ABP_Blockman`）
- Animation BPのステートマシン：**idle / run / jump / fall** を速度・接地フラグでブレンド。Mixamoの該当FBX（`assets/animations/`）をスケルトンへインポートして使用。
- 仕様書§5.2の「プロシージャル波形」モードはフォールバックとして任意（スライスはMixamo再生で十分）。

### 4.3 死亡爆散（仕様書§5.3）
- スケルタルメッシュに **Physics Asset** を付与。死亡時 `Set Simulate Physics`（ラグドール）で2秒もがき → パーツ分離は **ボーン毎の箱アクタをスポーン**して個別物理化、or ラグドールのままマグマ沈下（Y<−9.2で落下1/20減衰＋Timeline/Tickでスケール0縮小）。初期はラグドール＋沈下で近似、フル分離は後追い可。

---

## 5. クイズデータパイプライン（DataTable方式）

BPのネイティブJSONは弱いので、`offline_bank.json` を **DataTable** 化する（uassetで同梱されパッケージも容易）。
- **S_QuizItem**（User Defined Struct = BP Struct、DataTableの行型）：`Subject, Grade(int), Q(String), C(配列 or C1..C4), A(int), E(String), T(float)`。
- **変換**：一度きりの**devスクリプト**（Python/Node。リポジトリに `sample_quiz.py` 等の実績あり）で、入れ子 `{教科:{学年:[...]}}` を **平坦なJSON配列**（各行に`Name`＋上記フィールド、解説は`e`/`exp`フォールバック、`t`読取）へ展開 → UEで DataTable へインポート（行型=`S_QuizItem`）。出力先 `Content/AiQuiz/Data/DT_QuizBank`。UTF-8厳守。
- **`GetQuizzes(Subject,Grade,Difficulty,Count)`**（GameInstance BP関数）：`Get Data Table Row Names`→該当 教科/学年 行を抽出→正規化（択数2/4・a範囲・非空）→シャッフル→Count件。`_bucket_by_difficulty`/`_harden_distractors`/dedup/ボス並べ替え/`_estimate_seconds`は**後回し（ただし`t`は読む）**。**4→2択削減**（難以外は4択を2択へ）は移植。
- **動的壁速度**（`_recalc_wall_speed`）：`Speed = 28 / (t + 3.5) * stage_factor`、clamp`[1.0,8.0]`、TEN stage_factor=`1 + clamp(index/9,0,1)*0.15`。体感の要なので移植。

---

## 6. フェーズ別実装順序（各フェーズPIE実行可。⚠＝高リスク）

- **Phase 0 — セットアップ＋Unreal MCP**：UE5.7 Blueprintプロジェクト `AiQuiz` 作成。`Menu`/`Game`マップ、`BP_AiQuizGameInstance`、gitignore。**Unreal MCP導入・接続（§2、要承認）**。*検証*：両マップが開く、MCPでエディタ状態取得・テストアクタ生成・スクショが通る。
- **Phase 1 — データ（DataTable）**：`S_QuizItem`、devスクリプトで `offline_bank.json`→`DT_QuizBank` インポート、`GetQuizzes`。*検証*：ログに「算数 grade3: N件、先頭Q=…」が日本語表示。
- **Phase 2 — 状態機械（無描画）**：`BP_AiQuizGameMode`＋`DA_GameTuning`。PLAYING数式を変数のみで実装、ダミー入力で駆動。*検証*：画面デバッグでMENU→…→PLAYING、`player_x`操作で正誤遷移がGodotと一致。
- **Phase 3 — ステージ＋スクロール（グレーボックス）⚠ トレッドミル体感**：`BP_Stage` 灰色床＋最小`M_ConveyorFloor`（`ScrollZ`縞パン）。*検証*：ベルトが状態機械速度で手前へ流れ、床は固定。**`UU`/軸/符号をここで確定**。
- **Phase 4 — Pawn＋カメラ＋入力（仮Box）⚠ 操作**：`BP_AiQuizPawn`（Box）、Enhanced Input、FPS追従カメラ。*検証*：横速7.6・ジャンプ弧（g18/v7）・**D/Rightが原作の"右"ドアへ**、側面落下でマグマ死。
- **Phase 5 — ブロック人間＋AnimBP**：スケルタルメッシュ版ブロック人間（§4.1）＋`ABP_Blockman`（idle/run/jump/fall）。仮Boxを差し替え。*検証*：走り/ジャンプ/落下が見える。
- **Phase 6 — クイズ壁＋判定 ⚠ 判定タイミング**：`BP_QuizWall`（Cube＋TextRender＋NotoSansJP）、`_update_walls`プーリング、`SetQuiz`。正解→非表示＋（初期は）簡易破片、背面→Destroy。*検証*：壁がz=22・間隔30で出現、`player_z>=wall_z−0.4`で判定、正解通過/不正解・激突→ゲームオーバー、`choice_locked`の一度きり加点。
- **Phase 7 — フルループ＋UMG**：`WBP_MainMenu`→Start→`OpenLevel(Game)`、`WBP_GameplayHUD`＋`WBP_GameOver`＋Event Dispatcher、R/Escリスタート、3-2-1カウントダウン。*検証*：端から端まで、10問→クリア、不正解→ゲームオーバー→リトライ/メニュー。
- **Phase 8 — PSX＋マグマ/フォグ**：`PP_PSX`（ディザ/減色）即適用、フォグ、`M_PSX_Surface`（低スペック→ジッター→アフィン）、`M_Magma`。*検証*：Godotスクショと一致、性能劣化なし。
- **Phase 9 — Mixamo仕上げ＋死亡爆散＋破片FX**：Mixamoブレンド調整、死亡ラグドール/パーツ分離＋マグマ沈下（§4.3）、ドア4×5破片バースト・correct-flash/shake・背面壁崩壊（orスタブ維持）。⚠ 剛体数（§9）。
- **Phase 10 — 検証＆パッケージ**：PIE＋Standalone＋Development Windowsパッケージ（エディタの Platforms→Windows→Package、or RunUAT）。パッケージ版でDataTable同梱・日本語表示確認。仕様書と定数を逐一突合。

---

## 7. 再利用資産 & 移植元ファイル（絶対パス）

**そのまま再利用**
- `C:\AIQUIZ\AIQUIZ-Godot\offline_bank.json`（UTF-8・q/c/a/exp/t）→ devスクリプトで `DT_QuizBank` へ
- `assets\curriculum\<教科>\grade_<N>.json`（AI生成フェーズ用。スライスでは任意）
- `resources\fonts\NotoSansJP-*.otf` → `UFont`
- `assets\animations\Y Bot.fbx`（スケルトン土台）＋各Mixamo FBX（idle/run/jump/fall等。Phase 5/9）
- バックエンド（`C:\AIQUIZ\aiquiz-proxy`・Firebase・`C:\AIQUIZ\relay-server`）はエンジン非依存。スライス未使用。

**移植元（読む順）**
- `scripts\core\game_state.gd` — 状態機械＋全ゲーム数式（移植#1）
- `scripts\core\game_tuning.gd` ＋ `constants.gd` — 定数/enum（確認済み）
- `scripts\world\game_world.gd` — メインループ（入力集約・壁spawn/scroll/cull・床/カメラ）
- `scripts\world\quiz_wall.gd` — 壁/ドア組立・ラベル・`break_door`/`shatter_wall`
- `scripts\world\stage_environment.gd` ＋ `stage_constants.gd` — 床/コンベア/マグマ＋`set_scroll_z`
- `scripts\world\camera_controller.gd` — カメラ姿勢
- `scripts\core\quiz_provider.gd` ＋ `quiz_item.gd` — データ供給
- `scripts\ui\emote_blockman_preview.gd` ＋ `scripts\world\player_controller.gd` — ブロック人間生成・ポーズ・死亡爆散
- `addons\psx\shaders\psx.gdshaderinc` ＋ `psx_postprocess.gdshader` ＋ `shaders\conveyor_belt_floor.gdshader` ＋ `shaders\magma.gdshader` — シェーダー移植元
- `scripts\ui\gameplay_hud.gd` ＋ `ui\main_menu.tscn` — UI参照
- `C:\AIQUIZ\aiquiz_game_specification.md` — 定数・演出の正典

---

## 8. 検証方法

- **定数突合**（Godot定数と一致）：gravity18.0・jump7.0・speed7.6・X範囲±6.5・ドア中心/半幅・wall_start_z22・spacing30・判定オフセット−0.4（命中≈z−6）・背面カル−12.5・マグマY<−8.0・床上面−1.2/幅24・VISIBLE_DISTANCE28・MOVE_BUFFER3.5・速度clamp[1,8]・stage_factor1.0→1.15。
- **原作A/B**：`C:\AIQUIZ\Godot_v4.6.3-stable_win64.exe` で `AIQUIZ-Godot` を起動し、UE PIEと並走比較（ベルト速度・壁可視→判定時間・ジャンプ頂点/時間・横断時間・正解継続で減速なし・不正解/激突/落下が全てゲームオーバー＋正しい解説）。`godot-ai` MCPで原作の駆動/スクショ、**`unreal` MCPでUE側の駆動/スクショ/ログ**を取得して突合。
- **データ**：教科/学年ごと先頭問題をログ、日本語描画＋`exp`/`t`読込を確認。
- **ビルド/実行**：エディタPIE → Standalone → `Package Project (Windows)` or `RunUAT BuildCookRun -platform=Win64 -cook -stage -pak`（C++ビルド不要）。

---

## 9. リスク & 注意

1. **トレッドミルモデル（最重要）**：`world_scroll_z` をfloat移植、プール壁を再配置＋床マテリアルをパン。ワールドルート/床メッシュは動かさない。`UU`/軸/符号をPhase 3で先に確定。
2. **m↔cm**：BP内は全てメートル、`SetActorLocation`境界でのみ×100。
3. **軸反転**：Godot A/Left=+X・D/Right=−X・right_door_x負。意図的にマップし目視確認。
4. **BP状態機械の可読性**：巨大EventGraphを避け、状態ごと関数分割＋純関数。コメント/コラプスで整理。
5. **DataTable変換の正しさ**：UTF-8、`e`/`exp`フォールバック、`t`読取、択数2/4検証。変換スクリプトはdevツール（出荷物に非ず）。利点＝uassetなので**パッケージに自動同梱**（生JSONの同梱設定不要）。
6. **キャラ＝スケルタルメッシュ**：箱スキニングはBlenderで一度作成が必要。回避するならプロシージャル＋`GetSocketTransform`読取の代替（BP量増）。
7. **剛体チャーン/爆散性能**：Godotはドア毎~20体・壁崩壊で数十体を毎回生成。UEで素朴に毎フレーム生成/破棄するとヒッチ。壁プール・同時破片上限・短命Niagara・背面崩壊後回し。
8. **PSXアフィン/ジッター忠実度**：マテリアルにCustom HLSL必須。スライスは近似許容、減色postはほぼ逐語移植（見た目の8割）。
9. **将来のオンライン/AI**：純BPだとWebSocketリレー・Gemini SSEは厳しい→プラグインか薄いC++。スライス範囲外で、**後からC++追加可（ロックイン無し）**。
10. **Unreal MCP**：第三者ツール。導入・起動は要承認、ソースレビュー。ブリッジのC++はeditor専用でゲーム本体のBPオンリーに影響しない。未対応操作は手動フォールバック。

---

## 10. スライスで見送るもの（後続フェーズで追加）

オンライン対戦（WebSocketリレー＋スナップショット同期）／AI・Gemini動的生成＋自己最適化＋`QuizDedup`＋Firebase＋カリキュラムプロンプト／2P・Co-op・Goal-Race・Tutorial・Endless／コスメ（帽子・ボブルヘッド）・エモート/ダンス／壁スライドイン合体＋スタートバリア大演出（スライスは3-2-1で代替）／リプレイ／動的床延長・コンベアローラー等／分数スタック描画／難易度バケット・ディストラクタ強化・予測秒ヒューリスティック。

**スライスで残すもの**：コアサイクル・全物理定数・2/4択壁＋正解ドア爆散・動的速度・オフラインバンク・PSX＋コンベア＋マグマ＋フォグ・**ブロック人間（スケルタルメッシュ＋Mixamo）＋死亡爆散**・**Unreal MCP連携**。
