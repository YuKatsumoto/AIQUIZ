# スカイゲートの人の動き（W3：drop_moves）

サドンデス「つきやぶれ！スカイゲート」で 2 人が水上機に乗り込み、機内で座り、後ろのスロープから駆け出して飛び降り、空中を腹ばいで落ち、帰還でスロープから飛び降りて着地するまでの動き。受け渡しの約束は `docs/sudden_death_v2/skygate_build_plan.md` 4.4、動きの中身は `heli_drop.md` 第2章と 3.1。

| ファイル | 中身 |
| --- | --- |
| `drop_moves.glb` | 24 クリップ。骨は Quaternius UAL（`assets/animations/cc0_quaternius/UAL1_Standard.glb`）と同じ 65 本・同じ名前・同じ休みの姿（テストで差 0.04° 以下）。マネキンのメッシュ付き（Godot が Skeleton3D を作るため。読み込み側で隠す） |
| `drop_moves.json` | クリップごとの長さ・ループ・端を離れる時刻・腹ばいに落ち着く時刻・着地の時刻・足が床に着いている区間・根の動き（30fps） |
| `source/drop_moves.blend` | ライブの Blender で作った元（`RIG_Drop` と SD_* のアクション、UAL の元のアクション） |
| `source/build_drop_moves.py` | 作り直しの入口（下の「作り直し方」）。`dm_lib.py`（ポーズの道具）・`dm_clips.py`（全クリップの定義）・`dm_preview.py`（Blender での確認の画） |
| `scripts/world/sudden_death/drop/drop_motion.gd` | クラス `DropMotion`（選び方・当て方・情報） |
| `scripts/world/animation_rig.gd` | スロット `SLOT_DROP`（27）を 1 つ足した。`StagingPuppet.pose(clip, ratio, AnimationRig.SLOT_DROP)` で再生できる |

## クリップ

時刻は秒。「腹ばいまで」は端を離れてから腹ばい（`SD_Box_Loop`）に落ち着くまで。どの降り方も 1.2 秒以内（json の値と、テストで姿を測った値の両方）。

