# サドンデスの水上機 C-130（floatplane_c130）

サドンデス「つきやぶれ！スカイゲート」で 2 人を運び、後ろのスロープから飛び出させる水上機（計画書 `docs/sudden_death_v2/skygate_build_plan.md` の W1）。
形と寸法は `docs/sudden_death_v2/c130_float.md`（第 1・2・5 章）と `source/c130_design.py`（`artifacts/sudden_death_v2/c130_float/c130_design.py` の写し）。
Godot のクラスは `scripts/world/sudden_death/floatplane/sudden_death_floatplane.gd`（`SuddenDeathFloatplane`）。

- 外：白と濃紺に、オレンジと青の細い線。全長 18.0 m・翼の幅 24.0 m・エンジン 4 つ（4 枚羽根）・大きな尾翼・フロート 2 本。
  実機の目印も入れた：背中と腹の板アンテナ、操縦室の上から垂直尾翼へ張る HF のワイヤー、ピトー管、ワイパー、左の前の乗員の扉（輪郭・取っ手・小さな窓・足かけ）、
  背中の非常口の輪郭、垂直尾翼の背びれ、方向舵と昇降舵の継ぎ目、エンジンの下の吸気口、放電索、フロートの通路（滑り止め）・クリート・水かじ・竜骨の帯、
  外板の文字（登録記号 TQ-130・部隊名・DANGER PROPELLER・NO STEP・RESCUE）。パネルの線とリベットは法線のテクスチャ（三方向から貼る）。
- 機内（A：実機ふう。2026-10-18 にユーザーの指示で「実際の C-130 の機内を実写の水準で」作り込んだ。手本は Wikimedia Commons の C-130H／J の貨物室の写真）：
  骨組み（リブ）の間を灰緑のキルティングの断熱材が枕のようにふくらんで覆う、天井の両わきに太い空調ダクト（留め金・吹き出し口）、降下の静索 2 本、丸いダウンライト 24、黄色い非常灯、
  壁の上の配管と電線の束（P 形の留め金）、インターホン、位置番号のステンシル「LS ○○○」、太い白い縁の丸窓、
  赤いナイロンの布の座面と上の管から吊るベルトのはしごの背もたれ（12 席 × 2、席ごとの垂れた腰のベルト、アルミの脚と横棒）、座席の下の袋、
  アルミの床（継ぎ目・皿ねじ・すり傷）とローラーの列 4 本・黄色い線・つなぎ止めの輪、消火器・救急箱・酸素の盤・懐中電灯、乗員の扉の内側、
  黄色と黒の縞の後ろの開口と降下のランプ（赤・緑）、スロープの作動筒、縞鋼板の段と操縦席の床。
- 操縦席：一段高い床（貨物室の床から 1.05 m、段 3 つ、出入り口の幅 1.5 m）の真ん中の 1 席にハテナ（`HatenaPilot`、ヘリと同じ置き方）。
  2026-10-22 に C-130J のグラスコックピットを手本に作り直した（`source/blender/fp_cockpit.py`）：4 つの画面（PFD・地図・エンジン・気象レーダー）の
  立体の縁とソフトキー・ガラス、予備計器、主警告／主注意、布張りの日よけと自動操縦の盤・磁気コンパス、羊の角の形の操縦かん、ペダル、
  クッションの座席（頭あて・ひじかけ・肩のベルト）、右の台のパワー・条件・フラップのレバーとトリムの輪、左の台の無線、天井の盤（トグルスイッチ・
  消火の取っ手）、窓の内側の枠と窓の下の台、壁の酸素の盤・インターホン・遮断器の棚、消火器と斧。
- 2026-10-22 のクオリティーの引き上げ（外）：フロートを本物の水上機の形（V 字の船底・チャイン・段・とがった船首・点検口・竜骨の金具・しぶきよけ・
  水かじ）に、支柱を流線形（両端の覆い・X の張り線）に、エンジンの覆いを T56 の長い覆い（あごの吸気口・油の冷却口・継ぎ目と留め金・
  主翼の後ろへ伸びる尾と排気口）に、羽根を幅の広い櫂の形（翼形・根元の丸い軸）に作り直した。主翼の前の縁の金属の帯、給油口、着陸灯、
  燃料の放出口、編隊灯（胴体・尾翼・翼端）、後ろの降下の扉（左右）、静圧孔、換気の口、方向舵と昇降舵のタブ。外板はパネルごとの色むら・
  継ぎ目のくすみ（`textures/fp_paint_albedo.png`）と、シェーダーの汚れ（大きなむら・排気口の焼け・フロートの水線）。

