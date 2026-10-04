# 地上ステージの品質底上げ

2026-10-03。サドンデスの地下神殿（Blender自作＋PBRテクスチャ＋焼いた光＋霧＋反射）との品質差を詰めるため、地上（本編）の床・壁・ドア・レール・フレーム・桟橋・スタンド・海・空気を作り込んだ。GPUに負荷をかけすぎない（流体・コンピュート・重いポストエフェクトは使わない）ことが条件。

## 1. 決定事項

| 項目 | 内容 |
| --- | --- |
| 方針 | 静的なもの・軽量シェーダー・Blenderで焼いた頂点カラーだけで底上げする。流体シミュレーション、コンピュートシェーダー、SSR、SSIL、体積フォグ、SDFGI、LightmapGI、デカールは使わない |
| 人物 | ブロック調のプレイヤーは形も色も変えない（材質コードにも触れていない） |
| Android版 | `AIQUIZ-Godot-Android` は今回触らない。床シェーダーなどが本体と分岐しているため、反映するなら別作業（この変更は本体のWindows版だけ） |
| GPU予算 | 開発PC・1280×720・改修前との差（GPU p50）：高画質 +0.6ms 以内 / 標準 +0.4ms 以内 / 軽量 +0.15ms 以内 |
| 反射プローブ | 実装したが**既定でオフ**（`StageAtmosphere.PROBE_ENABLED`）。1個置くだけでリフレクションアトラス全体（プロジェクト設定の16枠）が確保され、VRAMが +134MB（718→895MB）増える。効果はレールの艶だけで、見合わない |
| 問題パネル | 3D問題パネルの地を灰色から、スタジアムのゴール看板と同じ紺に変えた（白文字の可読性が上がるため）。戻すときは `quiz_wall.gd` の `QUESTION_PANEL_COLOR` / `QUESTION_BORDER_COLOR` の2行 |

## 2. 変更内容

| 領域 | 内容 | 主なファイル |
| --- | --- | --- |
| ベルト床・ローラー・リターンベルト | 織り目・擦れ・汚れの細部テクスチャ（色に掛ける変調。ベルト色の着せ替えは保つ）、擦れ部の艶、ガード帯の塗装鋼板化（擦り傷・ベルトに擦られた縁）、フレーム際の接触AO、桟橋側壁の型枠コンクリート・水線の濡れ・雨だれ。模様はベルトと一緒に流れる | `shaders/conveyor_belt_floor.gdshader`、`scripts/world/stage_materials.gd`、`assets/environment/conveyor_stage/textures/belt_detail_*` |
| サイドフレーム・レール | 塗装鋼＋亜鉛メッキ鋼（地下神殿の鋼テクスチャをパスで直接参照）、縁の塗装剥げ、3.2mごとの継ぎ目、ボルト列、走行帯の研磨 | `shaders/ground_steel.gdshader`、`scripts/world/conveyor_rails.gd` |
| クイズ壁・ドア・ゴール小物 | 境目のない一枚の塗装鋼板（塗装のムラ・擦れ・雨だれ・足元に向かう汚れ。パネルの継ぎ目とリベット列は、ユーザー指示で取り除いた。`gen_wall_textures.py` の `JOINTS = True` で戻せる）。ゴールラインの縞・スタートバリア・鋸の支柱も同じ素材感。材質は `StandardMaterial3D` のまま、`albedo_color` は従来の色 | `scripts/world/wall_materials.gd`、`scripts/world/quiz_wall.gd`、`assets/environment/conveyor_stage/textures/wall_panel_*` |
| 空気 | 指数フォグ（密度0.0003、空の地平線色）、下からのバウンス光（負のエネルギーの影なし平行光）、軽い色調補正（コントラスト1.04）、ビネット | `scripts/world/stage_atmosphere.gd`、`shaders/ground_grade.gdshader` |
| 海 | フレネル（空の天頂→地平線の反射）、さざ波（解析式）、太陽のきらめき、水際の接触泡。追加のテクスチャ取得なし | `shaders/ocean.gdshader`、`scripts/world/ocean_detail.gd` |
| スタンド・ゴール台・ゲート・ヨット | Blenderで頂点カラーにAO・水際の汚れ・ムラを焼き込み（実行時コスト0）。共有材質をシェーダー化：色ムラ、水際の濡れ、雨だれ。遠景の海はフォグと反射を引き継ぐ | `assets/aiquiz_stadium/source/blender/aqs_wear.py`、`shaders/aiquiz_stand_surface.gdshader`、`scripts/world/aiquiz_stadium/aiquiz_stadium_materials.gd`、`shaders/aiquiz_backdrop.gdshader` |
| 設定画面のプレビュー | ベルト色の着せ替え画面と壁速度画面も、本編と同じベルトの質感にした | `scripts/ui/customize_settings.gd`、`scripts/ui/wall_speed_settings.gd` |

