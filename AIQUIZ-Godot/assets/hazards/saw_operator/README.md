# 連結チップソー操縦席（操作盤v3）

進行方向の左端に取り付ける、マスコット（ハテナ）着席済みの操縦席。2026-09-28に操作盤と操縦動作を1から作り直した（v3）。操縦者の16ボーン、座席と椅子ロケット部品、ドック取付部は変更していない。

## 素材

| ファイル | 内容 |
|---|---|
| `godot_console_v3.glb` | 実行時の操作盤。デッキ、座席台座、左右の操作ポッド、計器ダッシュ、ペダル、全操作部。140ノード・88メッシュ・約5.7万三角形・約2.4MB |
| `saw_operator.glb` | 座席（`OP_SeatFlightRoot`）、操縦者のリグ（旧プラシュ本体は `skip_import` で取り込まず、実行時に `MascotDresser` がハテナを着せる）、椅子ロケット部品、ドック取付部（`OP_MountFrame`）、着地基準（`OP_SeatSocket`）。v2の操作盤も含むが、実行時に取り除く |
| `console_horn.wav` / `console_switch.wav` | クラクション／キー・START音。`tools/saw_operator/build_console_audio.py` で生成（外部素材なし） |
| `source/saw_operator_v3.blend` | 編集用原本。`GodotConsole_V3` シーンのみ。分割された操作盤、参照用の現行ランタイム（`REF_`）、検査カメラ・ライト、Godotで評価した動き（30fps・1770フレーム、動作ごとのマーカー付き） |
| `source/evaluated_poses_v3.json` | Blenderプレビュー用の評価済み姿勢 |
| `source/passport_v3.md` | Scene Passport |
| `source/saw_operator.blend` ほか | v2の原本と資料（履歴） |

## 操作盤

- 左ポッド「DRIVE」：走行スティック（進行方向＝操縦者の左へ倒す）、キースイッチ、クラクション、速度LEDバー、回転灯、F/Rランプ。
- 右ポッド「BLADE」：昇降スティック（引くと上昇）、保護カバー付きSTART、トリムダイヤル、高さLEDバー、非常停止（飾り）、UP/DNランプ。
- 計器ダッシュ：SPEED・RPM・LIFTの3計器（270°・赤帯付き）、PWR/RDY/SAW/LIFT/WARNの5灯、前面の「AIQUIZ SAW」銘板（2026-10-08に変更）と安全ストライプ。
- 手の接触点はリグから実測した到達範囲（肩から手首0.237m、手のひらは手首の0.08m前）内に配置。デッキ寸法1.64×1.74m、刃の可動域とのすき間130mm、昇降台内への収まりはv2と同じ。
- 表示灯・LEDバー・回転灯はノードごとに発光マテリアルを複製し、Godotが状態に応じて発光量を変える。

## 動作（`scripts/world/saw_operator_presentation.gd`）

すべて `sample()` の時刻と入力から決まり、フレームレートやリプレイのシーク順に依存しない。

| 場面 | 動き |
|---|---|
| 搬出 | 船の昇降・横移動の揺れ、デッキ展開の前後の揺れ、床下げで床を見て着地の弾み。走行スティックで台車を操る |
| 待機（デッキ展開後の待機時計、6.5秒ごと） | 見回し → 手遊び（両手でスティックを交互にトントン）→ 伸び（両手を上げて反り、足を浮かせる）→ うたた寝（首が落ちてハッと起きる）→ 足ぶらぶら → 手振り、の固定順（12枠で重複なし） |
| 始動（着地後の加速時刻） | 左手でキーをひねる（表示灯・計器の自己診断）、右手で保護カバーを開け、振りかぶってSTARTを叩く（前傾・うなずき・スイッチ音）、右手でガッツポーズ、両手をスティックへ。視線はカバー→RPM計→進行方向 |
| 追走（7.2秒周期） | 計器確認／左の進行方向へ前傾して追う／昇降計とLEDの確認、のあとにダイヤル調整／座席でノリノリ／なし（固定順）。スティックの微修正、昇降中は右の計器を見る |
| 捕獲 | 左手でクラクションを2回（音あり）、左手のガッツポーズ、座席で弾んで足をばたつかせ、進行方向を見る |
| 停止（全員脱落の減速） | スティックを戻し、左手でキーOFF（表示灯消灯）、右手で保護カバーを閉め、背もたれに寄って一息 |
| メニューの収納（壁速度タブ、収納時計p） | 右手でBLADEスティックを引き続けて収納を指令（UPランプ・右LEDバーに進捗）、ブレーキ中はRPM計、ラックの上昇を見上げ、頭上を通過する間は左手で頭を押さえてかがみ、背後へ吊り下がるラックを振り返り、ロックでうなずく。格納中は左手のガッツポーズのあと待機しぐさを繰り返す。展開は同じpを逆にたどり、スティックは押し側（DNランプ）。回転灯とWARN灯は機械が動く間だけ点く。途中反転はスティックが中立を通って連続的に切り替わる |
| ポーズ・結果 | 姿勢を保持。リトライ・スキップは配置済み、リプレイは記録から再評価 |

