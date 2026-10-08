# ゴール観客席（Goal Stand）

ゴールを越えたコンベアの先端に建つ3段の立見スタンド。ブロック人形の観客がゴールと勝敗に反応する。
勝った側のファンは歓声・旗・プラカードで喜び、負けた側は頭を抱え、ホットヘッド（鉢巻き・はげ頭の短気な客）は
激怒して負けたプレイヤーに卵を投げつける（引き分けなら審判に）。パーティ客はゲームのエモートをランダムに踊る。

制作は Higgsfield 主体：Blender は Higgsfield コネクタ経由で組み立て・リグ・アニメーション・書き出しまで行い、
看板・プラカードの画像と観客の掛け声は Higgsfield の生成モデルで作った。

## 配置と挙動

- スタンド正面はゴールラインから `GoalStand.GOAL_OFFSET`（25.8 m）先。演出中のコンベア終端（+24 m）と
  サイドフレームのはみ出し（1.2 m）のすぐ外側で、海中の柱とアーチで立っている。幅26 m、段差0.55 m、奥行1.35 m×3段。
- P1 側（ワールド +X、画面左）はオレンジ系、P2 側は青系のファン。10% は中立の客。
- 役割：ホットヘッド（片側3人、卵パック持ち）、プラカード（片側3人が同じ段で横並び。がんばれ／ファイト、
  負けると画面左から「OH」「MY」「GOT」に裏返す。全画質で必ず3人とも出る）、
  チーム旗、フォームフィンガー、パーティ客（ダンス）、一般ファン。
- 反応：
  | 状況 | 反応 |
  | --- | --- |
  | 通常プレイ中 | 待機（おしゃべり・電話・うなずき・腕組み）。170 m 以上離れると静止して処理を止める |
  | ゴールレース | 手振り・拍手・叫び・祈り。パーティ客は軽くノる。女性の「がんばれー！あとちょっと！」 |
  | 誰かがゴール | そのプレイヤーのファンが歓声ジャンプ、他は拍手（2.8秒）＋歓声 |
  | 演出 0–4.1秒 | 拍手と旗・プラカード。4.1秒〜判定までは息をのむ（祈り・腕組み） |
  | 判定（6.9秒〜） | 勝者側：歓声・指さして笑う・旗振り。敗者側：頭を抱える・首振り・横並びのプラカードが「OH MY GOT」。歓声とブーイング |
  | 卵 | 敗者側ホットヘッドが激怒（顔が赤くなる）→判定が出ている間ずっと投げ続ける（数に上限なし）。25%は床に外れる。当たると殻だけが割れて散る（下の「卵の割れ方」） |
  | 引き分け | 全員拍手・歓声、「えーっ！引き分けー？」、ホットヘッドは審判に卵 |

## 素材

| ファイル | 内容 |
| --- | --- |
| `goal_stand.glb` | スタンド本体 `GS_Stand`（段・青いベンチ・胸壁・ペナント・チーム旗・海中の柱とアーチ）と電光掲示板 `GS_Scoreboard`。ヘッダー看板・電球盤・鋼板の画像を埋め込み |
| `goal_stand_spectator.glb` | 観客リグ（23ボーン）＋髪型7種のボディ＋手持ち小道具＋アニメーション25本 |
| `goal_stand_props.glb` | 飛んでいく卵と殻の破片 |
| `goal_stand_layout.json` | 段の高さ・立ち位置・通路（Blender空間。Godotでは (x, z, -y)） |
| `goal_stand_clips.json` | クリップ長・ループ・卵を放す時刻（0.3秒） |
| `goal_stand_egg_contents.glb` | （未使用）卵の中身：白身 `GSE_White`（半径1の放射状ディスク）と黄身 `GSE_Yolk`（底が平らな球）。`source/build_egg_contents.py` で作成 |
| `source/textures/sb_*.png` | 電光掲示板のヘッダー看板・鋼板（Higgsfield）と電球盤（手続き生成）。`prep_scoreboard_textures.py` で作成 |
| `../audio/sfx/goal_stand/*.ogg` | 歓声・ブーイング・拍手・掛け声3種・卵の投擲/破裂音 |