## ファイル

| ファイル | 内容 |
| --- | --- |
| `floatplane_c130.glb` | ゲームで使う機体（約 16.6 万三角形）。スロープと上のふたは閉じた形。頂点色（COLOR_0）の R は焼いた AO |
| `floatplane_c130_layout.json` | マーカー・動く部品の軸と角度・プロペラの羽根の向き・作動筒の付け根・機内の灯 30 個・尾の下の通り道・排気口（`exhausts`）・Godot と設計の寸法 |
| `textures/` | 断熱材・床・縞鋼板・外板のパネルの線・ベルトと布の織り目の法線、外板の色むら（`fp_paint_albedo.png`）、文字のアトラス（`fp_decals.*`）、計器のアトラス（`fp_panel.*`、4096×2048。アルファは光る所＝画面と灯。`fp_panel.json` の `items` が立体の縁・つまみ・レバーの位置）。`source/make_textures.py` が作る |
| `shaders/fp_surface.gdshader` | 面の材質：頂点色の AO は環境光だけを暗くする（機内の灯は消さない）。テクスチャは UV か三方向（外板）。`emission_mask_alpha` でテクスチャのアルファの所だけ光る（計器）。`exterior_grime` で外板の汚れ（むら・排気口の焼け `soot_src`・フロートの水線 `waterline_stain`） |
| `shaders/fp_decal.gdshader` / `fp_prop_disc.gdshader` | 文字（アルファで重ねる）・回るプロペラの円盤 |
| `shaders/fp_light_shaft.gdshader` / `fp_cabin_dust.gdshader` / `fp_hatch_glare.gdshader` | 後ろの扉から差す昼の光（`scripts/world/sudden_death/floatplane/fp_hatch_light.gd`）：光の筋（機内の箱の中を視線に沿ってたどる）・光の中だけ光るほこり・開口の白とび（2026-10-19、`docs/sudden_death_v2/c130_float.md` 10.4） |
| `shaders/fp_cloud_veil.gdshader` / `fp_cloud_puff.gdshader` | 雲の層をつき抜けて場所を替える（`fp_cloud_pass.gd`）：画面の深さで白くなる雲の中・層積雲の板（c130_float.md 10.5） |
| `source/c130_design.py` | 寸法の写し（数字は元と同じ。ビルダーが起動時に元と比べる） |
| `source/blender/build_floatplane_c130.py` | ビルダー（ライブの Blender で runpy）。形は `fp_section.py`（断面）・`fp_shell.py`（胴体・スロープ・上のふた・窓）・`fp_parts.py`（翼・エンジン・尾翼・フロートと支柱）・`fp_detail.py`（外の作り込み・窓枠・ガラス）・`fp_interior.py`（機内）・`fp_cockpit.py`（操縦席）、AO は `fp_bake.py` |
| `source/blender/floatplane_c130.blend` | 編集用の原本（Blender 5.1） |
| `source/build_report.json` | 三角形の数・部品・Blender で測った寸法・AO を焼いた時間 |
| `source/godot_probe.json` | Godot での確かめ（25 項目）と寸法の表 |
| `source/previews/godot_*.png` | Godot の実画面（外 5・機内 5・操縦席 2） |

## ゲーム側の約束（計画書 4.2）

- 原点：海面（浮いているときの水面）× 機体の中心線 × 主翼の翼弦の中央（機首から 6.6 m）。+Y が上、**機首が −Z**。設計の u（機首から後ろ）は z = u − 6.6、v（海面から）は y = v。
  浮いているときは `position.y` を海面の高さにする。
- 材質は名前で探す：`FP_Paint`（白）・`FP_Navy`・`FP_StripeOrange`・`FP_StripeBlue`・`FP_Glass`・`FP_Interior*`（`FP_InteriorBlanket`・`FP_InteriorFrame`・`FP_InteriorFloor` ほか）・
  `FP_SeatWebbing`（背もたれのベルト）・`FP_SeatFabric`（座面の布）・`FP_LightRed`・`FP_LightGreen`。`build()` が名前ごとに作り替える（色・粗さ・金属は GLB から、テクスチャと AO はクラスの表から）。
  2026-10-22 に足した名前：`FP_Exhaust`（排気口）・`FP_WingEdge`（主翼の前の縁）・`FP_Slime`（編隊灯、弱く光る）・`FP_WindowDark`（降下の扉の小窓）・`FP_Lens`（着陸灯）・
  `FP_KnobBlack`（つまみ・計器の縁）・`FP_Glareshield`（日よけ。`FP_InteriorSeat` と同じく布の織り目を三方向から貼る）。
