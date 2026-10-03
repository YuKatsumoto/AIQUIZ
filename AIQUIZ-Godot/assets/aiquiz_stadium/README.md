# AIQUIZ STADIUM（新ステージ）— 制作資料

海上の白い桟橋スタジアム。走路（ゲームのベルトコンベア）の両側に 6 段の観客席が並ぶ（v2 のマストと三角帆・ブースの「?」の画面は、2026-09-28 のユーザー指示で外した）。
水平線の左には高層ビルの街、左右に島、右の沖には「AIQUIZ STADIUM」の看板を掲げた灯台が立つ。
**v2：原本の画像に近づけて Blender で作り直し、ゲームに組み込み済み**（ステージの既定の見た目。以前のサントリーニ風スタンドは切り替えで残す）。
**v3：遠景（島・ビル群）を原本の絵の密度まで作り込み**（下の「v3 で作り込んだこと」）。スタンド・帆・ゲート・ゴール観客席は v2 のまま。

原本は Higgsfield で作ったキービジュアル `source/master/aiquiz_stadium_master_v1.png`（出自は `source/master/PROVENANCE.md`）。
部位ごとの参照画像 33 枚と GOAL 看板のテクスチャは Higgsfield（`nano_banana_pro`）、寸法はゲームの定数と照らした寸法表、形は寸法表を読む決定的なビルダー（Blender 5.1）で作る。

## ユーザー決定

- 原本：B オーシャン・セイル＋遠景ビル群（左の水平線）
- 観客席：6段
- ゴール観客席：B 案「港の操舵室」で作り直す（反応・卵・掲示板の仕組みはそのまま）
- 灯台：遠くに固定したランドマーク。置き場所は **B（軸から外した小島、画面右）**
- ゲートの文字：GOAL
- チーム色：P1 オレンジ＝+X（画面左）、P2 青＝-X
- **迫ってくる問題壁のデザインは変えない。床はゲームのベルトコンベアのまま**（v2 の指示）

## v2 で直したこと（原本との差）

| 項目 | v1 | v2 |
| --- | --- | --- |
| 帆 | 走路側へ下がる平らなテント形・不透明 | 原本と同じ、スタンドを横切る三角帆（ヘッド＝マストの頂、ブームの先が走路側の客席の上）。縁は内側へ弓なり、面はふくらみとねじれ。ゲームでは **風で揺れ（UV2 の重み）、ゴール側の太陽の光が透け（backlight）、夜は下から照らされたように光る** |
| 街とビル | 小さな箱のビル 14 本が島の陰 | ガラスの高層ビル 13 本＋中層 20 本＋低い街並みと海岸。原本どおり水平線の中央左（方位 10°、4.25km）に大きく立つ。外壁は昼の色と夜の窓明かりの 2 枚のテクスチャ |
| 島 | 平らな起伏 | 原本どおり左に茂みの丘の大島、中央左にヤシの小島、右に桃色の岩の島、遠くに小島。丸い茂み・ヤシ・水際の丸い岩・砂浜 |
| ブース | 八角の箱に青い板 | 丸みのある箱に「?」の画面（発光） |
| ヨット | 3 艇 | 6 艇、ふくらんだ帆（布の材質を共有） |
| 走路 | 走路の下の杭の組を別部品に | **作らない**：ゲームの床（ベルトコンベア）は上面から海底までの箱なので、杭は箱に隠れる。床・ローラー・側枠・レールはゲームのまま |
| 問題壁 | 確認用に派手な色の壁を仮置き | 確認用の壁もゲームの形（灰色の壁と 4 色の扉・問題文の板）そのままに |

## v3 で作り込んだこと（遠景）

ゲームの画面では島は 2km、街は 4km 先にあり、街の高さは 2P の画面で 60px ほど。細部より「輪郭・色と陰影・かすみ・水際」が効くので、そこを作り込んだ。
変更前のファイル・レンダーは `artifacts/aiquiz_stadium/backdrop_realism/before/`、変更後の実機の画面は `artifacts/aiquiz_stadium/game/v3_*.png`（主なものは `source/previews/ingame/backdrop_*.jpg`）。

