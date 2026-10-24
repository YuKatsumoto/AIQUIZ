# GOSTRIDER（ゴーストシャーク）の搭乗演出

2 人用で片方が脱落すると、その魂が幽霊になってサメに乗り、生き残った側へ突進する（`GhostSharkRideController`）。
このページは「脱落 → 魂が抜ける → 飛ぶ → サメに乗る → 柱が立つ → 発進」までの見せ方と、その作り方をまとめる。

## 流れと拍（`_sequence_elapsed` の秒。フェーズの長さは今までと同じ）

| 秒 | フェーズ | 乗り手の演技 | 見せ方（小窓） | 音 |
|---|---|---|---|---|
| 0.00 | DEATH_HOLD | 爆散した体の場所に、丸まった小さな魂 | 水面すれすれ（甲板の上で脱落したときは外側の斜め後ろ）から見上げる | |
| 0.55 | SOUL_RISE | ほどけながら脱力して昇る（0.34 → 1.0 倍へ育つ） | 光の殻と昇る粒（emerge） | `ghost_soul_rise` |
| 1.17 | | 体を縮めてためる | | `ghost_awaken`（1.11 秒。吸い込みの 0.16 秒後に和音） |
| 1.27 | | 目覚め：両腕を V 字に広げ、顔を上げる | 光の殻・輪 2 本・粒・灯り、小窓の閃光と揺れ | |
| 1.40 | SOUL_FLIGHT | サメを指して向き直り、蹴り出して水平に飛ぶ（腕を前に突き出すヒーロー飛行） | 肩越しに前で待つサメ → ステージ側から並んで追う。尾の光 | |
| 3.48 | | 起き上がり、脚を開いて鞍へ落ちる | | |
| 4.05 | MOUNTING | 着座：上体が深く折れて沈み、跳ね返って座り直す（手はハンドル、足は足掛け） | サメの斜め前の寄りにカット。衝撃の輪・火花・閃光・揺れ。サメに乗り移る光が鞍から頭と尾へ走る | `ghost_mount_land` |
| 4.90 | BEAM_REVEAL | 身を沈めてため、5.13 秒に右の拳を突き上げて吠える。左手はハンドルのまま | 下からあおってゆっくり回り込む（空と観客席）。柱の間はサメの輪郭が脈打ち、光の筋が流れる | `ghost_mount_beam` |
| 6.55 | | 拳を下ろしてハンドルへ | | |
| 7.09 | | サメが縦に立って昇る間、身を伏せてしがみつく | 背中（乗り手）側の下から見上げる | |
| 8.49 | ENTERING | 前のめりから、照準の姿勢へ | 後ろ上から追う（行く先と生き残った側が見える） | |
| 10.94 | AIMING〜 | 待機（呼吸・見回し）、チャージ中と構えは身を沈め、突進は低く前へ | | |

メインの画面では、搭乗の柱が生き残った側の画面の端に立つ（柱の甲板から 4 m の点が画面の横に入るまで、待ち合わせの場所を水路の前へずらす。`_keep_beam_in_main_view`）。
柱は小窓には映さない（小窓のカメラは柱のすぐ外に寄るので、映すと画面が柱の色で埋まり乗り手が隠れる）。

## 乗り手の演技（Blender → JSON）

- 作り方：`assets/animations/source/ghost_rider/build_ghost_rider_performance.py`（作業ファイル `ghost_rider_performance.blend`、`.gdignore` 付き）。
  ゲームのブロック人形（`PlayerController._build_player_skeleton`）と同じ部品の位置・箱の大きさ・親子の複製リグ（`RIG_GhostRider`）を作り、
  骨の軸をゲームの部品の軸（X、Y 上、Z 正面）にそろえてある。骨の回転（クォータニオン）がそのまま部品のローカル回転。
- リグはサメの `GhostMountSocket` に、ローカル単位行列・大きさ `RIDER_SCALE`（0.70、サメのモデルの 1 単位あたり）で子付けする。
  ゲームも乗り手をソケットの向き・位置そのまま、大きさ `0.70 × サメのモデルの倍率` で乗せる（向きの 180° 補正・持ち上げはやめた）。
- 乗っている区間は、毎フレーム 2 関節の IK で手のひらをグリップの中心、足の裏を足掛けの上に焼いてある（`limb_targets`・`solve_limb`）。
  胴を動かしても手足は離れない。腰は鞍の上（腰のピボットを +0.28 上げた位置でお尻が座面）。
- クリップ：`performance`（10.94 秒、329 フレーム）・`idle`（2.2 秒のループ）・`windup`（0.34 秒）・`dash`（1 フレーム）。
  書き出し先 `assets/animations/ghost_rider_performance.json`（骨ごとのクォータニオン・腰の位置・左右の握り 0〜1）。
- 作り直し（ライブの Blender で。ヘッドレス起動はしない）:
  ```
  ns = {}
  exec(open(r".../build_ghost_rider_performance.py", encoding="utf-8").read(), ns)
  ns["build_authoring_scene"]()   # 初回だけ：複製リグ + サメ
  ns["key_all"]()
  ns["export_json"]()
  ```
  `contact_report(rig)` で手のひら・足の裏と部品の距離、`render_review(path, target, eye)` で確認の絵が出る。

## サメ（鞍・ソケット・クリップ）

