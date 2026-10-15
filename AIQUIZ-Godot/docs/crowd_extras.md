# 観客の追加演出（2026-10-14）

ゴール観客席と左右のスタンドの観客に、試合の出来事への反応・群衆の演出・個性のある客を追加した。
観客の動き・小道具・ダンスはライブの Blender（Higgsfield 連携）で作り、GLB に書き出している。

| 案 | 内容 |
| --- | --- |
| A2 不正解・海に落ちた | 失敗したプレイヤーのファンは頭を抱える（`SPEC_Despair` / `SPEC_ShakeHead`）。2人用では相手のファンが指さして笑う（`SPEC_PointLaugh`）。中立の客は首を振るか息をのむ |
| A3 HP が減った | そのプレイヤーのファンが「あ〜」と首を振る（`SPEC_ShakeHead`） |
| A5 カウントダウン | 全員が前のめりで身構え（`SPEC_Anticipate`）、スタートの瞬間に歓声（居眠り客も飛び起きる） |
| A6 ノコギリ・サメ・落下 | その地点の近くの席だけ驚いてのけぞる（`SPEC_Gasp`）。距離に応じて 25 m/s で波紋のように広がる |
| B1 スタジアムウェーブ | 右スタンドのハテナが合図して、ゴールへ向かって 16 m/s で流れ、ゴール観客席を横切って左スタンドを戻る。座席の客は腰を浮かせて立ち上がり、両手を上げる（`SPEC_StandWave`）。プレイ中の小休止だけ、開始 12 秒後から 42〜70 秒おき |
| B5 勝者のダンスにシンクロ | 判定後に勝者がエモートを踊り始める（`ResultWinnerDance.START`）と、盛り上げ役と勝者側のファンの約 4 割が同じダンスを同じ拍で踊る。引き分けはそれぞれのスタンドが自分の側のプレイヤーのダンス |
| C1 居眠り | うたた寝してはっと起きる（`SPEC_Doze` / `SPEC_WakeUp`）。盛り上がると起きて 18 秒は起きている。ウェーブには参加しない |
| C2 食べる客 | ポップコーン（6割）かホットドッグを食べている（`SPEC_Eat`、`GSP_Popcorn` / `GSP_HotDog`）。失敗の瞬間は息をのむ |
| C3 隣同士のペア | 0.92 m 隣の 2 人組。盛り上がるとハイタッチ（`SPEC_HighFiveL/R`）、手拍子や緊張の場面では肩を組んで揺れる（`SPEC_ShoulderL/R`）。2 人は同じ時計で動く |
| C4 自撮り・双眼鏡 | スマホを掲げて自撮り（`SPEC_Selfie`、`GSP_Phone`）、双眼鏡でコースを追う（`SPEC_Binoculars`、`GSP_Binoculars`） |
| C5 応援団長 | 鉢巻きでメガホン（`SPEC_Megaphone`）か太鼓（`SPEC_Drum`）。0.5 秒の拍で、その側のファンが頭上で手拍子する（`SPEC_ChantClap`）。プレイ中は 26〜44 秒おきに 7 秒、両チーム交互。ゴールへの競争中は両チームずっと |
| C6 ビールの売り子 | ゴール観客席の左右の通路（x = ±6）を上り下りし、ときどき立ち止まって呼び込む（`SPEC_VendorWalk` / `SPEC_VendorCall`、樽 `GSP_Keg` とカップ `GSP_Cup`） |
| C7 マスコット | ハテナがゴール観客席の前（中央から 3.4 m、審判と重ならない位置）と左右のスタンドの通路（コース 20 m）に立つ。ゴール・スタートで跳び、手拍子に合わせて手をたたき、ウェーブの合図、勝者のダンス中は踊る |
| C8 肩車・タオル回し | 最上段に子どもを肩車した親（`SPEC_CarryKid`、子どもは `SPEC_KidSit` / `SPEC_KidRide`）。タオルのファンは盛り上がるとタオルを回し（`SPEC_TowelSpin`、`GSP_Towel`）、ふだんは首にかけている（`GSP_TowelNeck`） |

## 合図（`CrowdCues`）

`scripts/world/crowd/crowd_cues.gd`。`game_world.gd` が 1 つ持ち、毎フレーム `_update_crowd()` で進めてから、
ゴール観客席（`GoalStand.update_stand(..., cues)`）、左右のスタンド（`GrandstandCrowd.follow_cues()`）、
スタンドのハテナ（`GrandstandCrowd.update_mascots()`）に渡す。

- 出来事：`health_changed`（HP が減った→HURT）、`question_winner_decided`（判定された中で正解でない人→MISS）、
  `player_entered_ocean`（MISS と、落ちた地点の驚き）、`player_caught_by_saw`（MISS と驚き）、サメに食べられた瞬間（`p1/p2_shark_killed` の変化→驚き）、
  ゲームの状態（COUNTDOWN→カウントダウン、PLAYING に入った瞬間→スタート）。ゴール到達と判定は今まで通りゴール観客席が読み（`side_crowd_reaction()`）、GOAL / VERDICT になる。
- 層（それぞれ自分の時計を持つ）：合図（1 つだけ、0.35 秒でフェード。優先度は 判定 > ゴール > 失敗 > HP > スタート > カウントダウン）、
  驚き（コース上の位置）、ウェーブ、応援の拍、勝者のダンス。
- 観客が演じる優先順：ウェーブ > 近くの驚き > 勝者のダンス > 合図 > 応援の拍 > 各自のたまの動き > 休み。

## 左右のスタンド（座席の観客）

