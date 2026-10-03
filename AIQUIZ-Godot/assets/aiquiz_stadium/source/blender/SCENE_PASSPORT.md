# Scene Passport — AIQUIZ STADIUM（Blender 組み立て、v2）

SCENE
- intent: 原本 v1（白い海上桟橋スタジアム、スタンドを横切る三角帆、水平線の街、左右の島、沖の灯台）に近づけて、ゲームにそのまま差し込める部品として作る。床はゲームのベルトコンベア、問題壁はゲームのデザインのまま
- deliverable: `aiquiz_stadium.blend`（部品シーン＋確認シーン）、GLB 5 種（スタンドのブロック・帆の一式・GOAL ゲート・ゴール観客席 B・遠景）、座席と配置の JSON、確認レンダー、build_report.json。Godot への組み込み（stage_environment の stadium style、スタンド・遠景・材質のスクリプト、帆と灯のシェーダー、ゴール観客席と GOAL ゲートの差し替え）
- units: metres; axes: right-handed Z-up。Godot = (X, Z, -Y)
- render: EEVEE, 1600x900, 24fps, frames 1–120（確認用）、Standard の色変換
- dynamic: yes — 確認用のフライオーバー（空撮 → 2P の視点）。帆の風の揺れはゲームのシェーダー（UV2 の重み）で、実機で確認する
- build: ユーザーのライブ Blender 上で `build_stadium.py` を実行する（Higgsfield の Blender 連携 `bl_execute` 経由、手順は README の「作り直し」）。連携が未接続なら作業を止めて接続を依頼し、`--background` のヘッドレス実行で代替しない

HIERARCHY
- collection/object naming: 書き出し `AQS_EXPORT_<部品>`、確認用 `AQS_REVIEW_*`、参照物 `REF_*`（書き出さない）。部品 `AQS_Stand_Bay` / `AQS_Stand_CapStart` / `AQS_Stand_CapEnd`、`AQS_SailRig_R` / `AQS_SailRig_L`、`AQS_GoalGate`、`GS_Stand` / `GS_Scoreboard`、遠景 `AQS_Lighthouse` / `AQS_BG_*`。カメラ `CAM_*`、ライト `LGT_*`
- parent/child relationships: スタンド・帆・ゲート・ゴール観客席は原点に置いて書き出す。遠景はワールドの位置に置いて書き出す（Godot では原点に置くだけ）。確認シーンはリンク複製、帆は確認用の半透過の材質を上書き（object リンク）
- protected existing objects: ライブ Blender で作業する前に、開いているファイルに未保存の作業がないかユーザーに確認する（ビルダーは開いているシーンを空にしてから組み立てる）。ゲームの床・ローラー・側枠・レール・問題壁は変更しない

ASSETS
- A01 観客席ブロック bay / cap_start / cap_end | detailed | 11.7×20×(杭 -17.2〜マスト 12.5)m | 丸いブースと「?」の画面、マスト・ヤード・シュラウド
- A02 帆の一式 R / L | detailed | 8×1.6×6m | 三角帆（Coons 面、縁の弓なり、ふくらみ）、ブーム、灯、トッピングリフト
- A03 GOAL ゲート | detailed | 24.0×1.0×6.35m | 看板に Higgsfield の GOAL テクスチャ
- A04 ゴール観客席 B | detailed | 26×8×(海底 -128〜19.5)m | LED 面は `GS_ScoreboardScreen`
- A05 遠景 | stylized（v3 で原本の絵の密度まで作り込み） | 灯台 81m、島 4、街（1100m・340m）、沖の海、ヨット 6 | 方位と距離は dimensions.json の background
  - 島：ノイズの尾根と谷、岩山（上だけ岩肌・地層）、樹冠で覆う森、ヤシの群れ、水際の岩場、白波の帯、海の中の浅瀬（深さ 4m 以内、ゲームの海の板の下だけ）
  - 街：高層を手前と奥の 2 層（面取り・円筒・先細り・段・ツイン・飾り枠・基壇）、中層、低い街並み 3 列、並木と公園、護岸。外壁 5 種、棟ごとに窓の割り付けをずらす、航空障害灯
  - 沖の海 `AQS_BG_FarSea`：ゲームの海の板（4km 四方）の外側を far まで埋める。内側の縁は海の板の縁に沿わせ 2m 重ねる
- generation: 3D 生成は使わない（寸法とゲームの約束を優先して手続き的に作る）。テクスチャは Higgsfield（GOAL 看板）と手続き（帆の布・ブースの画面・街の外壁）

SHOT
- CAM_2P / CAM_1P（ゲームのカメラ定数）、CAM_Master（原本の空撮に近い高さと角度）、CAM_SailClose、CAM_City、CAM_Goal、CAM_Water、CAM_Overview、CAM_Lighthouse、CAM_Finale、部品の確認カメラ