| クリップ | 長さ | ループ | 端を離れる | 腹ばい | 腹ばいまで | 中身 |
| --- | --- | --- | --- | --- | --- | --- |
| `SD_Bench_Sit_Loop` | 2.4 | ○ | | | | ベンチで座る（UAL Sitting_Idle にそわそわ：ひざを揺らす・見回す・機体の揺れ） |
| `SD_Bench_Belt_Click` | 1.3 | | | | | 両手を腰のベルトへ → ひざの上で留める（`click` 0.78 秒）→ 手をももへ。座ったまま始まり、座ったまま終わる |
| `SD_Bench_Unbuckle_Stand` | 1.53 | | | | | バックルを外す（`release` 0.30）→ ベルトを左右へはらう → UAL Sitting_Exit を 1.3 倍で立つ（`stand` 1.27）→ 立ち姿（UAL Idle） |
| `SD_Ramp_Run_Up` | 0.93 | ○ | | | | 乗り込みでスロープを駆け上がる（UAL Jog、前かがみ）。速さ 5.90 m/s |
| `SD_Ramp_Walk` | 0.90 | ○ | | | | 降下でスロープの付け根へ歩く（UAL Walk の 1.5 倍）。速さ 1.36 m/s |
| `SD_Ramp_Run_Out` | 0.83 | ○ | | | | 駆け出す（UAL Sprint の 0.8 倍、前かがみ）。速さ 7.12 m/s。飛ぶクリップはこの走りの途中から始まる |
| `SD_Jump_Basic_A` | 1.27 | | 0.20 | 1.00 | 0.80 | 基本：左足で踏み切り両腕を上へ広げて飛び出す → 腕を広げて腹ばいへ |
| `SD_Jump_Basic_B` | 1.30 | | 0.23 | 1.07 | 0.83 | 基本：右足で踏み切り、走り幅跳びの腕（片腕を前・片腕を後ろ）→ 腹ばいへ。走りの位相 0.5 から |
| `SD_Jump_Superman` | 1.30 | | 0.20 | 1.07 | 0.87 | 両腕を前へ伸ばし頭から一直線にダイブ |
| `SD_Jump_Backflip` | 1.93 | | 0.80 | 1.83 | 1.03 | 端で止まってくるっと振り返り、しゃがんで後ろ宙返り（3/4 回転、ひざを抱える）→ 腹ばいで半回転して前を向く |
| `SD_Jump_SpinDive` | 1.30 | | 0.20 | 1.07 | 0.87 | 腕を胸で組んで、ダイブしながら体の軸まわりに 1 回転 |
| `SD_Jump_Starfish` | 1.33 | | 0.20 | 1.13 | 0.93 | 高く跳んで手足を大きく広げた大の字のまま → 前へ倒れて腹ばい |
| `SD_Jump_Trip` | 1.53 | | 0.23 | 1.37 | 1.13 | 端でつまずき、手足をばたつかせて前へ 1 回転して腹ばい |
| `SD_Jump_Cannonball` | 1.47 | | 0.20 | 1.30 | 1.10 | ひざを抱えた体育座りで飛び込む → ぱっと開いて腹ばい |
| `SD_Jump_Salute` | 2.53 | | 1.43 | 2.37 | 0.93 | 端で止まって振り返り、ビシッと敬礼（人形の右手）→ 棒のままかかとを支点に後ろへ倒れる → 寝返りして腹ばい |
| `SD_Jump_Hesitate` | 1.87 | | 0.77 | 1.73 | 0.97 | 端で止まって下をのぞく → 足踏み → 拳をあごに「えいっ」と足から飛ぶ → ばたついて腹ばい。端を離れるのは基本より約 0.57 秒遅い（2 人目だけ） |
| `SD_Box_Loop` | 2.0 | ○ | | | | 空中の腹ばい（ボックス：ゴールポストの腕・反った背中・ひざを曲げる）。風で手足と体が小さく揺れる |
| `SD_Box_Lean_Left` / `_Right` | 2.0 | ○ | | | | 動く向きへ体を 16° 傾ける（その側が下がる）。腕も左右で変える |
| `SD_Box_Lean_Forward` | 2.0 | ○ | | | | 前へ：頭を 12° 下げ、腕を後ろへ流し、脚を伸ばす |
| `SD_Box_Lean_Back` | 2.0 | ○ | | | | 後ろへ：頭を 10° 上げ、腕を前へ伸ばし、ひざを深く曲げる |
| `SD_Land_Hero` | 3.2 | | 0.43 | | 着地 1.50 | 帰還：端から軽く跳び、手を広げて 4 m 落ち、片ひざと拳を床に着くヒーロー着地 → 顔を上げて立つ |
| `SD_Land_Roll` | 3.0 | | 0.43 | | 着地 1.50 | 同じく着地してすぐ前転（UAL Roll。約 1.7 m 前へ転がる）→ 立つ |
| `SD_Land_Stick` | 2.9 | | 0.43 | | 着地 1.50 | 同じく両足でピタッと着地 → 両腕を V に上げる → 立つ |

- 腹ばいの 4 つの傾きと `SD_Box_Loop` は同じ長さ・同じ揺れの位相。飛ぶクリップの `settle` から後ろは `SD_Box_Loop` の `(time - settle)` とまったく同じ姿なので、`settle` 以降どこで `SD_Box_Loop` に切り替えてもつながる。
- `drop` は帰還の着地の落ちる高さ（4.0 m、heli_drop.md 2.3 の「床から約4m」）。

## 座標と根の動き（json）

