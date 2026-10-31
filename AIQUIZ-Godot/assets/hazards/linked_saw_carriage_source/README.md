# 連結チップソー台車の編集原本（壁速度タブの収納 v3）

`linked_saw_carriage.blend` は、次の2つの編集原本。

- `assets/hazards/linked_saw_carriage.glb`
- `assets/hazards/linked_saw_carriage_stow.json`

2026-10-28 に、収納機構を v2（四隅の昇降塔＝ダビット）から、左右の門型クレーン方式（v3）へ作り直した。

v2 との違い：

- 撤去したもの：v2 の塔・吊り桁・フライ・C形クランプ・剛体代理・ドライバー・コントロール類。
- 残したもの：刃側の機構（ラム・クレビス・トラニオン、`Slide`/`Ram`/`RamA-C`/`Hinge`/`Tilt` ボーン）。

作り直し前の原本：

- `artifacts/saw_stow/v3/blender/checkpoints/`（Git 除外）
- v2 の生成スクリプト：`tools/saw_stow/build_stow.py`（履歴として保持）

既存の `Spin_Loop`／`Advance_Demo` と、`Carriage`・`Spin_NN`・`Roll_NN`・`Slide_NN` の基準姿勢は変えていない。

## シーンとコレクション

- シーン `CUTLINE | 8-blade carriage`（24fps）。
- `SAW_Import`：台車と収納機構。v3 の部品には `stow_v3` タグが付き、ボーンに親子付けされている。
  - `stow_v3_part` は新規部品の印。
  - v2 から残した刃側部品は `stow_v3` タグのみ。
- 出力しない参照：
  - `REF_GodotContext`：ベルト・壁・キャラ。
  - `REF_Conveyor`：レール・側枠。
  - `REF_Station_Menu_parts`：メニュー姿勢の操縦席。
  - `REF_Vessel_parts`：作業船。
  - `REF_StowContext`：確認用カメラ（`CAM_WallSpeedTab`、`CAM_MenuMain`、`CAM_S3_Review` ほか）。

## 機構とリグ

座標は台車ローカル（x＝横断、y＝進行方向、z＝上、ベルト面＝0）。新しいボーンは +Y 向き・ロール0で、基準姿勢ではローカル軸がワールド軸と一致する。例外は `Rope_*` で、ローカル Y がロープの向きに沿い、長さを Y スケールで表す。

### 門型クレーン（左右各1基）

ボーン構成：

- `Gantry_L/R`：ヒンジ。台車の両端、x=±12.13、z=0.46 で、y 軸まわりに回る。
- `GantryS2_*`／`GantryS3_*`：伸縮2段。脚の軸に沿って平行移動するだけ。
- `Hook_*`：フックブロック（シーブ付き）。
- `Spreader_*`：旋回するスプレッダー。
- `GJaw_*_1..4`：可動爪。
- `Rope_*`：2本掛けのワイヤ。

寸法：

- 脚は y=±1.76。
- 頭梁は y 方向に通す。
- ヒンジから頭梁中心まで、収縮時 4.0m・最大 6.8m。

基準姿勢（GLB のバインド姿勢）は、格納状態。

- 門型をコンベア外側面に吊り下げる（鉛直から外側へ 3°）。
- フックとスプレッダーは門型の内側にドックし、スプレッダーは y 方向を向く。
- ベルト面より上に出るのは、ヒンジのドラムと取付板（z 0.58 まで）だけ。

### 刃側（v2 から流用）

- `Hinge_NN`：ラムの昇降。
- `Tilt_NN`：90° の起こし。
- `Slide_NN`：両端への寄せ。ピッチ 0.85m、束の中心 x=±9.3325。
- `RamA/B/C_NN`：伸縮。`Hinge` の高さからドライバーで決まる。焼き込みにも同じ値を書く。
- `Spin_NN`：拘束を持たない。トラニオンに乗る姿勢と、スプレッダーに掴まれた姿勢を、焼き込み時に計算する。

## 動き（`tools/saw_stow3/build_stow3.py`）

動きはスクリプト内の時刻の関数として解析的に計算し、全ボーンへ 24fps で直接焼き込む。

- 動きの元データは、スクリプト先頭の定数 `T`（タイムライン）・寸法・`SWAY`。
- ドライバー、Follow Path、剛体は使っていない。

### 収納（6.55秒）

次の動きが、前の動きの減速中に始まるよう重ねてある。速度がゼロに戻るのは、爪で掴む一瞬と最後の固定だけ。2026-10-28 のユーザー指摘「一連のアニメーションが分離している」への対応。

| 時刻（秒） | 動き |
|---|---|
| 0.00 | ホーン |
| 0〜0.85 | 刃にブレーキ |
| 0〜2.1 | 門型が側面から外側を回って起き上がる |
| 1.75〜2.85 | 起き上がりにつなげて、内側へ乗り出す |
| 1.45〜2.3 | 門型が伸びる |
| 1.73 | フックが外れて垂れ、ロープを0.25m繰り出す |
| 1.85〜2.45 | スプレッダーが90°回る |
| 0.45〜2.75 | 刃が上がる → 起きる → 端へ寄って束になる（3つの動きを重ねる） |
| 2.75〜3.10 | 乗り出しの終わりに重ねて、スプレッダーを0.6m真下へ下ろす（爪が刃を挟むため最後は鉛直） |
| 3.10〜3.25 | 爪で掴む |
| 3.30〜4.10／3.55〜5.25 | 持ち上げと振り出しを重ね、束は斜め上へ出て弧を描く。操縦席の上は刃の下端2.5m以上で通る |
| 4.85〜6.30 | 振り出しの終わりに重ねて巻き下げる（刃中心 −1.90、上端はベルト面の0.45m下） |
| 6.40 | 固定 |

