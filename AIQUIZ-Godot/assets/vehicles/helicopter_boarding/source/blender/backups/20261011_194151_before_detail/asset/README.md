# 乗り込めるヘリ（helicopter_boarding）

オンライン対戦のマッチング演出で使うヘリ。プレイヤーが左のドアから乗り込み、操縦士ハテナ（等倍）と並んで座る。
設計は `artifacts/heli_blueprint/`（図 1〜9）。オンライン対戦のメニュー（`scripts/world/online_heliport/online_heliport_helicopter.gd`）と、
本編・メニューの迎え・オンラインのヘリ登場（`scripts/world/helicopter_arrival_director.gd`、計画書 M9）で使っている。発進は左右のジェットのポッド。

## ファイル

| ファイル | 内容 |
|---|---|
| `helicopter_boarding.glb` | ゲームで使うヘリ。三角形 11,036、材質 15、テクスチャなし（頂点色に AO） |
| `helicopter_boarding_layout.json` | マーカー（MK_*）の位置と向き、ドアのヒンジ、ローター・ハッチの軸、`skid_drop`、ジェットのポッド（`jet_boost`） |
| `source/blender/build_helicopter_boarding.py` | ビルダー（ライブの Blender で runpy）。`hb_common.py`・`hb_shell.py`・`hb_parts.py` を使う |
| `source/heli_pilot_spec.json` | ビルダーが読む数値（設計図 `artifacts/heli_blueprint` が書き出す写し。`artifacts/` は git の管理外なので、ここに置く） |
| `source/blender/helicopter_boarding.blend` | 編集用の原本（Blender 5.1） |
| `source/blender/SCENE_PASSPORT.md` | 作り方の約束（部品・材質・確かめ方） |
| `source/previews/` | 確認レンダー（Blender の `hb_*.png`、Godot の `godot_*.png`） |
| `source/build_report.json` | 三角形の数・AO の焼き込み・チェックの結果 |

## ゲーム側の約束（Godot）

- 原点：メインローターの軸 × 地面から `skid_drop`（1.75 m）。デッキの上に置くときは `position.y = デッキの高さ + skid_drop`。機首は -Z
- 色替え：材質 `BodyPaint` の面の `albedo_color` を替える（`OnlineHeliportHelicopter._prepare_body` と同じ）。
  ノード名ではなく材質名で探すこと（`Body` には白い帯・内張りも入っている）
- ガラス：材質 `Windows`（`_apply_window_glass` と同じ）
- ドア：`Door_L` / `Door_R` の原点はヒンジの前端。ローカル +Z がヒンジの線。
  開ける：`door.basis = rest_basis * Basis(Vector3(0, 0, 1), deg_to_rad(open_deg))`（左 -90°、右 +90°、0.6 秒）
- ローター：`MainRotor` はローカル Y、`TailRotor` はローカル X で回す。止めるときは前後（`park_deg` = 0）にそろえる
- 表示の切り替え：`Belt_L` / `Belt_R` はふだん隠し、座ったら出す。`Booster_R` はハテナが右の席にいるときだけ。`Beacon` は点滅
- 立ち位置・座る位置は `MK_*` を読む（定数を書かない）。プレイヤーの位置合わせは足の裏の実測で行う（BASE_Y では合わない）
- ジェットブースト：`JetPod_L` / `JetPod_R` の原点は肩のヒンジ、ローカル +Z がヒンジの線。ふだんは 38° 下へたたんである。
  広げる：`pod.basis = rest_basis * Basis(Vector3(0, 0, 1), deg_to_rad(deploy_deg))`（左 -38°、右 +38°）で翼が水平になり、噴射口が真後ろ（+Z）を向く。
  子の `JetNozzle_*`（羽根）は x・y を `nozzle_open_scale`（1.35）倍に広げ、`JetGlow_*`（材質 `JetGlow`）の発光を強める。
  炎はポッドのローカルの `nozzle_exit_local` から +Z へ（`HelicopterBoostExhaust`）。操作は `OnlineHeliportHelicopter.set_jet_charge()` / `ignite_jets()`
- `Booster_R` は右の座席のかさ上げ（ハテナ用）で、ジェットとは別

## 作り直し方

1. 設計を直すときは `artifacts/heli_blueprint/heli_design.py` を直し、`python artifacts/heli_blueprint/make_blueprint.py spec` で
   `heli_pilot_spec.json` を書き直す（`make_blueprint.py` だけなら図面も作り直す）
2. ライブの Blender（Higgsfield の Blender 連携）で次を実行する。最後に `.blend` を保存する
   ```python
   import runpy, sys
   sys.argv = ["blender", "--"]
   runpy.run_path(r"C:/AIQUIZ/AIQUIZ-Godot/assets/vehicles/helicopter_boarding/source/blender/build_helicopter_boarding.py", run_name="__main__")
   ```
3. Godot で取り込みを更新し、確かめる
   ```powershell
   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/helicopter_boarding_check.gd
   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/helicopter_boarding_check.gd -- shots=assets/vehicles/helicopter_boarding/source/previews
   ```