- 関数（`SuddenDeathFloatplane`）：

| 関数 | 中身 |
| --- | --- |
| `build(quality)` | 読み込み・材質の作り替え・画質（`with_pilot = false` を先に入れるとハテナを載せない）。2 回目からは画質だけ変える |
| `set_ramp(t)` | 0 ＝ 閉じる（上へ 25°）、1 ＝ 床と水平。作動筒（`RampCyl_*`・`RampRod_*`）も付いていく。1 を超えると床より下へ下がり、`RAMP_GROUND`（1.8）で床から 20° 下（端が喫水線から 0.81 m。着地台の浮き輪に載せる。2026-10-19、W6 が足した） |
| `set_upper_door(t)` | 尾の下のふた。0 ＝ 閉じる、1 ＝ 後ろの端の蝶番で前を上げて尾の中へ（28.16°、前の端の下面が海面から 5.00 m） |
| `set_props(speed, reverse := false)` | 回転 0〜1（だんだん追いつく。`snap_props` ですぐ）。`reverse` で羽根を −42° ねじる（逆推力）。速さ 0.45 から円盤に替える（画質「低」は替えない） |
| `set_flaps(t)` / `set_jump_light(state)` | フラップ 0〜1（30°）。ランプ `"off"`・`"red"`・`"green"`（光ると開口のまわりを照らす） |
| `set_pontoon_spray(amount)` | フロートのしぶき（船首・船底の段・船尾 × 左右、0〜1） |
| `marker(name)` / `seat_transform(player)` / `pilot_transform()` | ワールドの Transform3D。P1 は機体の右の壁（+X）のベンチ |
| （足した関数）`set_cabin_lighting(mode)` | 機内の灯：`"day"`（暖かい白）・`"red"`（降下の前の赤い照明）・`"off"`。機体の外にカメラがあるときは `"off"` にすると軽い |
| （足した関数）`set_belt(player, on)` / `ramp_edge_now()` / `marker_local(name)` | 腰のベルトの表示／今のスロープの端（ワールド）／ローカルのマーカー |

- マーカー（`floatplane_c130_layout.json` の `markers`）：basis の **+Z が人の向き**（StagingPuppet の yaw と同じ）。`MK_Cam*` だけはカメラの向き（−Z が見る向き）で、そのまま `camera.global_transform` に入れてよい。

| マーカー | 位置（ローカル） | 中身 |
| --- | --- | --- |
| `MK_SeatP1` / `MK_SeatP2` | (±1.76, 2.56, 0.80) | 座った pelvis（ももの下面＝座面 2.38）。向きは通路の向かい（P1 は −X、P2 は +X） |
| `MK_StandP1` / `MK_StandP2` | (±1.15, 1.90, 0.80) | ベルトを外して立つ足もと |
| `MK_RampHinge` / `MK_RampEdge` | (0, 1.90, 4.60) / (0, 1.90, 7.80) | スロープの付け根と、開いた端の上面（飛び出す位置） |
| `MK_DeckDoor` / `MK_PilotSeat` | (0, 2.95, −3.40) / (0, 3.20, −4.85) | 操縦席の出入り口（段の上）と、ハテナの原点（足元の基準、機首を向く） |
| `MK_CamAft` / `MK_CamFwd` | (0, 4.55, −3.50) / (0, 3.60, 4.35) | 機内のカメラ（段の上から後ろ、P1 が左）／スロープの付け根から前 |
| `MK_TailEnd` | (0, 5.30, 11.45) | 尾の一番後ろ（水路で床の壁から 0.5 m に合わせる） |
| `MK_JumpLight` | (0, 5.40, 4.28) | 降下のランプ（開口の上。赤が +X、緑が −X） |
| ほか | | `MK_CockpitLight`・`MK_CabinLight1〜3`、しぶきの `MK_SprayBow_*`・`MK_SprayStep_*`・`MK_SprayStern_*` |

- 尾の下の通り道：上のふたを開けると、尾の下は動かない「ほお」（胴体の下の両わき）のあいだが開く。後ろへ行くほど狭く、ほおの下の端が高くなる
  （layout の `tail_passage`：z 7.8 で半幅 1.27・ほおの下端 3.28、z 9.4 で 0.88・4.23、z 10.6 で 0.52・4.74）。昇降台から尾の下をくぐる 2 人は、尾の先ほど真ん中寄りに通すとよい。