- クリップの座標：Godot の向きで **+Z が前、+Y が上、+X が体の左**。原点は**クリップの初めの、腰の真下の床**。
- 骨（`pelvis`）が持つのは体の姿だけ（体の向き・宙返り・腰の高さ）。進む・跳ぶ・落ちるは json の `root`（30fps ごとの `[x, y, z]`）。`PlayerController` の骨の当て方は腰の前後左右を捨てるため、前後左右の動きはすべて `root` にある。
- 端を離れるまで `root.y = 0`。離れたあとは、腰が放物線（前は空気で弱まる）を描くように `root.y` が下がる（宙返り中の腰の高さの変化も打ち消してある）。着地のクリップは着地から `root.y = -drop`。
- `edge`：飛ぶ・着地のクリップで、クリップの初めから端を離れる瞬間のいちばん外の足先までの前の距離（m）。**スロープの端の `edge` m 手前（腰の真下）からクリップを始めると、足先が端で離れる**（実画面のテストで端から 0.27 m 以内）。
- `run_phase`：飛ぶクリップの始まりの姿が `SD_Ramp_Run_Out` の何秒目と同じか（基本 B だけ 0.42、ほかは 0）。そこで切り替えると走りがつながる。
- `contact`：足が床に着いている区間。`DropMotion.place` はこの間だけ足の裏を床に合わせる。
- 人形は UAL の左右が鏡に映る（`AnimationRig` の `mirror_x`）。UAL の左手で作った敬礼が人形の右手になる。

## DropMotion（`scripts/world/sudden_death/drop/drop_motion.gd`）

約束の 4 つ（4.4）：

| 関数 | 中身 |
| --- | --- |
| `choose_jump(rng, player, last) -> String` | 1 人ぶん。85% は基本の A/B（相手が基本なら別の型）、15% は特別な 8 種類。2 人は別の特別、前の回に出た特別は避ける、`Hesitate` は 2 人目だけ。`last` は呼ぶ側が持ち続ける辞書（`"second"` 2 人目、`"current"` この回、`"previous"` 前の回）。回の初めに `start_drop(last, first)` を呼ぶ（`choose_pair(rng, last, first)` は 2 人ぶんを一度に） |
| `pose_puppet(puppet, clip, time)` | 本物のアバターに当てる（`SLOT_DROP`）。time は秒。ループは回し、ほかは端で止める |
| `pose_doll(parts, clip, time)` | 人形（`EmoteBlockmanPreview.build_player_skeleton`）に当てる。人形の根が回っていても、根から見た姿で当てる |
| `clip_info(clip) -> Dictionary` | json の表（上のキー。無いキーは既定値） |

足したもの（約束は変えていない）：`place(parts, clip, time, frame)`・`place_puppet`・`place_doll`（当てたあと、`frame`＝クリップの原点のワールドの置き場所へ腰を置く。足が床にある間は足の裏を床に合わせ、離れたらその差を保つ）、`root_offset(clip, time)`、`is_grounded`、`settle_delay`、`pose_box(parts, move: Vector2, time)`（W4 用：腹ばいに 4 つの傾きを押している向きで足し合わせる。x＝右、y＝前）、`pose_doll_blend`、`JUMP_STAGGER`（0.4 秒）・`SETTLE_LIMIT`（1.2 秒）。

```gdscript
# 降下（W6）：回の初めに 2 人の降り方を決める（先はランダム）
var first := 1 + rng.randi_range(0, 1)
var jumps := DropMotion.choose_pair(rng, _drop_memory, first)   # {1: "SD_Jump_...", 2: "..."}
# 毎フレーム：当ててから置く（frame はクリップの原点。飛ぶクリップはスロープの端から edge m 手前、+Z をスロープの外へ）
DropMotion.place_puppet(puppet, clip, t, frame)
# 空中（W4）：腹ばいと傾き
DropMotion.pose_box(parts, move, t)
```