### 呼び出し口（`StageEnvironment` に1行ずつ）

`StageEnvironment` は材質やノードを直接作らず、次のヘルパーを呼ぶ。どれも `class_name` を付けず `preload` で参照する（クラス名キャッシュが古いと解決できないため）。

| 呼び出し元 | 呼び先 |
| --- | --- |
| 床・ローラー・リターンベルトの生成時と画質変更時 | `StageMaterials.belt_detail(material, quality)` |
| サイドフレーム | `StageMaterials.side_frame(quality)` |
| レール | `ConveyorRails.apply_graphics_quality(q)`（画質変更時）、材質は `StageMaterials.rail_head/rail_support` |
| 環境の構築と画質変更 | `StageAtmosphere.apply_environment_quality(env, quality)` |
| `WeatherCycle._apply`（毎フレーム） | `StageAtmosphere.apply_weather(env, day_amount, twilight_amount, quality)`：フォグは WeatherCycle が毎フレーム無効に戻すので、直後に設定し直す |
| `StageEnvironment.build()` の最後 | `StageAtmosphere.build(parent, quality, gameplay)`：下からのバウンス光（全画質）とビネット（本編・標準以上）。返ったノードを生成物の子にする |
| 海の材質を作るたび | `OceanDetail.configure(material, quality)`、太陽方向は `WeatherCycle` → `OceanDetail.set_sun` |
| スタンドの共有材質 | `AiquizStadiumMaterials.painted()`（`ShaderMaterial`）。画質は `GameManager.graphics_quality_changed` に追従 |

## 3. 画質段階ごとの出し分け

| 機能 | 軽量 | 標準 | 高画質 | 最高画質 |
| --- | --- | --- | --- | --- |
| ベルト床・ローラーのテクスチャ取得（1画素） | 2（色・ORM） | 3（＋法線） | 3 | 3 |
| フレーム・レールのテクスチャ取得 | 2 | 2（ボルトの凹凸は計算のみ） | 2 | 2 |
| 壁・ドアのテクスチャ取得（triplanar、1画素） | 3（色） | 6（＋法線） | 9（＋粗さ） | 9 |
| 桟橋側壁 | 1 | 1 | 1 | 1 |
| フォグ・色調補正・下からのバウンス光 | ○ | ○ | ○ | ○ |
| ビネット（本編のみ） | × | ○ | ○ | ○ |
| 反射プローブ | × | × | × （実装あり、既定オフ） | × |
| 海：フレネル・さざ波・きらめき・泡 | × （従来と同じ） | ○（さざ波4波、泡1オクターブ） | ○（6波、2オクターブ） | ○ |
| スタンドの塗装 | 頂点カラーのみ（従来と同じ） | 色ムラ・濡れ・雨だれ | ＋細かい色ムラ | ＋細かい色ムラ |

## 4. GPU予算と実測

測定：`tests/ground_look_bootstrap.gd`（本番の `game_world.tscn`、ローカル2P、1280×720、6構図×300フレーム）。改修前のコードを別フォルダーにコピーして同じハーネスで動かし、前後を交互に2回ずつ測った（ほかのゲームが GPU を使っていない状態）。値は6構図の GPU p50 の平均。最初のベースライン（`artifacts/ground_quality/before/summary.md`）は別のゲームが GPU を約50%使っている間に測ったため、この表の測り直しを基準にする。

| 画質 | 改修前 | 改修後 | 差 | 予算 |
| --- | --- | --- | --- | --- |
| 軽量（3Dスケール0.7） | 0.775ms | 0.790ms | **+0.015ms** | +0.15ms |
| 標準（0.85） | 0.990ms | 1.045ms | **+0.055ms** | +0.4ms |
| 高画質（1.0） | 1.295ms | 1.400ms | **+0.105ms** | +0.6ms |
| 最高画質（2.0、2×2スーパーサンプル） | 2.210ms | 2.575ms | **+0.365ms** | （画素数が4倍の条件。適応スケーラーが予算で調整） |

VRAM（`RenderingServer` のテクスチャ＋バッファ）：軽量 +21MB、標準 +29MB、高画質 +35MB、最高画質 +36MB。3D の描画呼び出しは全構図で +0〜+1。