LOOK
- material roles: 頂点色の塗装（AQS_Painted）、夜の灯（AQS_NightGlow）、ブースの画面（AQS_BoothScreen、発光）、帆の布（AQS_SailFabric、両面・半透過、確認用は Translucent を混ぜる）、街の外壁（AQS_CityFacade_A/B/C、夜の窓）、看板（AQS_GoalBoard / AQS_LighthouseSign / GS_SBHeaderSign）、LED（GS_ScoreboardScreen）
- 遠景（v3）：`AQS_BG_Painted`（島・街の頂点色）、`AQS_CityFacade_A〜E`、`AQS_BG_Sea`（沖の海）。ゲームは霧を使わないので、Godot の `aiquiz_backdrop.gdshader` が距離で空の地平線の色へかすませる（量 = min(0.6, (1-exp(-d/10000)) × 高さで最大 30% 薄く)、水面下はかすませない、沖の海は海の板の縁から 900m かけてかすむ）。確認シーンは同じ式の確認用材質（`*_Review`、object リンク）で撮る。書き出す材質は変えない
- 島の頂点色に地形の凹凸（谷は暗く尾根は明るく）を入れる。ゲームは環境光が強く陰影が浅いため

LIGHTING
- key: ゲームと同じ太陽の向き（前方＝ゴール側、仰角 50°、右 20°）。コースのカメラから見て帆が逆光になり、布が透けて白く光る
- dusk / night: 夕暮れは低い太陽と暖色の空、夜は帆が下ほど明るく光り、マスト頂部・ブームの灯・ブースの画面・街の窓が光る。確認シーンだけブームの下に点光源（影なし）
- color management: Standard（頂点色のパレットをそのまま出す）、露出 0

MOTION
- 24fps / 1–120：CAM_Flyover が空撮から 2P の視点へ。1–10 と 110–120 は静止
- 帆：ゲームのシェーダーで、法線方向のふくらみの呼吸（0.24m、帆ごとに位相）と細かい波。実機の 2 コマの差分で確認

ACCEPTANCE
- structural: 寸法表どおり（ブロック 20m、6段 114席、スタンド内側面 |x|≥27.2、帆の走路側の端 |x|≥28.5・最も低い所が観客の頭より上、揺れの重み、左右のふくらむ向き、LED の材質と UV、ゲートの幅、遠景が far 5000m の内側）
- structural（v3 遠景）：島 60k・街 40k・遠景の合計 180k 以下、海の中の地形は -8m より浅い（海越しに崖が透けない）、海の板の下の島だけ浅瀬がある、沖の海は上向きで内側の縁が海の板の縁に沿う
- visual: CAM_2P / CAM_Master が原本の構成（左右の帆の列、中央左の街、右の灯台、左右の島）に見える。床と問題壁はゲームのまま。
  v3：CAM_IslandL / CAM_IslandR / CAM_City の望遠で、島が森と岩山と水際に、街がガラスの高層ビル群に見え、夕暮れ・夜は空と同じ色でかすむ
- game: 実機の 2P で昼・夕暮れ・夜、GOAL ゲート、ゴール観客席、帆の揺れを確認。関連テストが合格

RESULT v3（遠景の作り込み、2026-09-28）
- refs_read: blender-scene, blender-modeling, blender-scene-spec, blender-lookdev, blender-audit-finalize
- structural: 54 項目すべて合格。遠景の三角形 136,108（左の島 52,530・右の島 47,138・小島 9,970 / 10,660・街 8,716・沖の海 2,160）、全部品 161,338
- motion: フライオーバーは v2 と同じく合格（1–10 静止、110–120 で 2P の目に静止）
- game: 実機で昼・夕暮れ・夜の俯瞰、2P の視点、街と左右の島の望遠を確認（`artifacts/aiquiz_stadium/game/v3_*.png`）。`side_stand_blocks`・`goal_stand`（485 項目）・`floor_boundary`（214 項目）の headless が合格
- 残る制約：海の板の奥の縁に、沖の海が水面のすぐ下に見える細い明るい線（8° の望遠で約 12px、ゲームの画角では 1〜2px）

RESULT v2（build_report.json と実機）
- structural: 43 項目すべて合格。三角形 bay 5,476 / cap_start 6,336 / cap_end 6,096、帆の一式 454、遠景 約 40k、全部品 約 64k
- motion: フライオーバーは 1–10 静止 → 60 で中間 → 110–120 で 2P の目に静止。帆の揺れは実機の差分で帆の面が動くことを確認
- game: `side_stand_blocks`・`goal_stand`（485 項目）・`floor_boundary`（headless）、`helicopter_crossing`（2 人、画面付き、39 項目）が合格。実機の画面は `../previews/ingame/`
