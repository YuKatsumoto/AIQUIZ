# 乗り込めるヘリ（helicopter_boarding）

オンライン対戦のマッチング演出で使うヘリ。プレイヤーが左のドアから乗り込み、操縦士ハテナ（等倍）と並んで座る。
設計は `artifacts/heli_blueprint/`（図 1〜9）。オンライン対戦のメニュー（`scripts/world/online_heliport/online_heliport_helicopter.gd`）と、
本編・メニューの迎え・オンラインのヘリ登場（`scripts/world/helicopter_arrival_director.gd`、計画書 M9）で使っている。発進は左右のジェットのポッド。

見た目：かわいい形のまま、機械の作り込み（屋根のカバー・吸気口・排気・ローターの頭・3 枚羽根・フェネストロンの尾・機首の機器・
ヒンジ・ホイスト・スキッドの金具・コックピットの計器）を足した。帯より下と尾翼は濃紺（色替えしない）、上はプレイヤーの色、
白い帯の上下に細い線。デカールは「AIQUIZ」のロゴ・機体番号（AQ-01 / AQ-02）・ハテナの紋章・黄黒の帯だけ（注意書きの文字はない）。後ろの仕切りはコルクボードで、操縦士ハテナがこれまで乗せた人との写真 4 枚（ゴールで肩組み・幽霊ザメに二人乗り・客席でウェーブ・「？」のポーズ）と、ハテナのシール・画びょうを貼ってある（風防越しに見える）。ロゴを変えたときは `tools/logo_editor/apply_logo.py` が `hb_decals.png` のロゴの 2 マスだけを描き直す（機体の UV はそのまま）。

## ファイル

| ファイル | 内容 |
|---|---|
| `helicopter_boarding.glb` | ゲームで使うヘリ。三角形 35,558、面（surface）78、材質 19、テクスチャ 1 枚（デカールのアトラス 2048²）。頂点色に AO |
| `helicopter_boarding_hb_decals.png` | GLB から Godot が取り出したアトラス（`.import` は VRAM 圧縮・高品質（BC7）・ミップマップ。取り込み直しても残る） |
| `helicopter_boarding_layout.json` | マーカー（MK_*）、ドアのヒンジ、ローター・尾のファン・ハッチの軸、`skid_drop`、ジェット（`jet_boost`）、ガラスの帯（`glass`）、塗装と機体番号（`livery`） |
| `source/blender/build_helicopter_boarding.py` | ビルダー（ライブの Blender で runpy）。形は `hb_shell.py`（胴体）・`hb_parts.py`（ローター・尾・スキッド・灯・ジェット）・`hb_detail.py`（屋根・機首・ヒンジ・腹）・`hb_cockpit.py`（コックピット）、デカールは `hb_textures.py`（アトラスを描く）と `hb_decals.py`（外板に貼る） |
| `source/textures/hb_decals.png` / `hb_decals_regions.json` | ビルダーが描くアトラスと、領域の表（左下が原点の px） |
| `source/textures/board_photos/*.png` | 後ろのコルクボードの写真（768² の正方形 4 枚。Godot の本物のステージ・観客・ハテナ・プレイヤーで撮る：`tests/heli_board_photos.gd`）。アトラスの `BOARD` へ縮めて貼る。配置は `hb_cockpit.BOARD` |
| `source/heli_pilot_spec.json` | ビルダーが読む数値（設計図 `artifacts/heli_blueprint` が書き出す写し。`artifacts/` は git の管理外なので、ここに置く） |
| `source/blender/helicopter_boarding.blend` | 編集用の原本（Blender 5.1。アトラスを詰めてある） |
| `source/blender/SCENE_PASSPORT.md` | 作り方の約束（部品・材質・確かめ方） |
| `source/previews/` | 確認レンダー（Blender の `hb_01〜24`、Godot の `godot_*.png`） |
| `source/build_report.json` | 三角形・面の数、AO、デカールの貼り具合、チェックの結果（61 行） |
| `source/blender/backups/` | 段階ごとの写し（`*_before_detail` は作り込み前、`auto/` は書き出す前の GLB の写し） |

## ゲーム側の約束（Godot）

- 原点：メインローターの軸 × 地面から `skid_drop`（1.75 m）。デッキの上に置くときは `position.y = デッキの高さ + skid_drop`。機首は -Z
- 材質は名前で探す（ノード名ではない）。`OnlineHeliportHelicopter.prepare_surface_material()` が 1 つずつ作り替える：
  - `BodyPaint`：色替え（`set_tint`）＋クリアコート。`BodyAccent`（帯より下・尾翼の濃紺 #1D2F5C）：色替えしない＋クリアコート。`Trim`：クリアコート
    （glTF のクリアコートは Godot 4.7 が読まないので、つやはここで足す）
  - `Windows`：`shaders/heli_glass.gdshader`。風防（`Windows`）だけサンバイザーの帯（高さは layout の `glass.visor_y`）
  - `Decal` / `DecalNumber`：`configure_decal_material()`（アルファで重ねる・深度を書かない・`render_priority = -8`・頂点色を掛ける）。
    ガラス・ローターの円盤・炎より先に描く。影は落とさない。`Interior` の `Decal`（計器盤の銘板・後ろのコルクボード）は紙なので別の材質にし、
    クリアコートを付けず `roughness = INTERIOR_DECAL_ROUGHNESS`（0.85。天井の灯が白く照り返さない）
  - 機体番号：`set_livery_slot(slot)`（1 = AQ-01、2 = AQ-02）。`DecalNumber` を機体ごとに複製し、`uv1_offset = livery.number_uv_step × (slot − 1)`
  - 灯（`Beacon`・`NavLight_*`・`LandingLight`・`StrobeLights`・`JetGlow_*`）は面が 1 つ。覆いは `Body` に入れてある