- `SeatedSpectatorKit`：焼き込む動きを 32 本の固定順（`CLIPS`、シェーダーの `C_*` と一致）にした。
  小道具 8 種は UV2.y のビット（6 + 小道具番号）でメッシュに入れ、小道具を持つ客だけが小道具入りのメッシュ（`prop_mesh()`）を使う
  （持たない客の頂点数は前と同じ。1 ブロック 2 ドロー）。
- ウェーブの立ち上がり：`goal_stand_clips.json` の `SPEC_StandWave.rise`（立つ・座る時刻）に合わせて、焼き込み時に腰を座面から浮かせ、
  座ったときの足首まで 2 本の骨の IK で脚を伸ばす。
- 勝者のダンス：試合の開始時に両プレイヤーのエモートのダンスを `prepare_sync()` し、`step_sync()` が 1 フレーム 1.5 ms まで少しずつ焼く（判定の時点で焼き終わっている）。
  ダンスは元の FBX の長さ（`source_seconds`）でループさせ、30fps の観客の動きに合わせて縮める（`CrowdCues.dance_time()`）。
- 客ごとのデータ：`look` に小道具（× 5040）、`habit` に役（× 8、0〜10）とチーム（× 128）。ペアは位相と速さを共有する。
- 役の割合：中立の客の 6% が居眠り、12% が食べる客、6% が自撮り、5% が双眼鏡。ファンの 10% がタオル、隣同士の 7% がペア。1 ブロックに応援団長 1 人（2 列目の中央付近）。
- ハテナ：`aisle_offsets_z()` のうちコース 20 m に最も近い通路、最前列の手前（x 1.0、床 0.32）。軽い版のモデル（`mascot_model_lod.glb`）。

## ゴール観客席

- 役の追加（各側）：応援団長 1（P1 はメガホン、P2 は太鼓）、ペア 1 組（2 段目）、肩車 1（最上段）、タオル 2、居眠り 2、食べる客 3、自撮り 1、双眼鏡 1。
  応援団長・ペア・肩車はどの画質でも必ず出る。売り子 2 人は通路を歩く。
- 時計に合わせる動き（ウェーブ・応援の拍・勝者のダンス・ペア）は `_play_synced()` で共通の時刻へシークし、0.12 秒以上ずれたら合わせ直す。
  ウェーブは客の x 座標から到着時刻を計算する（`CrowdCues.wave_arrival_goal_stand()`）。
- 肩車の子どもは親の首の骨（`neck_01`）の `BoneAttachment3D` の下に置き、首にスキンされた頂点と同じように動く（座る位置と縮尺は `goal_stand_clips.json` の `kid`）。

## ダンスの速さの修正

ゲームのダンス FBX は 60fps（例：YMCA は 4.5 秒）だが、前の観客のダンスは 30fps として書き出していて、**半分の速さ**で踊っていた。
`retarget_dances.py` で元の 2 フレームを 1 フレームにして実際の速さ・全長（上限 16 秒をやめた）にし、エモート 14 種すべて（スリラーは 4 部を連結、111.3 秒）を観客用に作った。
フレアとヘッドスピンは床の技なので観客用はなく、`SPEC_DanceBounce` で代わりに弾む。

## 制作（Blender）

`assets/goal_stand/source/`（ライブの Blender で実行。作業ファイル `goal_stand_crowd.blend`）：

- `author_crowd_extras.py`：新しい動き 20 本（`pose_lib.py` の IK）。売り子の歩きは UAL の `Walk_Loop` の脚に腕を付け替え。
- `build_crowd_props.py`：小道具 10 種。各小道具は使う動きの代表フレームで手に持った位置に作り、骨の休止姿勢へ戻してスキンする。
- `retarget_dances.py`：実際の速さ・全長、複数 FBX の連結、`source_seconds` の記録。
- `preview_crowd_extras.py`：動きを並べた確認用レンダー（`artifacts/crowd_extras/`）。
- `export_goal_stand.py`：`EXPORT_ONLY = ["spectator"]` で観客の GLB と `goal_stand_clips.json` だけを書き出せる。

`assets/characters/aiquiz_mascot/source/build_stand_mascot.py`（`aiquiz_mascot.blend` で実行）：ハテナの客席用の動き 5 本 → `mascot_stand.glb`。

## 検証

```powershell
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/goal_stand_bootstrap.gd
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/side_stand_blocks_bootstrap.gd
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --fixed-fps 60 --script tests/crowd_extras_bootstrap.gd
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --fixed-fps 60 --script tests/crowd_cues_gameplay_bootstrap.gd
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --fixed-fps 60 --script tests/result_ceremony_bootstrap.gd -- runtime case=p1 fps=60 out=crowd_extras
```

- `crowd_extras`：スタンドと観客を実際に組み、合図を順に送って、配役・肩車の高さ・カウントダウン・スタート・失敗・驚き・ウェーブ（右→ゴール→左）・応援・
  勝者のダンス（全員が同じ拍で踊ること）・売り子の歩行を確かめ、`artifacts/crowd_extras/runtime/` に撮る。
- `crowd_cues_gameplay`：本物の `game_world.tscn` で、ゲームのシグナルから合図が届くことを確かめる（`artifacts/crowd_extras/gameplay/`）。
- 計測：決着演出の通しで、ゴール観客席の更新は 1 フレーム平均 0.81 ms（追加前の計測は 0.64〜0.69 ms）。

## 既知の制限

- ゴール観客席のハテナは前の欄干（高さ 0.91 m）の後ろに立つので、脚は隠れる。
- プレイ中のカメラは壁の方を向くため、左右のスタンドは画面の端に映る。ウェーブや手拍子がよく見えるのは、壁が割れた後やゴールへの競争、ヘリの登場の場面。
- 観客は自分のスタンドの席しか知らないので、ペア以外の「隣と息を合わせる」動きはない。