## 5. 守っていること（壊すと動かなくなる約束）

- **サドンデスの穴**：`StageEnvironment` が `shader.code.replace("shader_type spatial;", …#define SHAFT_HOLE)` で床・ベルト・ローラー・海のシェーダーの派生を作る。`conveyor_belt_floor.gdshader` と `ocean.gdshader` は1行目が `shader_type spatial;`、`#ifdef SHAFT_HOLE` のブロックと `discard` を持ち、相対 `#include` を使わない（`tests/ground_quality_unit.gd` が検査）。
- **床シェーダーの外部 uniform**：`scroll_z`、`scroll_sign`、`base_color` など24個の名前と型は変えない。メニューのプレビューと設定画面が書き込む。新しい uniform は既定値で従来の見た目に落ちる（`detail_strength` 0）。
- **ベルト色の着せ替え**：テクスチャは色ではなく「色に掛ける変調」（線形平均 0.94）。赤いベルトでも色相・彩度は変わらない。
- **壁は動く**：壁の材質は**オブジェクト空間の triplanar**（`uv1_world_triplanar = false`）。ワールド空間だとテクスチャが壁の上を泳ぐ。
- **壁の材質は `StandardMaterial3D`**：`break_door`、`_fade_mesh_to_transparent`、`_shatter_mesh` が `albedo_color` を読む。
- **フォグ**：`WeatherCycle._apply` が毎フレーム `fog_enabled = false` に戻すので、`apply_weather` が直後に設定し直す。サドンデスの降下は地上の環境を複製して `fog_light_energy` を 0 へ下げる。背景シェーダー（島・街・遠景の海）は独自の `FOG` を出力し、環境フォグを**置き換える**ので二重にはかからない。遠景の海だけは `edge_fog_density` でフォグを引き継ぐ。
- **人物の色**：色調補正のコントラストは 1.04、彩度は変えない。プレイヤー2人の体の平均色は改修前の ±3% 以内。
- **`tests/graphics_quality_unit.gd`**：SSAO は高画質以上、SSIL は常にオフ、グローは軽量以外でオン。

## 6. 見送ったもの

| 見送り | 理由 |
| --- | --- |
| SSR、SSIL、体積フォグ、SDFGI | 屋外では重い。SSIL は意図的にオフ |
| LightmapGI | スタンドは実行時にブロックが増え、UV2もない |
| デカール | サドンデスの穴の内側に映る恐れ |
| 海底テクスチャ | 水深120mで見えない |
| 空の radiance サイズを128へ | `REALTIME` の空は 256 しか使えない（実際に256へ戻される） |
| AgX トーンマップ | 01の輝度が -25%、オレンジの人物が -14%、赤いドアがくすむ |
| 空を光源にする環境光 | この空は天頂が濃い青で下が淡い青緑のため、床が青く、下向きの面が暖色に寄る。代わりに下からの負のバウンス光で下向き面だけを暗く冷たくした |

## 7. 資産とツール

| ファイル | 内容 |
| --- | --- |
| `tools/ground/gen_ground_textures.py` | ベルト細部テクスチャ（1024²、シード20261003、numpy＋Pillow） |
| `tools/ground/gen_wall_textures.py` | 壁パネルテクスチャ（3072×1536、シード20261004） |
| `assets/environment/conveyor_stage/textures/README.md` | 上のテクスチャの仕様、チャンネル、タイル寸法、地下の鋼テクスチャを地上で再利用する方針 |
| `assets/aiquiz_stadium/source/blender/aqs_wear.py` | 頂点カラーへのAO・水際の汚れの焼き込み（`build_stadium.py` から呼ぶ。`--no-wear` で無効） |

## 8. 検証

`AGENTS.md` に従い、構造の確認と実ゲームでの証拠を分けて記録する。画像と記録は `artifacts/ground_quality/`（`.gitignore` 対象）。

| 検証 | 内容 |
| --- | --- |
| 前後の撮影・計測 | `tests/ground_look_bootstrap.gd`：`-- quality=<low|balanced|high|ultra> shots perf frames=300 tag=<名前>`。出力は `artifacts/ground_quality/<tag>/<quality>/`。改修前は `before/`、最終は `after/`、並べた画像は `compare_final/`。画像差分は `-- compare tagA=before tagB=after quality=high` |
| 回帰テスト（ヘッドレス） | `tests/ground_quality_bootstrap.gd`（新規。237項目：テクスチャ、シェーダーの約束、画質ごとの設定、フォグ、ビネット、海、壁、スタンド塗装） |
| 既存テスト | `graphics_quality`、`floor_boundary`、`goal_stand`、`side_stand_blocks`、`sudden_death`（単体・実ゲーム `correct` / `p2` / `timeout`）、`surface_hole`、`result_ceremony`、`shaft_descent`、`cistern_loader`、`hp`、`saw_chase`、`wall_recoil`、`startup_loading`、`menu_harbor_stage`、`final_death_camera`、`scoreboard_cutin`、`ocean_graphics_quality_regression` |

