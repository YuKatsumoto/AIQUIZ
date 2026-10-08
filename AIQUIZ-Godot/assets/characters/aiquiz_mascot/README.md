# ハテナ（AIQUIZのマスコット）

ゲームのスタッフ役を務めるオリジナルのマスコット。クイズの精で、白い丸い体がオレンジの「？」の点になっている。担当する役は次の3つ。
- ヘリの操縦士
- ノコギリの操縦席
- ゴールとスコアタワーの審判

ゲームクリエイター甲子園の応募規定「版権のあるキャラクターの使用は禁止」に合わせ、2026-10-08にGodotのプラシュ（godot-plush）由来のキャラクターから置き換えた。最初はカモメ船長に置き換え、同じ日にハテナへ変更した。

## 素材

| ファイル | 内容 |
|---|---|
| `mascot_model.glb` | 骨格 `Rig`（16本の `DEF-*`）と本体メッシュ `HERO_Mascot`。<br>・約3.5万三角形、高さ2.04m（「？」込み）<br>・単色の材質が8つで、テクスチャはない<br>・アニメーションは含まない |
| `source/aiquiz_mascot.blend` | 編集用の原本（Blender 5.1）。コレクションは次のとおり。<br>・`HATENA_Parts`：ハテナの部品（非表示。`build_hatena.py` が作り直す）<br>・`HATENA_Review`：確認用のカメラ<br>・`MASCOT_Final`：骨格と完成した本体（`HERO_Mascot`）。前のカモメ船長（`HERO_Mascot_Kamome`）と手作業の試作（`HERO_Mascot_Handmade`）も非表示で残している<br>・`MASCOT_Concepts` / `MASCOT_Concepts2`：最初のデザイン案（ハテナは `CONCEPT_A_Hatena`） |
| `source/build_hatena.py` | ハテナの部品を組み立てるスクリプト |
| `source/fit_hatena.py` | 部品を骨格に載せてウェイトを付け、GLBに書き出すスクリプト |
| `source/fit_generated.py`、`build_mascot.py`、`generated_meshy_multiview.glb`、`concept_*.png`、`kamome_albedo_2048.jpg` | カモメ船長の時の素材。今は使っていない |

## 作り方

`CONCEPT_A_Hatena`（プリミティブで組んだ試作）を、Blender上で作り直した。生成AIは使っていない。

- **体**：細かく分割した立方体を楕円体（0.56×0.48×0.55m）に押し付けたもので、四角形の面が均等に並ぶ。
- **顔**（目・ハイライト・ほお・口）：楕円体の式から求めた表面の上に作る。体の曲面にぴったり沿うので、浮いたりめり込んだりしない。
  - 目は光沢のあるふくらみで、ハイライトは両目とも同じ側に大小2つ。
- **「？」**：少し平たい断面の筆跡にし、先端を玉で止める。体との境目に輪を付ける。
- **腕**：肩の玉、先が細くなるカプセル、ひじの玉、親指のあるミトン。
- **脚**：股の玉、カプセル、ひざの玉、スニーカー（紺の甲、白い靴底、白い履き口）。
- **大きさ**：骨格の初期姿勢に合わせてある。
  - 肩 (±0.52, 0, 0.819)、ひじ (±0.649, 0.014, 0.727)、手首 (±0.76, 0, 0.647)
  - 股 (±0.186, 0.006, 0.536)、ひざ z 0.384、足首 (±0.186, 0.011, 0.178)

ライブのBlenderで、`aiquiz_mascot.blend` を開いて順に実行する。

```python
exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/build_hatena.py', encoding='utf-8').read(), {})
exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/fit_hatena.py', encoding='utf-8').read(), {'fit_stage': 'build'})
exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/assets/characters/aiquiz_mascot/source/fit_hatena.py', encoding='utf-8').read(), {'fit_stage': 'export'})
```

ウェイトは部品ごとに決める。
- **体**：腰から頭へ z 0.78〜0.95 で切り替わる。顔の高さは頭のボーンに従う。
- **顔と「？」**：頭のボーンだけに従う。
- **腕・脚のカプセル**：ひじ・ひざで隣のボーンとなめらかにつなぐ。
- **関節の玉**：それぞれのボーンの根元に置いてあり、その場で回る。
- **靴**：足のボーンに従い、つま先側だけつま先のボーンに従う。

骨格は旧プラシュのものと同じ（ボーン名・親子関係・初期姿勢が一致）。そのため、各役の作り込まれた動き（審判の旗、操縦席の操作、ヘリの座り姿勢）はそのまま使える。Blenderでは、走る・手を振る・倒れる姿勢で変形を確かめた（`artifacts/mascot/hatena_pose_*.png`）。

## ゲームへの組み込み

- **ヘリの操縦士**：`scripts/world/helicopter_arrival_director.gd` の `PILOT_GLB` から、このGLBを直接読み込む。
  - 表示倍率は `PILOT_SCALE` = 0.35。「？」がコックピットの天井から出ない大きさにしてある。
- **審判・ノコギリ操縦席**：`scripts/world/mascot/mascot_dresser.gd`（`MascotDresser.dress()`）を使う。
  - `referee_finale.glb` と `saw_operator.glb` の骨格へ、本体メッシュとスキンを付け直す。
  - 両GLBの旧本体は、取り込み設定の `skip_import` で読み込まない。
- **書き出し設定**：`export_presets.cfg` の `exclude_filter` で、次のものを提出用ビルドから外している。
  - 旧プラシュのテクスチャ
  - 未使用の旧審判（`assets/animations/result_referee/`）
  - 設定ホールの `godotkun_*`
- `assets/characters/godot_plush/` は `.gdignore` でGodotの取り込み対象から外した。Blender側の旧ツールの参照用に残している。

## 検証

```powershell
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/mascot_rig_check.gd
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/mascot_capture_bootstrap.gd -- pilot
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/result_ceremony_bootstrap.gd --fixed-fps 60 -- runtime case=p2 fps=60 quality=high
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x900 --script res://tests/saw_operator_runtime_bootstrap.gd
```

- `mascot_rig_check`：次の3点を確かめる。
  - 両リグと骨格が一致していること
  - 旧本体を取り込んでいないこと
  - 着せ替えが成功すること
- `mascot_capture_bootstrap -- pilot`：コックピットの接写を `artifacts/mascot/` に保存する。
- GLBを書き出し直したあとは、Godotエディターでファイルシステムを再スキャンし、取り込みを更新してから確かめる。エディターの再インポート操作だけでは、取り込み結果が更新されないことがあった。
