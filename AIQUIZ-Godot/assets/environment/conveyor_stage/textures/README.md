# conveyor_stage / textures

地上（本編）ステージのコンベアベルト床・ローラー用の**細部テクスチャ**。地下神殿（`underground_temple`）の
`steel_*` / `galv_*` / `concrete_*` を地上でも使うための再利用方針もここに書く。
生成は `tools/ground/gen_ground_textures.py`（numpy + Pillow のみ。Blender / Godot 不要）。

## ファイル

| ファイル | サイズ | 内容 | Godot 側の扱い |
| --- | --- | --- | --- |
| `belt_detail_albedo.png` | 1024x1024 RGB | **色ではなく「ベルト色に掛ける細部の変調」**。グレー（R=G=B）。織り目の谷の汚れ、走行方向の汚れ筋・引きずり跡、細かい汚れ、小さな欠け | `source_color`。`ALBEDO = belt_col * tex.rgb`（**ゲイン 1.0、×2 しない**） |
| `belt_detail_normal.png` | 1024x1024 RGB | OpenGL (+Y) 法線。平織りの織り目（擦れ筋では平らにつぶれる）、擦り傷、欠け、ゆるいうねり | `hint_normal`（インポート `normal_map=1`、BC5）。`NORMAL_MAP = tex.rgb` |
| `belt_detail_orm.png` | 1024x1024 RGB | R = AO（織り目の谷・欠けが暗い）、G = 粗さ 0.72〜0.88（擦れ筋は低め＝少し滑らか）、**B = 擦れ（摩耗）マスク 0〜1**（ゴムは金属でないので青は金属に使わない） | 非 sRGB。`AO = orm.r`、`ROUGHNESS` は下記参照、`METALLIC` は既存 uniform のまま。B は擦れ筋を明るくするのに使う（下記） |

数値（生成スクリプト既定実行の検証出力＝書き出した PNG を読み直した値。シード固定で再現可能）:

- albedo: **線形平均 0.940**、線形 min 0.64、標準偏差 0.034。
  8bit では 1.0 を超えられないので「暗くする方向だけ」の変調。平均をちょうど 1.0 に戻したい場合は
  シェーダーで `* 1.064` を掛ける（地上のベルトシェーダーはそうしている）。
- normal: 長さ 0.995〜1.005（平均 1.0002）、最大傾き 36 度、x/y の標準偏差 約 0.10〜0.11。
- orm: AO 0.30〜1.00（平均 0.79）、粗さ 0.718〜0.875（平均 0.814）、擦れマスク 0〜1（平均 0.235、0.5 超は面積の約 17%）。
- 擦れ・汚れはすべて走行方向（画像の縦）に伸びた小〜中サイズ（幅 1〜5 cm、長さ 5〜80 cm 程度）の跡の集まりで、
  タイル（2.5 m）より大きい塊は入れていない（大きいものはタイルごとに同じ形で繰り返して目立つため）。
  数 m 規模の汚れムラ・擦れの濃淡は、ベルトシェーダー側でワールド座標のノイズで付ける。
- 継ぎ目: 左右・上下とも、周期境界の隣接ピクセル差が内部の同位相の隣接差の 0.85〜1.15 倍。
  FFT 合成と、タイル幅を割り切る周期の解析的な織りだけで作っているので、トリミングやブレンドは使っていない。

## タイル寸法とUVの張り方

- **推奨: 1 タイル = 2.5 m（2.0〜3.0 m の範囲で可）**。1 px = 2.44 mm。
  - 織り目の糸ピッチは 8 px = **1.95 cm**（2.0 m/tile なら 1.56 cm、3.0 m/tile なら 2.34 cm）。平織り 1 周期は 16 px。
  - 繊維の筋・細かい粒は約 1 cm、擦れ筋・汚れ筋は幅 1〜5 cm・長さ 5〜80 cm（走行方向）、欠けは 3〜10 mm。