運び出し中のシーブの位置：

- x は振り出しの進み具合で決まる。
- 高さは、持ち上げの進み具合の割合だけ、その x で門型が届く最高点（`z_reach`）へ近づける。
- 門型の傾きと長さは、このシーブ位置から逆算する。

空のクレビスは、束が離れた後に起こしを戻し、ラムを縮める。

### 展開と揺れ

展開は、収納の運動学を時間反転したもの。吊り荷の揺れ（振り子、最大約3°）だけは、各クリップの順方向で計算し直している。

揺れを0に保つ区間：

- 刃を掴む・置く瞬間（爪が刃の周りにある間）
- ドック
- 固定

### クリップ

| 名前 | 内容 |
|---|---|
| `Stow` / `Deploy` | 全ボーン（`Carriage`・`Roll_` 以外）を24fpsで焼き込んだクリップ。イベントのマーカーを持つ |
| `Gantry_Upright` | 作業船で搬入中の姿勢。門型が直立し、内側へ2°傾いた状態 |

マーカー：

- `Stow`：`horn`・`release`・`clamp`・`lock`
- `Deploy`：`horn`・`unlock`・`unclamp`・`dock`・`lock`

保存状態では `Stow` を割り当て、NLA トラックはすべてミュートしている。

## 再生成

`tools/saw_stow3/build_stow3.py` の段階を順に実行する。各段階は冪等。ライブの Blender で実行する（ヘッドレスは使わない）。

| 段階 | 内容 |
|---|---|
| `cleanup` | v2 の塔・桁・爪・コントロール・物理・アクションを撤去し、刃側の部品を `stow_v3` へ付け替える |
| `bones` | 門型のボーン（左右10本ずつ） |
| `parts` | 部品。断面ロフト、Bevel、Weighted Normal |
| `bake` | `Stow`／`Deploy`／`Gantry_Upright` を焼き込み、NLA へ置く |
| `export` | GLB の書き出し（収納部品は1つのスキンメッシュ `SAW_StowSkinned` に結合） |
| `sidecar` | JSON の書き出し |
| `audit` | 実メッシュ BVH による干渉検査。`AUDIT_KINDS`・`AUDIT_STEP` で分割できる |
| `transport` | 作業船との干渉 |
| `review` | 確認用レンダー |
| `tidy` | ブロックアウト用シーン `STOW3_Blockout` の削除 |

```python
STAGE = 'parts,bake,export,sidecar'
exec(open(r'G:/AIQUIZ-Main/AIQUIZ-Godot/tools/saw_stow3/build_stow3.py', encoding='utf-8').read())
```

干渉検査は重いので、クリップごとに分けて実行する（ブリッジの応答期限を超えるため）。

```python
STAGE = 'audit'; AUDIT_KINDS = ('Stow',); AUDIT_STEP = 2
exec(open(r'G:/AIQUIZ-Main/AIQUIZ-Godot/tools/saw_stow3/build_stow3.py', encoding='utf-8').read())
```

`transport` を実行する前に、Godot で作業船の三角形を書き出す（出力先：`artifacts/saw_stow/v3/dock/`）。

```powershell
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/saw_stow_dock_export.gd
```

結果は `artifacts/saw_stow/v3/blender/` に保存する。

- `audit_stow.json`、`audit_deploy.json`
- `transport_clearance.json`
- 復旧コピー：`checkpoints/`

## 出力と取り込みの注意

- **fps**：シーンは24fpsのまま。変えると `Spin_Loop`（3.333秒）の長さが変わり、ゲーム内の刃の回転速度がずれる。
- **24fps キーの補間**：Godot（`SawChaseController._setup_stow`）が、収納クリップのトラックを 3次補間に切り替える。直線補間のままだと、キーごとに速度が段差になる。
- **書き出し時の状態**：`ExportState` で、ドライバーをミュートし、骨を四元数にし、焼き込んだクリップ以外の骨を基準姿勢に置く。
- **glTF 書き出し**：`use_active_scene=True` が必須。出力時は全 NLA トラックのミュートを一時解除する。
- **Godot の取り込み**：`linked_saw_carriage.glb.import` で `AnimationPlayer` のアニメーション最適化を無効にしている。
- **背景処理の Blender**：`--factory-startup` や `read_factory_settings()` は使わない。この環境では拡張機能の wheel が削除される。

## 寸法の制約

| 対象 | 範囲 | この設計での扱い |
|---|---|---|
| 問題壁 | \|x\|≤11.9 | 格納状態の門型は \|x\| 12.00 以上 |
| コンベア側枠 | x≤12.0、上端 z 0.08 | 吊り下げた脚は外側へ 3° 傾け、側枠との隙間を確保 |
| 作業船の昇降区画の角柱 | \|x\|≥12.275、\|y\| 1.14〜1.66、上端 z 0.605 | 搬入中の直立姿勢で、角柱の y 帯を横切る部品と、z 0.62 以下の部品は \|x\| 12.26 未満（最大 12.252） |
| 操縦席（メニュー） | x 12.01〜13.85、\|y\|<0.85、上端 2.25 | ドック中にこの y 帯を横切る部品は、ヒンジから 2.85m 以上離して外側を回す（収縮長 4.0m の理由）。束は刃の下端 2.5m 以上で通過し、操縦席の外側（x 14.06 以上）へ下ろす |

`.gdignore` により、このフォルダーは Godot の取り込み対象外。
