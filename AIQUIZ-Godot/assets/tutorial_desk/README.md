# 机のセット（ローカル2Pの説明画面の始め・実写）

ローカル2Pの説明画面の始め（2人が座る → 手を添える → 準備完了 → モニターの中へ）を実写にするための、夜の部屋のセットと、
等身大のブロックマン 2 人（P1 オレンジ・P2 水色）と、座る動き。計画は [docs/new_tutorial/desk_intro/plan.md](../../docs/new_tutorial/desk_intro/plan.md)、
作る物の一覧は [scene_passport.md](../../docs/new_tutorial/desk_intro/scene_passport.md)。

- `tutorial_desk.glb`：Godot へ取り込むための書き出し（約 4.5MB）。2026-11-03 にゲームはブロックマン前の机（`scripts/ui/tutorial_keyboard_desk_3d.gd` の手続きの机）へ戻したので、今はゲームから使っていない。
- `source/tutorial_desk.blend`：Blender の元ファイル（シーン `TutorialDesk`）。`source/` は `.gdignore` で Godot に読み込ませない。
- 作り直すときは、ライブの Blender（Higgsfield の Blender 連携の `bl_execute`）で、次の順に実行し、終わったら `.blend` を上書き保存する。
  ```python
  import runpy
  base = r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/tutorial_desk/source/blender/"
  runpy.run_path(base + "build_tutorial_desk.py")["build"]("detail")   # セット（"blockout" は箱だけの配置）
  runpy.run_path(base + "build_tutorial_people.py")["build"]()         # ブロックマンと座った姿勢（約 11 秒）
  runpy.run_path(base + "build_tutorial_motion.py")["build"]()         # 座る動きとカメラ（24 fps・132 コマ）
  runpy.run_path(base + "export_tutorial_desk.py")["export"]()         # tutorial_desk.glb
  ```
  それぞれ自分の `TD_` のコレクションの中だけを作り直す。人物を作り直したら、動きと書き出しもやり直す。
  書き出した後は Godot で取り込み直し（`--headless --path . --import`）、`tests/tutorial_keyboard_desk_unit.gd` を流す。
- `source/blender/build_tutorial_desk.py`：部屋・机・モニター・キーボード（64 キー）・椅子・デスクライト・ハテナのフィギュア・カメラ・ライト。
- `source/blender/build_tutorial_people.py`：MPFB2（Blender の拡張機能 `mpfb`）の骨組み `mixamo` に、骨ごとの角を丸めた箱を付けたブロックマン。
  キーに置く手は、指ごとに指先（指の箱のいちばん低い点）をキーの天面の真ん中へ合わせる（`place_typing_hand`）。
- `source/blender/build_tutorial_motion.py`：立つ → 座る → 椅子ごと寄る → 手をキーへ。カメラ `CAM_Intro` は D1 → D5 を 1 本で寄る。
- `source/blender/export_tutorial_desk.py`：glb への書き出し。キーの文字は書き出す間だけ形（`LEGM_`）に置き換える。ライトは書き出さない（Godot で作る）。
- `source/key_layout.json`：ゲームのキー配列（64 キー）。`tools/tutorial_desk/export_key_layout.gd` で書き出す。
  キーの物の名前は英字（`KEY_Left`、`KEY_Backslash` など）で、ゲームのキーの id はカスタムプロパティ `key_id` に入っている（glb では extras）。