- `StagingPuppet.pose` を直接呼ぶときは ratio 1.0 を避ける（`PlayerController` の読み込みが、いちばんトラックの多いクリップを 1 つループ扱いに書きかえるため、端で初めへ戻る）。`DropMotion.pose_puppet` は端の手前で止めている。
- Godot の読み込みで名前の `_Loop` が外れる（`SD_Box_Loop` → `SD_Box`）。`AnimationRig.resolve_ual_clip` と `DropMotion` はどちらの名前でも引ける。
- 乗り込み・降下の時刻表（heli_drop.md 3.1 の 2.8–3.6 秒）に対して `SD_Bench_Unbuckle_Stand` は 1.53 秒ある。W6 が時刻表を組むときに速める（再生の速さを上げる）か、時刻表を広げる。

## 設計から変えたところ（相談が要るほどではないもの）

| 項目 | 設計 | 作ったもの | わけ |
| --- | --- | --- | --- |
| スピンダイブ | 1 回転半 | 体の軸まわりに 1 回転 | 頭から腹ばいへ倒れこみながら 1 回転半ひねると、最後に腹が上を向く（共通の腹ばいに戻れない） |
| 後ろ宙返り | 背中から宙返りして腹ばいへ | 3/4 回転で腹ばいになったあと、腹ばいのまま半回転して前を向く | 振り返って後ろへ宙返りすると頭が機体の側を向いて止まるため |
| ためらい | 0.5 秒ほど長い | 端を離れるのが基本より約 0.57 秒遅い | のぞく・足踏み・「えいっ」を入れて最短にした |

## 作り直し方（ライブの Blender だけ。ヘッドレス禁止）

1. Higgsfield の `get_host_status` で Blender（`blr`）が接続済みか確かめる。`artifacts/sudden_death_v2/BLENDER_IN_USE.txt` が無ければ名前と時刻を書く。
2. `source/drop_moves.blend` を開き、`exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/assets/animations/sudden_death/source/build_drop_moves.py", encoding="utf-8").read())` を流す（全クリップを焼き直し、`drop_moves.glb` と `drop_moves.json` を書き出す。飛ぶクリップの「腹ばいまで」が 1.2 秒を超えると止まる）。空のシーンで流すと UAL を読み込むところから作る。
3. `.blend` を上書き保存し、`BLENDER_IN_USE.txt` を消す。
4. Godot で `drop_moves.glb` を読み込み直す（`.import` は `animation/remove_immutable_tracks=false`・LOD と影のメッシュなし）。
- Blender での確認の画：`dm_preview.py` の `preview(name, info, times, out_dir, mode)`（Workbench。体を `root` に沿って動かし、スロープの箱を置く）。

## 確かめ方

```
Godot --headless --path . --script res://tests/sudden_death_v2/drop/drop_motion_unit_bootstrap.gd
Godot --path . --resolution 1280x720 --fixed-fps 30 --script res://tests/sudden_death_v2/drop/drop_ramp_capture_bootstrap.gd -- case=pair jumps=SD_Jump_Basic_A,SD_Jump_Superman tag=basic_superman
```

- ユニットテスト（523 項目）：スロットの約束、24 クリップが json と glb にある、骨が UAL と同じ、選び方（2 万回：特別は各 15.2%・15.3%、2 人が同じ特別にならない、前の回の特別を繰り返さない、ためらいは 2 人目だけ、基本どうしは A と B）、**どの降り方も端を離れて 1.2 秒以内に腹ばい（姿を測って 0.77〜1.10 秒）**・腹が下で頭が前、ループが閉じる、根の動きがなめらか、人形の根が回っても同じ姿、`place` で足の裏が床。出力 `artifacts/sudden_death_v2/drop_motion/unit_report.json`。
- 実画面（Forward+）：`case=pair`（本物のアバター 2 人が歩く → 駆け出す → 0.4 秒ずらして端で飛ぶ → 腹ばい。足先が端で離れる・腹ばいの向きを測る）、`case=all`（人形で 10 種類）、`case=land`（着地 3 通り。着地後に足の裏が 4 m 下の床）、`case=cabin`（ベンチで向かい合って座る・ベルト・外して立つ）。一覧は `artifacts/sudden_death_v2/drop_motion/sheet_*.jpg`。