| 項目 | v2 | v3 |
| --- | --- | --- |
| 島の地形 | なめらかな丘 | 尾根と谷（ノイズ）、右の島は裾野の広い岩山で頂上だけごつごつした岩肌と地層の縞。谷は暗く尾根は明るく頂点色に入れる（ゲームは環境光が強く陰影が浅いため） |
| 森 | 丸い茂み 12〜92 個 | 島を覆う樹冠（大きな島で約 700）。6 色の緑を混ぜ、下は陰で暗く、高い所ほど日が当たって明るい。ところどころ空き地と高木 |
| 水際 | 砂浜と丸い岩 | 砂浜（乾いた砂と濡れた砂）、ヤシの群れ、水際の岩場、白波の帯（波打ち際と沖の礁）、海の中の浅瀬（深さ 4m 以内の砂と藻場。ゲームの半透明の海越しに礁湖の色になる） |
| 街 | 高層 13・中層 20・低い街並み | 高層を手前と奥の 2 層（面取り・円筒・先細り・段・ツイン・頂部の飾り枠・基壇）、中層 約 45、低い街並み 3 列と通り、公園と並木、護岸と砂浜。外壁は 5 種（濃紺の横連窓・石張りを追加） |
| 窓 | どの棟も同じ割り付け | 棟ごとに窓の割り付けをずらし、下は暗く上は空を映して明るい頂点色。夜は外壁を暗くして窓明かりだけを浮かせる。高い塔の頂に航空障害灯 |
| かすみ | 頂点色とテクスチャに焼き込み（夜も昼の色のまま） | `shaders/aiquiz_backdrop.gdshader` が距離でかすませる（`FOG`）。色は空のシェーダーと同じ式の地平線の色（昼・夕焼け・夜）、高い所ほど薄い。水面下はかすませない |
| 沖の海 | なし（海の板は 4km 四方で、街と遠い小島はその外の空の上に立っていた） | `AQS_BG_FarSea`：海の板の外側を far まで埋める海。色と照明はゲームの海に合わせ、かすみは海の板の縁から少しずつかける |

気づいた制約：海のシェーダーは真上の水深だけで透け方を決めるので、深い斜面を海の中に作ると低い視点から崖のように透ける（浅瀬を 4m 以内にした理由）。
また、海の板の奥の縁では、沖の海が水面のすぐ下に見えるため細い明るい線が出る（8° の望遠で約 12px、ゲームの画角では 1〜2px）。

## ゲームでの使われ方

| 場所 | 中身 |
| --- | --- |
| `scripts/world/stage_environment.gd` | `layout_stadium_style`（既定 `aiquiz`／`santorini`）。aiquiz のとき、スタンドは下の新スクリプト、遠景は `StadiumBackdrop`、海底は残してサントリーニの岸壁の階段は作らない |
| `scripts/world/aiquiz_stadium/aiquiz_stadium_stand.gd` | 20m ブロックを床の長さに合わせて並べる（`santorini_terrace_stand.gd` と同じ約束：座席 JSON・通路・観客・ブロックは増やすだけ）。帆（タープ）は置かない（2026-09-28 のユーザー指示。`aiquiz_stadium_sail_rigs.glb` は書き出しは続くが使わない）。杭は実行時に海底まで伸ばす |
| `scripts/world/aiquiz_stadium/aiquiz_stadium_backdrop.gd` | 灯台・島・街・沖の海・ヨット（GLB はワールド座標で作ってあるので原点に置くだけ）。天気の `night_amount_changed` で夜の灯を切り替え、空の地平線の色と太陽の向きを遠景のかすみに渡す |
| `scripts/world/aiquiz_stadium/aiquiz_stadium_materials.gd` | 取り込んだ材質を名前で差し替える：`AQS_Painted`（頂点色）、`AQS_NightGlow`（夜の灯のシェーダー）、`AQS_SailFabric`（帆のシェーダー）、`AQS_BG_Painted` / `AQS_CityFacade_*` / `AQS_BG_Sea`（遠景のシェーダー：かすみ・ガラス・夜の窓・沖の海）。すべて共有なので夜の切り替えは 1 回で全部に届く |
| `shaders/aiquiz_sail.gdshader` / `aiquiz_vertex_glow.gdshader` / `aiquiz_backdrop.gdshader` | 帆（風の揺れ・透け・夜の光）、夜の灯、遠景（距離のかすみ・夜の窓・沖の海） |
| `scripts/world/goal_stand/goal_stand.gd` | 構造を `aiquiz_stadium_goal_stand.glb` に（段・通路・LED 面の約束は元の goal_stand.glb と同じ） |
| `scripts/world/game_world.gd` | GOAL ゲートを金色の箱と Label3D から `aiquiz_stadium_goal_gate.glb` に（市松の線は残す） |
| `scripts/world/grandstand_crowd.gd` | 観客の描画範囲を座席から求める（6 段でも腕まで入る） |

確認：`tests/side_stand_blocks_bootstrap.gd`・`goal_stand_bootstrap.gd`・`floor_boundary_bootstrap.gd` は headless で、`helicopter_crossing_bootstrap.gd`（2 人、実際のスタートの流れ）は画面付きで通る。
実機の画面は `source/previews/ingame/`（2P の昼・夕暮れ・夜、帆の近景、GOAL ゲート、ゴール観客席）。

## 書き出したもの（Godot が読み込む）

