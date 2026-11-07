# Scene Passport — 結果発表アリーナ（両者脱落の結果発表）

```text
SCENE
- intent: 2人対戦で両者脱落したとき、暗転のあとに結果発表（スコアタワー）を行う海上の専用アリーナ。観客とモニター付き
- deliverable: assets/result_arena/result_arena.glb・result_arena_stand.glb・result_arena_layout.json（Godot で使う静的な部品）
- units: metres; axes: right-handed Z-up（Godot = (X, Z, -Y)）
- render: 確認用のみ（EEVEE、1280x720）。ゲームの見た目は Godot の材質（AQS_Painted など）が決める
- dynamic: no — ゲーム用の静的な建物。動き（観客・LED・照明）は Godot 側

HIERARCHY
- シーン ResultArena（他のシーンには触らない）
- RA_EXPORT_Arena: RA_Deck, RA_Lid, RA_WingR, RA_WingL, RA_Masts（アリーナ空間の位置のまま書き出す）
- RA_EXPORT_Stand: RA_Stand, RA_Scoreboard（スタンド空間：前端 y=0、奥へ +y、-Y を向く。GoalStand が 180° 回す）
- RA_Layout: 正面スタンドの確認用の複製（同じメッシュ）と確認用の海の板。書き出さない
- protected existing objects: 既定のシーン Scene（Camera, Cube, Light）には触らない

ASSETS（すべて [BLOCK]：手続き的なビルダー、生成なし）
- A01 RA_Lid    | [BLOCK] | stylized | 円盤 半径 7.0（サドンデスの縦穴と同じ）、上面 z=0 | 原点＝舞台の中心 | 縦穴が開くとき Godot が隠す
- A02 RA_Deck   | [BLOCK] | stylized | 輪 半径 7.0〜12.0（コースの床の半分の幅。サドンデスの水上機が x=12 に横付けする）、
  上面 z=0、外周のスカートは海面（z=-8）の下まで、杭は海底（-128）まで
- A03 RA_Stand  | [BLOCK] | stylized | 幅 26（＋両端のヒレ 0.55）、奥行き 8.6、段は goal_stand_layout.json と同じ（観客が並ぶ）
- A04 RA_Scoreboard | [BLOCK] | stylized | LED 面 12.6 x 5.4（下端 z=3.3、材質 GS_ScoreboardScreen）、看板、左右の照明塔（高さ 16）
- A05 RA_WingR / RA_WingL | [BLOCK] | stylized | 長さ 20、6 列の座席（コースの客席と同じ段）、中心 Godot (±22, 16.5)、舞台の中心を向く
- A06 RA_Masts  | [BLOCK] | blockout+ | 高さ 18 の照明塔 2 本（左右のスタンドのカメラ側の奥）

SHOT
- active camera: 確認用 RA_PreviewCamera ＝ ゲームの結果発表のカメラの最初の姿勢（Godot アリーナ空間 eye (0, 3.2, -10.6)、
  10° 見下ろし、縦の画角 40°）
- foreground: 舞台（フタ・外周）、subject: スコアタワー（Godot が置く）、background: 堀の海・正面スタンドの観客・大型モニター・左右のスタンド

LOOK
- material roles: AQS_Painted（頂点色：白・コバルト・段のグレー・座席）、AQS_NightGlow（夜の灯）、GS_ScoreboardScreen（LED）、GS_SBHeaderSign（看板の画像）
- palette: AIQUIZ STADIUM の palette.json（白・コバルト・P1 オレンジ・P2 青）
- world/background: Godot の空・海・遠景をそのまま使う

LIGHTING
- ゲーム側（太陽・空）。確認レンダーは太陽 1 灯と空の色だけ

ACCEPTANCE
- structural: 書き出す 7 部品が名前どおり 1 つずつ。材質は 4 種以内。LED 面の材質名 GS_ScoreboardScreen。座席 JSON が両スタンド分ある
- visual: ゲームのカメラの構図で、舞台→堀→観客席→モニターが重ならずに読める。左右のスタンドの内側半分が画面の端に入る
```

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-audit-finalize