アニメーション（30fps）：

- 独自（`author_actions.py`、IKで作成）：`SPEC_Cheer` `SPEC_Clap` `SPEC_Rage` `SPEC_Despair` `SPEC_Wave`
  `SPEC_Anticipate` `SPEC_PointLaugh` `SPEC_SignUp`
- Quaternius UAL（CC0、`assets/animations/cc0_quaternius`）から：`SPEC_Idle` `SPEC_Talk` `SPEC_Phone` `SPEC_FoldArms`
  `SPEC_ShakeHead` `SPEC_Nod` `SPEC_HoldUp` `SPEC_Throw` `SPEC_DanceBounce` `SPEC_Shout`
- ゲームのエモート（Mixamo FBX）をリターゲット：`SPEC_Dance_YMCA` `Gangnam` `Silly` `HokeyPokey` `RunningMan`
  `WaveHipHop` `Swing`。両リグは同じTポーズ・-Y向きなので、ボーンごとにワールド空間の回転差分を移し、
  腰の移動は脚の長さ比で縮めてから1.5秒の移動平均を引いて段から出ないようにしている。

観客は1マテリアル（`shaders/goal_stand_spectator.gdshader`）。Blenderで各面の色の役割を UV.x
（(役割+0.5)/16）に焼き、Godotでは肌・服・ズボン・髪・靴・チーム色・怒り度をインスタンスごとに渡す。
プラカードの板だけは画像テクスチャのマテリアル。裏返し用の板（`GSP_SignBoo`）は GLB の「ブーー！」マテリアルを
複製し、Godot 側で `goal_stand_spectator_sign_{oh,my,got}.png` に差し替える（`GoalStand.WORD_SIGNS`）。

## 電光掲示板（Scoreboard）

スタンドの背面壁の後ろに2本の鉄骨脚で立つ野球場型の電光掲示板（幅12.6 m、筐体の高さ約7.6 m）。

- LED 画面 11.2×4.8 m（7:3、マテリアル `GS_ScoreboardScreen`）。Godot が `GoalStandScoreboard` の
  SubViewport（1400×600）を `shaders/goal_stand_scoreboard_led.gdshader` で表示する：LED 448×192 個を丸い発光点として描き、
  32×32 個ごとのモジュール継ぎ目、黒い光沢面、斜めから見たときの減光。LED が画面上で3〜6 px 以上のときだけ
  粒を描く。
- 遠距離のちらつき対策：SubViewport のテクスチャにはミップマップがないため、`GoalStandScoreboard` が半分ずつ縮めた
  SubViewport を7段（700×300〜11×5）つなぎ、盤面が変わったときだけ更新する。シェーダーは画素の範囲に合わせて
  2段を選んで補間する（トライリニア）。`tests/scoreboard_flicker_runtime.gd` で 60/120/220/400 m から横に少しずつ
  動かしたときのフレーム間の輝度変化を測り、ミップマップ付きの理想値の1.3倍以内であることを確かめる
  （実測：単純な1回サンプリングより 24〜81% 少なく、理想値との差は3〜19%）。
- 上部：「AIQUIZ STADIUM」の看板（ゲームロゴを参照に生成）、左右の電球盤（7×3灯を描いた1枚のテクスチャ。
  小さな立体を並べると遠くで瞬くため）、庇、投光器4基。
- 左右の柱に P1（オレンジ）・P2（青）の発光ライン。背面にルーバー、点検通路と手すり、梯子、X ブレースの脚。
- 表示内容：問題ごとの勝者（勝者の行に○、誰も正解しなければ「−」、R 列に勝利数、出題中の列が点滅）。
  リザルトで判定（WIN）が出た瞬間から勝者のカットイン（引き分けは DRAW!）に切り替えて保持する。