```powershell
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/ground_quality_bootstrap.gd
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/ground_look_bootstrap.gd --fixed-fps 60 -- quality=high shots perf frames=300 tag=check
```

## 9. 既知の弱点と今後

- 効果は「テクスチャのあるおもちゃの世界」で、地下神殿のような実写寄りの質感ではない（人物がブロック調のままなので、そのほうが整合する）。標準距離（01）では織り目が画素より小さく、見えるのは擦れ・汚れまで。ベルトの擦れ筋は見方によっては速度線にも見える。
- 太陽を傾けたことで（第10章）、正面の見え方は明るく、陰影がはっきりした。一方、前方（コースの先）を向いた画面では太陽の反射のきらめきは出ない（太陽がカメラの後ろにあるため）。後ろや横を向く画面（メニュー背景など）では出る。
- 側壁の型枠割り（3.75m）は、海側から見ると規則的な繰り返しが見える。
- 島と街は背景シェーダーが独自にかすませるため、環境フォグでは変わらない（2〜3km の島は手前の海よりかすみが薄い）。
- スタンドの杭の頂点の輪は3本だけなので、焼き込んだ水際の汚れは 7.4m の直線的なグラデーションになる。鋭い水際はシェーダー側で出している。杭に1リング足せば焼き込みで水位の帯が出せる（頂点数が変わる）。
- Android版（`AIQUIZ-Godot-Android`）には未反映。
- 反射プローブを使うには、リフレクションアトラスのメモリ（+134MB）を許容するか、枠数を減らす必要がある。

## 10. 太陽の傾き（2026-10-03、ユーザーの指示）

それまでの正午の太陽は真上（`(0, 1, 0)`）で、垂直な面（壁の正面、人物の背中、スタンドの側面）は環境光だけで照らされ、陰影が出なかった。コースの後ろ・左上から30°傾けた。

| 項目 | 内容 |
| --- | --- |
| 変更箇所 | `assets/environment/sky/day_night_sun_path.tscn` の `SunOrbitControl`。ローカルZ軸まわりに +30° ロール（`rotation` の z = 0.5236 rad、y = -2.178 rad は従来のまま）。シーンの説明どおり「ローカルZまわりのロールで軌道を傾ける」操作 |
| 正午の太陽の向き | `(0.285, 0.866, -0.411)`（太陽へ向かう向き。高さ60°、カメラの後ろ、画面の左上）。日の出の向き（ローカルZ）は従来のまま。`WeatherCycle` は昼固定なので、この向きがそのまま使われる |
| 見た目 | 壁の正面・ドアが明るく読みやすくなり、パネルの継ぎ目が出る。走者の影が前方（画面の奥・右）へ伸び、人物に陰影がつく。画面全体の平均輝度は +7%（壁に寄った構図で +23%）、ベルト上面は -11%。左のスタンドの内側面は日陰になり、左右で差がつく |
| 試した候補 | 真後ろ（B）：壁が明るすぎ、陰影が出にくい。右後ろ（C）：Aの左右反転。後ろ・左 38°（D）：影が長く、壁がさらに明るい。正面・左（E）：壁が日陰になり、壁の足元に濃い影帯、走者の背中も暗くなる。後ろ・左 30°（A）を採用 |
| 戻し方・変え方 | `SunOrbitControl` の `rotation` の z を 0 にすると真上に戻る。エディターで `day_night_sun_path.tscn` を開いて回転させてもよい |
| 候補を試す | `tests/ground_look_bootstrap.gd` の引数 `sun=x,y,z`（正午の太陽へ向かう向き）で、シーンを編集せずに見比べられる |

太陽の向きは `WeatherCycle` を通じて、空の太陽の円盤、海のきらめき（`OceanDetail.set_sun`）、遠景のかすみ、影つきの平行光に届く。サドンデスの降下（太陽の光が消える処理）と結果演出（専用のキー・リムライト）は従来どおり動く（実ゲームのテストで確認）。GPU 負荷は測っていない（影のコストは向きによらず同じ）。