- 作り方：`assets/animations/source/build_ghost_shark_mount.py` の `_build_shark_actions(open_file=False)`（開くのは別の呼び出しで）。
  `shark_swim_with_jaw.blend` を作り直して保存し、`assets/shark/shark_swim.glb` を書き出す（リグと子だけ、表示中のシーンだけ）。
- 鞍：長いシート、水平で左右対称の T 字ハンドル（グリップの中心 `(1.74, ±0.36, 0.88)`）、左右の足掛け（`(1.46, ±0.585, 0.21)`）。
  ハンドル・足掛けなど硬い部品とソケットは、どれも `body_02`（座る場所の骨）だけに付く（体が曲がっても手足の接地がずれない）。
- クリップ：`GhostMountReceive`（着座で背がたわみ、尾がはね、揺れて収まる。等速で再生）と `GhostBeamPower`（新規 3.59 秒：身震い・柱の間の震え・上昇の尾の漕ぎ）。
  幽霊のクリップは顎をキーせず、頭・胸びれを中立にする（`rebuild_shark_animation.py` と同じ約束）。
- `SharkSwim`・`SharkBite` は `assets/shark/source/rebuild_shark_animation.py` の持ち物で、ここでは作り直さない。
  2026-10-21 に GLB を `git HEAD` と比べ、`SharkSwim`・`SharkBite`・`GhostRendezvousIdle`・`GhostDeparture` が角度差 0.00° で同じことを確かめた。

## ゲーム側の部品

- `scripts/world/ghost_rider_performance.gd`（`GhostRiderPerformance`）：JSON を読み、フェーズの時刻でクリップを補間して部品に当てる。指の握りもここ。
- `scripts/world/ghost_rider_presentation.gd`（`GhostRiderPresentation`）：演技の当て込み・魂の向き（進む向きへ振り向き、曲がりで傾き、着く直前にソケットの向きへそろう）と大きさ・光（輪・殻・火花・灯り）・拍（emerge / awaken / erupt）。
  魂が小窓だけに映っている間（レイヤー 20）は、光も同じレイヤーに置く。
- `scripts/world/ghost_soul_trail.gd`：魂の尾（交差した 2 枚のリボン、加算）。
- シェーダー（`assets/ghost_rider/`）：`ghost_soul`（半透明・縁光り・ゆらぎ）、`ghost_rider_solid`（乗っている間。不透明・縁光り）、`ghost_fx_additive`（光の部品）、`ghost_possession`（サメへの乗り移り。鞍から光の帯が走り、輪郭と光の筋が残る）。
  ポータルを通る間は、サメの Stencil の差し替えに合わせて乗り手を標準の材質にする（`set_ghost_rider_portal_safe`）。
- 幽霊の姿はどの場面でも同じ：`PlayerController.apply_ghost_soul_look(root, player_index)`（魂のシェーダー・プレイヤー色の縁光り・昇る光の粒）。
  GOSTRIDER の魂、リザルトで降りてくる幽霊、表彰台の代役（リザルトで脱落した人・サドンデスで負けた人。`apply_ghost_look`）、
  サドンデスの空のゲートの幽霊（`sky_gate_presenter._make_ghost_look`）がこれを使う。見た目を変えるときはここと `ghost_soul.gdshader` だけを直す。
- 小窓（`scripts/ui/death_wipe.gd`）：幽霊の演出は爆散の保持で閉じない。演技の時刻でショットを選ぶカメラ（出現・飛行・着座・力み・上昇・発進）、
  閃光（`play_ghost_flash`）・揺れ（`add_ghost_shake`）・寄り、枠はプレイヤー色、ラベル「P1  GHOST RIDER」。
- モーションを部品に当てる `_apply_skeleton_pose` は、乗り手（向きと大きさのある親）を渡すとその空間で当てる（エモートの上半身も乗り手の向きに付いてくる）。

## 確かめ方

- 連番：`tests/ghost_mount_capture_bootstrap.gd`
  ```
  Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/ghost_mount_capture_bootstrap.gd -- tag=check death=ocean
  ```
  `death=wall|ocean`、`until=aim|dash|miss`、`every=N`、`rider=1|2`。出力 `artifacts/ghost_mount_capture/<tag>/`（`main_*.jpg` は画面、`wipe_*.jpg` は小窓のカメラを 960×720 で撮ったもの、`report.json` にフェーズ・音・柱の画面の位置）。
- 座標の実測：`tests/ghost_mount_probe_bootstrap.gd`（鞍の部品・関節の乗り手の空間での位置、乗り移りの重ねがけの状態）。
- 2026-10-21 に通したテスト：`ghost_hud`（P1・P2 とも 112）・`ghost_shark_audio`（26）・`result_ceremony` 単体（5000）と実機（780）・`player_skin`・`hp` 単体（197）と実機・
  `tutorial_renewal`（duo、86）・`tutorial_rules`（83）・`shark_asset`・起動の予熱（`startup_loading_acceptance`、30）・
  オンライン `tests/net/run_pair.py --scenario ghost` と `ghost_host`・`shark_contact`（既定・`player=2`・`case=back`・`case=close`）。
  `shark_contact` は、2 人用ののこぎり（後で追加）の刃の中に選手を置いていて最初のフレームで試合が終わっていたので、テストでのこぎりを止めた。