椅子ロケットのベルト・飛行姿勢は `SeatLaunchPresentation` が従来どおり制御する。

## 原本の編集と再出力

ライブのBlenderで実行する（ヘッドレス不可）。開いているファイルには作業用シーンを追加するだけで、保存はしない。

```python
exec(open(r'C:/AIQUIZ/AIQUIZ-Godot/tools/saw_operator/build_console_v3.py', encoding='utf-8').read(), {'console_stage': 'setup'})
# 'blockout' → 'detail' → 'export'（GLB出力）→ 'write_source'（原本出力）。作り直しは 'rebuild' → 'detail'
```

既存の原本を編集する場合は `source/saw_operator_v3.blend` の `GodotConsole_V3` シーンを開き、`export` と `write_source` だけを実行する。動きを変えたら以下で姿勢を書き出し、`tools/saw_operator/bake_source_v3.py` をBlenderで実行（`bake_from`／`bake_to` で分割可）するとBlenderのプレビューに反映される。

```powershell
godot --headless --path . --script res://tests/saw_operator_export_poses.gd
```

`source/` と `references/` は `.gdignore` で実行時インポート対象から除外している。

## 検証

```powershell
godot --headless --path . --script res://tests/saw_operator_acceptance_bootstrap.gd
godot --headless --path . --script res://tests/saw_chase_bootstrap.gd
godot --headless --path . --script res://tests/saw_dock_bootstrap.gd
godot --headless --path . --script res://tests/seat_launch_bootstrap.gd
godot --headless --path . --script res://tests/menu_saw_unit_bootstrap.gd
godot --path . --resolution 1280x900 --script res://tests/saw_operator_runtime_bootstrap.gd
godot --path . --resolution 1600x900 --script res://tests/saw_operator_scene_bootstrap.gd -- mode=menu
godot --path . --resolution 1600x900 --script res://tests/saw_operator_scene_bootstrap.gd -- mode=game
godot --path . --resolution 1600x900 --script res://tests/saw_operator_lifecycle_bootstrap.gd
godot --path . --resolution 1600x900 --script res://tests/menu_saw_runtime_bootstrap.gd
godot --path . --resolution 1600x900 --script res://tests/menu_saw_edges_bootstrap.gd
godot --path . --resolution 960x720 --script res://tests/saw_operator_motion_capture_bootstrap.gd -- --sequence
godot --path . --resolution 960x720 --script res://tests/saw_operator_motion_capture_bootstrap.gd -- --stow
```

結果・接写・通し動画は `artifacts/saw_operator/v3/`（Git除外。別環境へ渡す際は一緒にコピーする）。テストは実ゲーム状態を操作するため、作業中のプレイへ接続して実行しない。

## v2（2026-09-20〜25）

v2の操作盤・動作・参考画像・制作記録は `references/v2/`、`source/saw_operator.blend`、`tools/saw_operator/build_station.py` ほか、検証は `artifacts/saw_operator/v2_report.md` に残している。現在の操縦者は `assets/characters/aiquiz_mascot/`（旧プラシュの出典は `assets/characters/godot_plush/CREDITS.md`）。