- カットインのあと：ローカルの2Pフィナーレで結果画面（`STATE_CLEAR`）が開き、今の試合の記録とハイライトの保存が終わると（`MatchReel.is_ready()`、
  6秒待っても終わらなければそのまま）、LED 番組「AIQUIZ VISION」に切り替わる（RECORDS → 前回の対戦 → 履歴 → 通算 → ロゴ。ハイライトのリプレイは流さない：`GoalStandScoreboard.PLAY_REPLAY`）。
  番組のワイプがカットインの上を左から覆って入れ替わり、結果画面を離れるまで流れる。もとはメインメニューの島の LED 画面で流していた番組
  （`scripts/ui/menu_led/`、[docs/menu_led.md](../../docs/menu_led.md)）。番組の 1296×588 を 1400×600 の盤面に全面で貼り、LED の粒とミップは盤面側のシェーダーが受け持つ。

## 卵の割れ方

`scripts/world/goal_stand/goal_stand_eggs.gd`。着弾時の速度と当たった面の向きから計算する。

- 卵は面に数フレーム潰れてから割れる。殻の破片は面で跳ね返り、空気抵抗を受けて回転しながら床で弾み、平らに寝て止まってから消える。
- 中身（白身・黄身・飛沫）は描かない。卵は判定が出ている間ずっと飛び続けるので、残っている殻の破片は最大96個（超えたら古いものから消す）。
- 以前の中身の表現（`goal_stand_egg_contents.glb`、`shaders/goal_stand_egg_white.gdshader`、`source/build_egg_contents.py`）は未使用。
- 確認：`Godot --headless --path . --script tests/goal_stand_eggs_bootstrap.gd`

## Higgsfield で生成したもの（計 5.25 クレジット）

| 素材 | モデル | 備考 |
| --- | --- | --- |
| 旧看板 `source/textures/banner.png`（電光掲示板に置き換えたため未使用） | seedream_5_0_flash | ゲームロゴ（icon.jpg）を参照画像に使用 |
| プラカード P1「がんばれ！」/ P2「ファイト！」/「ブーー！」（「ブーー！」は GLB 内のみ、表示は下の OH/MY/GOT に置き換え） | seedream_5_0_flash | 単色背景で生成し `key_generated.py` で抜き |
| プラカード「OH」「MY」「GOT」 | 手描き（`source/generated/sign_word_*_raw.png`） | `prep_word_signs.py` で看板比率（0.62:0.46）に整える |
| 卵の飛び散り（3Dの黄身・白身に置き換えて削除） | z_image | マゼンタ背景から抜き |
| 電光掲示板のヘッダー看板「AIQUIZ STADIUM」 | seedream_5_0_flash | ゲームロゴ（icon.jpg）を参照画像に使用。生成された看板枠（2.5:1）をそのまま使う |
| 広告3枚（カモメ急便／ひらめきソーダ／マナブ文具） | seedream_5_0_flash | 広告帯をなくしたため未使用（元画像のみ `source/generated/` に残す） |
| 掲示板の塗装鋼板 | seedream_5_0_flash | 縁取りを落とし、明暗ムラを平坦化してタイル化 |
| 掛け声6本（よっしゃあああ！最高だー！／やったー！おめでとー！／ふざけんなー！金返せー！／ブーーー！／えーっ！引き分けー？／がんばれー！あとちょっと！） | seed_audio（太郎・Hana） | `synth_crowd_audio.py` で群衆の合成音に重ねる |

生成物の元ファイルは `source/generated/`。

## 編集可能な制作データ（`source/`、Godotの読み込み対象外）

Higgsfield Blender コネクタ（Blender 5.1）で実行する。開いているセッションに `AIQUIZ_GoalStand` シーンを追加して作業し、
他のシーンには触れない（同名の他シーンのオブジェクトがあれば停止する）。