| ファイル | 中身 |
| --- | --- |
| `aiquiz_stadium_stand_blocks.glb` / `.json` | 側面スタンドの 20m ブロック `AQS_Stand_Bay` / `AQS_Stand_CapStart` / `AQS_Stand_CapEnd`（6段・114席、丸いブース。マスト・ヤード・シュラウドと「?」の画面は 2026-09-28 のユーザー指示で作らない）。JSON は座席・通路と帆の組み合わせ |
| `aiquiz_stadium_sail_rigs.glb` | 帆の一式 `AQS_SailRig_R` / `AQS_SailRig_L`（布・ブーム・ブームの灯・トッピングリフト）。ブロックと同じ座標。UV2 に揺れの重み |
| `aiquiz_stadium_goal_gate.glb` | GOAL ゲート `AQS_GoalGate`（柱 |x| 11.55、梁の下 5.0m、表裏に GOAL 看板） |
| `aiquiz_stadium_goal_stand.glb` | ゴール観客席 B `GS_Stand` / `GS_Scoreboard`（LED 面 `GS_ScoreboardScreen` は元と同じ位置・向き・UV） |
| `aiquiz_stadium_backdrop.glb` | 遠景（ワールド座標）：灯台 `AQS_Lighthouse`、島 4 つ、街 `AQS_BG_City`、沖の海 `AQS_BG_FarSea`、ヨット 6 艇。沖の海のほかはカメラの far 5000m の内側（沖の海は far まで伸ばす） |
| `aiquiz_stadium_layout.json` | 一品物の位置と材質の扱い |
| `*_<画像名>.png` | Godot が GLB から取り出したテクスチャ（取り込み時に自動で作られる） |

三角形数：スタンドのブロック 5.5k〜6.3k、帆の一式 0.45k、遠景の合計 約 136k（左の島 52.5k・右の島 47.1k・小島 10k ずつ・街 8.7k・沖の海 2.2k）、全部品で 約 161k。
遠景は Godot の取り込みで距離の LOD が作られる（2km 先では細かい三角形が減る）。材質は帆の布だけ両面、ほかは片面。

## 制作資料（`source/`、Godot の読み込み対象外）

| パス | 内容 |
| --- | --- |
| `blender/build_stadium.py` | **ビルダー**（部品の組み立て・書き出し・検算・レンダー）。部品は `aqs_parts.py`（スタンド・ゲート・ゴール観客席・灯台）、`aqs_sails.py`（帆）、`aqs_backdrop.py`（島・街・沖の海・ヨット）、確認シーンは `aqs_review.py`、共通の設定は `aqs_common.py`、形と材質の道具は `aqs_geom.py` |
| `blender/SCENE_PASSPORT.md` | 組み立ての仕様（部品・カメラ・光・動き・合格条件） |
| `blender/aiquiz_stadium.blend` | 組み立て結果。部品のシーンと、ゲームの座標どおりに並べた確認シーン（床と問題壁はゲームの形を写した参照物、仮置きの観客、昼・夕暮れ・夜、原本の空撮に近いカメラ） |
| `build_report.json` | 検算（43 項目＋動き 3 項目）、部品ごとの三角形数・材質・外形 |
| `previews/*.jpg` / `previews/ingame/*.jpg` | Blender の確認レンダーと、ゲームの実画面 |
| `textures/make_textures.py` | 手続きのテクスチャ：帆の布、ブースの画面、街の外壁（昼と夜の窓）。`goal_board.png` は Higgsfield、`lighthouse_sign.png` は `sb_header.png` の流用 |
| `DIMENSIONS.md` / `dimensions.json` | 寸法表（人が読む版 / ビルダーが読む版）。値ごとに根拠（定数・実測・設計） |
| `reference/`・`generation_record.json`・`PROMPTS.md`・`palette.json`・`game_constants.json`・`guides/`・`measure/` | 参照画像と生成記録、色見本、ゲームの定数、ガイドと実測 |

## 作り直し

```powershell
python assets/aiquiz_stadium/source/textures/make_textures.py
python assets/aiquiz_stadium/source/measure/build_dimensions.py   # 検算に失敗すると終了コード 1
```

Blender のビルダーは、ユーザーが開いているライブの Blender 上で動かす（途中経過が画面に見えるように）。Higgsfield の Blender 連携が
接続済みか `get_host_status` で確かめ、未接続なら接続を依頼して待つ。`--background` のヘッドレス実行で代替しない。
ビルダーは開いているシーンを空にしてから組み立てるので、先に未保存の作業がないか確認する。`bl_execute` で次を実行する：

```python
import runpy, sys
for name in [m for m in sys.modules if m.startswith("aqs_")]:
    del sys.modules[name]              # 部品モジュールの修正を読み直す
sys.argv = ["blender", "--"]           # レンダーを省くなら ["blender", "--", "--no-render"]
runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/aiquiz_stadium/source/blender/build_stadium.py", run_name="__main__")
```

約 20 秒で GLB・JSON・`.blend`・確認レンダー（`artifacts/aiquiz_stadium/blender/`、主なものは `source/previews/`）・
`build_report.json` を作り直す。
最後の行 `AQS_BUILD {"all_checks_pass": true, ...}` が合格の印。定数・ガイド・実測の作り直しは `extract_game_constants.py`、`guides/`、`measure/` の各スクリプト。