- 床メッシュに UV は無いので、シェーダーでワールド座標から作る（例）:
  `uv = vec2(world_pos.x, world_pos.z + scroll_z * scroll_sign) / belt_tile_m;`
  - **画像の横（U）= ベルト幅方向（ワールド X）、画像の縦（V）= 走行方向（ワールド Z）**。擦れ・擦り傷・汚れの筋は縦方向に伸びている。
  - 走行に合わせて V をスクロールさせれば織り目もベルトと一緒に動く。ガードレール帯（`rim_*`）は動かさない。
  - ローラーは、幅方向を `-local_pos.y`（ローラーは Z 軸回りに 90° 回っているので、これでワールド X と同じ向き）、
    周方向を既存の `belt_v / belt_scale`（弧長 m）にして同じ式で良い。
- サンプラーは `filter_linear_mipmap_anisotropic, repeat_enable` 推奨（遠景の床は斜めに見える。織り目は 8 px 周期なのでミップ 3 段で消える）。

実際の組み込みは `shaders/conveyor_belt_floor.gdshader`（`detail_*` uniform）と
`scripts/world/stage_materials.gd`（`belt_detail()` が画質ごとに設定）。要点:

- 床メッシュに UV が無いので UV はワールド座標から作り、法線マップも NORMAL_MAP（メッシュの接線）を使わず、
  上面は U=+X・画像の上=-Z、ローラーは U=軸方向・画像の上=弧長の逆向き、の接線枠をシェーダーで組んで NORMAL に入れる。
- `ALBEDO = belt_col * (1 + (tex*1.064 - 1) * 濃淡)`、擦れマスク（orm.b）で擦れ筋を少し明るく、
  `ROUGHNESS = roughness_val + (orm.g - 0.814) * 係数`（既存スライダーが平均を決める）。AO は織り目が見える近距離だけ。
- 画質 low は albedo と orm の 2 枚だけ（法線マップは読まない）。

## 再生成

```
python tools/ground/gen_ground_textures.py              # 3 枚を書き出して数値検証
python tools/ground/gen_ground_textures.py --preview    # + 3x3 並べプレビュー（artifacts/ground_quality/）
python tools/ground/gen_ground_textures.py --seed 7 --out C:/tmp/try --no-verify   # 別シードの試作
```

既定シード 20261003 で同じ PNG が再現される（同一環境で 2 回実行してバイト一致を確認済み。
numpy の FFT 実装が変わると 1 ピクセル程度ずれる可能性はある）。生成物を変えたら、Godot でインポートし直すこと。

`.png.import` は手書き（生成スクリプトは書かない）。`underground_temple/source/export_cistern.py` の
`TEX_IMPORT` と同じ書式で、`[remap]` の `uid` / `path` / `[deps]` は**意図的に省略**している。
Godot が最初のインポート時に `uid` と `.ctex` を付与して書き換えるので、その後の `.import` は Godot のものとして扱う。
設定: albedo / orm は VRAM 圧縮 BC7（`compress/mode=2`, `high_quality=true`, `normal_map=2`）、
normal は `normal_map=1`（RGTC、`high_quality=false`）、いずれもミップマップ生成あり。

## 地下神殿のテクスチャを地上で再利用する方針

地上のレール・フレーム・壁・柱などは、`assets/environment/underground_temple/textures/` の PNG を
**コピーせずパスで直接参照**する（`res://assets/environment/underground_temple/textures/steel_albedo.png` など）。
同じ `.import`（同じ uid / 同じ `.ctex`）を共有するので、VRAM もビルドサイズも増えない。
地上用の色は **シェーダーの uniform で掛ける**（地下の素材は頂点色 COLOR_0 で色を付けているが、地上のメッシュには同じ頂点色が無い想定）。

実測（2026-10 時点）:

| セット | albedo / normal / orm のサイズ | albedo の A | ORM（R=AO, G=粗さ, B=金属） | 地下での UV |
| --- | --- | --- | --- | --- |
| `steel_*` | 1024x1024 RGBA | **塗装マスク**（平均 238/255、約 7% が A<128＝塗装が剥げた素地）。地下では `mix(tex.rgb, tex.rgb * COLOR.rgb, tex.a)` で塗装部だけ着色 | R≈1.0（ほぼ平ら）、G 0.49〜0.92（平均 0.56）、B=0（塗装面） | 1.0 m / UV |
| `galv_*` | 1024x1024 RGBA | 常に 255（意味なし） | G 0.36〜0.92（平均 0.47）、B 0.4〜1.0（平均 0.96、亜鉛メッキの金属） | 1.0 m / UV |
| `concrete_*` | **2048x2048** RGBA | 常に 255（意味なし） | R 0.36〜1.0、G 0.57〜0.88（平均 0.80）、B=0 | 3.75 m / UV |