- `gs_common.py` — 定数・パレット・箱メッシュ生成・キー書き込み
- `build_rig.py` — UAL マネキンから指を除いた `RIG_Spectator`
- `build_bodies.py` — 髪型7種のブロック人形（各箱を1ボーンに100%スキン）
- `pose_lib.py` / `author_actions.py` — ポーズソルバー（2ボーンIK）と独自リアクション
- `retarget_dances.py` — エモートのリターゲット
- `bake_ual.py` — UAL クリップの焼き込みと卵を放す瞬間の計測
- `build_props.py` — 卵・卵パック・フォームフィンガー・旗・プラカード
- `prep_word_signs.py` — 手描きの「OH」「MY」「GOT」を看板テクスチャに整える
- `build_stand.py` — スタンド本体と `goal_stand_layout.json`
- `build_scoreboard.py` — 電光掲示板 `GS_Scoreboard`（`goal_stand_layout.json` に画面位置 `scoreboard` を追記）
- `prep_scoreboard_textures.py` — 掲示板のテクスチャ（ヘッダー看板の切り出し・鋼板のタイル化・電球盤の描画）を `textures/sb_*.png` に書き出す
- `export_goal_stand.py` — GLB 3種と `goal_stand_clips.json`
- `preview.py` — 確認用レンダー（`artifacts/goal_stand/blender/`）
- `key_generated.py` — 生成画像の背景抜き / `synth_crowd_audio.py` — 群衆音の合成と書き出し（ffmpeg）
- `build_all.py` — 上の工程を順に実行

### 再生成

Blender（Higgsfield コネクタ）で：

```python
ns = {}; exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/build_all.py", encoding="utf-8").read(), ns); ns["build_all"](export=True)
```

プロジェクトルートで：

```powershell
python assets/goal_stand/source/key_generated.py
python assets/goal_stand/source/prep_scoreboard_textures.py
python assets/goal_stand/source/synth_crowd_audio.py
```

## Godot 実装

- `scripts/world/goal_stand/goal_stand.gd` — スタンド・観客の生成（1フレーム6人ずつ）と反応、卵の狙い、効果音。
  画質別の人数：HIGH 78 / BALANCED 71 / LOW 48（ホットヘッドは常に6人）。LOW はアニメを30Hz、
  70 m 以遠は15Hz、170 m 以遠は処理停止。
- `scripts/world/goal_stand/goal_stand_scoreboard.gd` — 電光掲示板の表示（スコア表と勝者カットイン）。
- `scripts/world/goal_stand/goal_stand_eggs.gd` — 卵の弾道（最後は動く標的に追従）と割れた後の物理（下の「卵の割れ方」）。
- `scripts/world/game_world.gd` — ゴールラインと同じ条件で生成・配置し、毎フレーム更新。
- `ResultCeremonyDirector.crowd_egg_target()` / `ResultFinaleStage.egg_target()` — 判定後の卵の標的。
- `AudioManager.play_crowd_cue()` — 群衆の効果音（初回使用時に読み込み）。

## 検証

```powershell
& $GODOT --headless --path . --script tests/goal_stand_bootstrap.gd
& $GODOT --path . --script tests/result_ceremony_bootstrap.gd --fixed-fps 60 -- runtime case=p1 fps=60 out=check
& $GODOT --path . --script tests/scoreboard_cutin_bootstrap.gd --fixed-fps 60
& $GODOT --path . --script tests/scoreboard_flicker_bootstrap.gd --fixed-fps 60
```

ランタイムテストは配置（コンベア終端の先・タワーより奥）、配役、レース中の盛り上がり・上昇中の緊張・判定後の反応、
卵の命中、ダンス、勝者側の歓声と敗者側の落胆・「ブーー！」、描画コールと更新コストを確認する（`case=p2` / `case=draw` / `quality=low`）。