- 機内の光：ダウンライトはスポットライト 24（画質「高」から座席の上の 4 つに影）、非常灯 5、操縦席 1、計器の明かり。貨物室は「室内」の反射プローブ（`CabinProbe`）で環境光を暖かい暗めの色にしている
  （空の青い光で機内が白っぽくならない）。プローブは貨物室の内張りの内側だけ（外板は入れない）。
- 画質「低」：ダウンライトは 3 つに 1 つ（そのぶん強く）、影なし、プロペラの円盤なし、しぶきを減らす、ハテナは軽い版。

## 寸法（Godot に読んだ形で測った値と、`c130_design.py` の差。基準は 5 cm 以内）

`scripts/world/sudden_death/floatplane/floatplane_c130_probe.gd` が Godot に読んだ GLB の頂点から測る（2026-10-19）。最大の差は全長の +3.0 cm（垂直尾翼の後ろの縁の根元が設計の点 18.05 の位置にある）。

| 項目 | c130_design.py | Godot で測った値 | 差 |
| --- | ---: | ---: | ---: |
| 全長（機首〜尾の端） | 18.000 | 18.030 | +0.030 |
| 翼の幅 | 24.000 | 24.000 | +0.000 |
| 高さ（フロートの底〜尾翼の上） | 10.150 | 10.154 | +0.004 |
| 胴体の幅 | 4.400 | 4.400 | +0.000 |
| 胴体の高さ | 4.200 | 4.200 | +0.000 |
| 貨物室の長さ | 8.000 | 8.005 | +0.005 |
| 貨物室の幅（内のり） | 4.040 | 4.040 | +0.000 |
| 貨物室の立てる高さ | 3.720 | 3.720 | +0.000 |
| 後ろの開口の幅 | 3.100 | 3.100 | +0.000 |
| 後ろの開口の高さ | 3.300 | 3.300 | +0.000 |
| スロープの長さ | 3.200 | 3.200 | +0.000 |
| スロープの幅 | 3.100 | 3.100 | +0.000 |
| プロペラの直径 | 2.800 | 2.803 | +0.003 |
| フロートの長さ | 14.200 | 14.200 | +0.000 |
| フロートの直径 | 1.700 | 1.700 | +0.000 |
| フロートの喫水 | 0.650 | 0.650 | +0.000 |
| フロートの間 | 7.200 | 7.200 | +0.000 |
| 貨物室の床（海面から） | 1.900 | 1.900 | +0.000 |
| 操縦席の床（海面から） | 2.950 | 2.950 | +0.000 |

- 貨物室の幅・立てる高さは内張り（断熱材の後ろの面）で測った値。断熱材のふくらみ（最大 7 cm）と骨組み（8.5 cm）のぶん、通れる所は少し狭い。
- 後ろの開口は貨物室の後ろの端の枠（u 10.95〜11.19）。スロープの付け根はその後ろ（u 11.2）。

## 確かめの画（Godot の実画面、`source/previews/`）

`godot_ext_34`・`godot_ext_side_left`・`godot_ext_nose`・`godot_ext_float`・`godot_ext_rear_open`（スロープと上のふたを開き、プロペラを回した形）、
`godot_int_aft`（`MK_CamAft`、座った 2 人の人形）・`godot_int_fwd`（`MK_CamFwd`）・`godot_int_red_open`（赤い照明・赤いランプ・スロープを開いた形）・`godot_int_seats`・`godot_int_wall`、
`godot_cockpit`・`godot_cockpit_side`（ハテナと計器盤）、2026-10-22 に足した `godot_cockpit_eye`（演出の操縦席の目 `COCKPIT_EYE`）・`godot_cockpit_back`（左うしろから天井の盤と台）・
`godot_ext_engine`（エンジンの覆いとプロペラ）・`godot_ext_float_bow`（フロートの船首）。舞台の空と海（`StageEnvironment.create_stage_sky()`・`create_ocean_surface()`）の上で撮る。

Godot のエディターを開いたまま GLB を書き直したときは、`filesystem_manage(reimport)` のあと `scan` をかけ、`.godot/imported/floatplane_c130.glb-*.scn` の時刻が
GLB より新しくなってから確かめを走らせる（取り込みは後で行われる。前の取り込みのまま撮ってしまう）。

## 作り直し方

1. テクスチャを直すとき（普通の Python、numpy・Pillow）：
   ```powershell
   python assets/vehicles/floatplane_c130/source/make_textures.py
   ```