- albedo の sRGB 平均: steel 217（明るい塗装）、galv 188、concrete 144。どれも「そのまま色を持つ」テクスチャ（ベルトの細部変調とは違う）。
- normal は 3 セットとも OpenGL (+Y)、A=255（未使用）。`hint_normal` で読む。
- そのほか同じフォルダ: `floor_*`（2048、濡れ床用の `floor_wet` あり）、`grate_*`（512、albedo の A が格子の抜き）、
  `hazard_albedo`（1024、黄黒帯。normal/orm は `steel_*` を共用）、`detail_normal`（1024、1 m タイルの微細法線）。
  `*_light.png`（2048）は地下モジュール専用のライトマップなので地上では使わない。
- 地上で使うときの目安: レール・フレームは `steel_*` か `galv_*` を 1.0 m/UV 前後（三平面マッピングかワールド座標 UV）、
  壁・柱は `concrete_*` を 3.75 m/UV。steel を使うなら A（塗装マスク）を必ず読み、塗装部だけ地上の色で着色する。
- 床まわりでの実際の使い方: サイドフレームとレールの台座は `steel_albedo/orm`（塗装マスクで縁だけ塗装が剥げる）、
  レールの頭部とウェブは `galv_albedo/orm`（濃淡を弱めて使う）を `shaders/ground_steel.gdshader` で面ごとの平面投影。
  桟橋の側壁は `concrete_albedo` の輝度だけで `side_color` を変調（3.75 m/タイル、1 回読み）。
- 地下の素材は暗い洞窟向けに作られている（ベイクライト前提のレシピは `underground_temple/README.md` を参照）。
  地上の動的ライトで使う場合は通常の PBR（ALBEDO / NORMAL_MAP / AO / ROUGHNESS / METALLIC）で読めば良く、ライトマップ用の UV2 は不要。

## 壁パネル（クイズ壁・扉・ゴール小物）

`wall_panel_albedo.png` / `wall_panel_normal.png` / `wall_panel_orm.png`（3072x1536、完全にシームレス）。
塗装した鋼板の壁：**境目のない一枚の面**（パネルの継ぎ目・リベット列・パネルごとの色調や傾きの段差はない。ユーザー指示で2026-10-03に取り除いた）、塗装のムラ、擦れ、雨だれ、足元に向かう汚れ。`tools/ground/gen_wall_textures.py` の `JOINTS = True` で、3m幅のパネル割り・継ぎ目の溝・リベット列の版に戻せる。
生成は `tools/ground/gen_wall_textures.py`（numpy + Pillow、シード 20261004、Blender/Godot 不要）。

- **albedo は R=G=B の灰色で「`albedo_color` に掛ける変調」**（線形平均 0.940）。`albedo_color` は従来の壁・扉の色のまま
  （`break_door` などが `albedo_color` を読むため）。壁は約6%暗くなる。
- normal は OpenGL (+Y)。orm は R=AO、G=粗さ（平均 0.60＝従来の壁の粗さ）、B=金属 0。
  orm のインポートは `roughness/mode=Green` + `roughness/src_normal`（粗さのミップを法線から広げる）。
- 張り方は `scripts/world/wall_materials.gd`。**オブジェクト空間の triplanar**（`uv1_world_triplanar = false`）で、
  壁は床に沿って動くため、ワールド空間だと模様が泳ぐ。1 タイル = 部品のローカル座標で 9.0m x 4.4m。
  BoxMesh は node の中心にあるので、部品の中心がパネルの中央に来るようにオフセットしてある。
- 画質別の取得回数（壁 1 ピクセル、triplanar は 1 テクスチャ 3 回）：low = albedo（3）、balanced = + 法線（6）、
  high / ultra = + 粗さ（9）。
- PNG を作り直したら、エディターで**ファイルシステム全体のスキャン**（`filesystem_manage op=scan`）をする
  （単一ファイルの `reimport` では取り込み直されないことがあった）。取り込み後に `.godot/imported/wall_panel_*.md5` の
  source_md5 が新しい PNG と一致することを確認する。VRAM は 3 枚で約 19MB（ミップ込み）。