- 画質：`apply_quality(quality)`。低ではローターを円盤にせず、デカールの異方性フィルタを切る
- ドア：`Door_L` / `Door_R` の原点はヒンジの前端。ローカル +Z がヒンジの線。
  開ける：`door.basis = rest_basis * Basis(Vector3(0, 0, 1), deg_to_rad(open_deg))`（左 -90°、右 +90°、0.6 秒）。
  屋根の上ではドアがヒンジの線より内側（|x| 0.22 まで）を通るので、屋根に部品を足すときは `build_report.json` の `shell.door_keepout` の表を見る
- メインローター：`MainRotor` はハブ（ローカル Y で回す。回っても見えたまま）、子の `MainRotorBlades` が羽根 3 枚（止めると 1 枚が機首の上＝`park_deg` 0）。
  回っている間は羽根を隠して、ぼかした円盤に替える
- 尾：フェネストロン（直径 0.90、羽根 10 枚）。`TailRotor` はファンの羽根だけで、原点はファンの中心、ローカル X で回す。回っている間は `TailFanDisc` に替える
- 表示の切り替え：`Belt_L` / `Belt_R` はふだん隠し、座ったら出す。`Booster_R` はハテナが右の席にいるときだけ。`Beacon` は点滅、
  `StrobeLights`（尾の白いストロボ）はローターが回っている間だけビーコンと交互に光る
- 立ち位置・座る位置は `MK_*` を読む（定数を書かない）。プレイヤーの位置合わせは足の裏の実測で行う（BASE_Y では合わない）
- ジェットブースト：`JetPod_L` / `JetPod_R` の原点は肩のヒンジ、ローカル +Z がヒンジの線。ふだんは 38° 下へたたんである。
  広げる：`pod.basis = rest_basis * Basis(Vector3(0, 0, 1), deg_to_rad(deploy_deg))`（左 -38°、右 +38°）で翼が水平になり、噴射口が真後ろ（+Z）を向く。
  子の `JetNozzle_*`（羽根）は x・y を `nozzle_open_scale`（1.35）倍に広げ、`JetGlow_*`（材質 `JetGlow`）の発光を強める。
  炎はポッドのローカルの `nozzle_exit_local` から +Z へ（`HelicopterBoostExhaust`）。操作は `OnlineHeliportHelicopter.set_jet_charge()` / `ignite_jets()`
  煙は SmokeVFX（`HelicopterBoostSmoke`）。出すのはオンラインの発進（急発進、`ignite_jets(true)`）だけ：噴射口の後ろの空中に残って広がり、ジェットを切っても漂って消える。
  原点を動かさない飛行では `drift_jet_smoke()` で海と雲といっしょに流し、ヘリを消す前は `release_jet_smoke()` で煙だけ残す
- まとめた部品：座席・操縦かんは `Interior`、ステップは `FrameAndSkids`、床下ハッチの井戸と枠は `Body` に入っている（描く回数を減らすため。名前で探さないこと）
- `Booster_R` は右の座席のかさ上げ（ハテナ用）で、ジェットとは別

## 作り直し方

0. コルクボードの写真を撮り直すときは、Godot で次を実行して `source/textures/board_photos/` を書き直す（4 枚で約 15 秒。`-- only=shark` でその 1 枚だけ。
   ポーズ・カメラの調整値は `-- key=value` で試せる。`-- preview` を付けると本物の写真を書き換えず `artifacts/heli_board_photos/preview_<名前>.png` に撮る）。
   「はてな？」の写真のプレイヤーのポーズは、`tests/heli_board_photos.gd` の先頭の表 `HATENA_PLAYER_POSE` で決める。そのあと下の 2. でヘリを作り直す
   ```powershell
   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 768x768 --script res://tests/heli_board_photos_bootstrap.gd
   ```
1. 設計を直すときは `artifacts/heli_blueprint/heli_design.py` を直し、`python artifacts/heli_blueprint/make_blueprint.py spec` で
   `heli_pilot_spec.json` を書き直す（`make_blueprint.py` だけなら図面も作り直す。ドアの通り道の計算で 10 分ほどかかる）
2. ライブの Blender（Higgsfield の Blender 連携）で次を実行する。チェックが通れば GLB・layout を書き、確認レンダーを出して `.blend` を保存する
   ```python
   import runpy, sys
   sys.argv = ["blender", "--"]      # 試すときは "--no-render", "--no-save"。"--views=hb_24" でその確認レンダーだけ
   runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/vehicles/helicopter_boarding/source/blender/build_helicopter_boarding.py", run_name="__main__")
   ```
3. Godot で取り込みを更新し、確かめる
   ```powershell
   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/helicopter_boarding_check.gd
   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/helicopter_boarding_bootstrap.gd
   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/helicopter_boarding_bootstrap.gd -- shots=assets/vehicles/helicopter_boarding/source/previews
   ```