2. ライブの Blender（Higgsfield の Blender 連携）で次を実行する。使う前に `artifacts/sudden_death_v2/BLENDER_IN_USE.txt` を見て、空いていれば名前と時刻を書き、`.blend` を保存したら消す。
   ビルダーは GLB・layout を書き、AO を焼いて `.blend` を保存する（約 11 秒）。`"--no-export"`・`"--no-save"`・`"--no-bake"` で試せる
   ```python
   import runpy, sys
   sys.argv = ["blender", "--"]
   runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/vehicles/floatplane_c130/source/blender/build_floatplane_c130.py", run_name="__main__")
   ```
3. Godot で取り込みを更新し、確かめる（25 項目と寸法の表。2 つ目は実画面を撮る）
   ```powershell
   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/world/sudden_death/floatplane/floatplane_c130_bootstrap.gd
   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://scripts/world/sudden_death/floatplane/floatplane_c130_bootstrap.gd -- shots=assets/vehicles/floatplane_c130/source/previews
   ```

## 決めたこと（設計にない数）

- 断面は上下で丸みの違う超楕円（いちばん太い高さは貨物室で海面から 2.9 m、上の丸み 3.2・下 4.0）。貨物室の床の幅がスロープの幅 3.10 とそろう。
- スロープは閉じると付け根から上へ 25°（上面の長さ 3.20 で端が u 14.1）。開くと床と水平で、端は u 14.4（尾の端から 3.65 m。昇降台の 4.1 m とつながる）。
- 上のふた（尾の下）は、胴体の半幅 × 0.75 より内側の下の面。両わきは動かない「ほお」。後ろの端の蝶番で 28.16° 前を上げると尾の中に収まる
  （外板から出ないことをビルダーの計算で確かめた。前の端の下面は海面から 5.00 m ＝ スロープの床から 3.10 m、設計の「尾の下のすき間 3.1」）。
- 骨組みは丸窓（u 5.4・7.6・9.8）の両わき ±0.42 に置き、間は 0.56〜0.68 m。乗員の扉（左の壁、u 3.38〜4.30）の上では左の骨組みを切る。
- 背もたれのベルトは |x| 1.925（座る位置の pelvis から 16.5 cm 後ろ）。断熱材は座席の後ろだけ薄くしてベルトの後ろに収めた。
- 操縦席の座面はハテナの原点から 0.48 m 上（ヘリと同じ）。操縦かんの握りはハテナの原点から (±0.586, +0.818, −0.361)（ヘリと同じ）。
- 操縦席の窓（2026-10-19、ユーザーの指示「窓が狭く、ハテナの目の高さに合っていない」「前の 4 枚は実機のように上を短く」
  「前のいちばん外の窓は横の窓に沿う形に、横の窓は前の窓の上の辺に合わせて線を入れる」、実機 C-130 の前の写真が手本）：
  - 前の真ん中の 2 枚（|x| 0.04〜0.60）：v 4.15〜4.68（もとは 4.48〜4.97。下を計器盤のひさし v 4.12 のすぐ上まで、上を低く）。
  - 角の窓（もとの前の外の 2 枚 |x| 0.66〜1.16 の代わり）：真ん中の窓のとなり（外板の |x| 0.66、柱 6 cm）から角を回り込み、
    横の窓の前の柱（u 1.26〜1.32）まで。高さは前の窓と同じ v 4.15〜4.68（`CORNER_PANE`）。内の縁は外板の |x| 0.66 の線そのもの
    （`corner_inner_u`・`corner_uv`。真ん中の窓の外の縁 |x| 0.60 と平行で、あいだの柱は上から下まで 6 cm）。
  - 横の窓：前の窓の上の辺（v 4.68）を真ん中に横の枠（すき間 6 cm）を入れて、下の段（v 4.13〜4.65）と上の段（ブロウ窓、
    v 4.71〜上の端はもとのまま）に分けた。下の端はもとの 4.44〜4.50 から 4.13〜4.17 へ下げた。
  - 座ったハテナの目（v 約 4.4）が前の窓の中、頭のてっぺんは窓の上の外板に隠れる。ワイパーは前の窓の下の縁にそって止めた姿。
  - 数は `fp_shell.py` の `FRONT_PANES`・`FRONT_V`・`CORNER_PANE`・`SIDE_PANES`・`SIDE_X`（横の窓の型は |x| 0.63 から：前の窓の型と
    重なるとブーリアンが崩れる）、ワイパーは `fp_detail.py` の `build_wipers`。機内から窓を抜けるカメラの道すじ
    （`floatplane_staging.gd` の `WINDSHIELD_IN`・`WINDSHIELD_OUT`、x −0.5 で真ん中の窓を通る）はこの窓の高さに合わせる。
