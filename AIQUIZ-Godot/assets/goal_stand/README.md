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
  追加演出（[docs/crowd_extras.md](../../docs/crowd_extras.md)）：応援団長（P1 メガホン／P2 太鼓）、肩を組む・ハイタッチする 2 人組、
  子どもの肩車、タオル回し、居眠り、ポップコーン・ホットドッグを食べる客、自撮り、双眼鏡、通路を歩くビールの売り子 2 人、
  前列のマスコット（ハテナ）。
- 反応：
  | 状況 | 反応 |
  | --- | --- |
  | 通常プレイ中 | 待機（おしゃべり・電話・うなずき・腕組み）。170 m 以上離れると静止して処理を止める |
  | ゴールレース | 手振り・拍手・叫び・祈り。パーティ客は軽くノる。女性の「がんばれー！あとちょっと！」 |
  | 誰かがゴール | そのプレイヤーのファンが歓声ジャンプ、他は拍手（2.8秒）＋歓声 |
  | 演出 0–4.1秒 | 拍手と旗・プラカード。4.1秒〜判定までは息をのむ（祈り・腕組み） |
  | 判定（6.9秒〜） | 勝者側：歓声・指さして笑う・旗振り。敗者側：頭を抱える・首振り・横並びのプラカードが「OH MY GOT」。歓声とブーイング |
  | 卵 | 敗者側ホットヘッドが激怒（顔が赤くなる）→判定が出ている間ずっと投げ続ける（数に上限なし）。25%は床に外れる。当たると殻が散り、生卵の中身が体と床に残る（下の「卵の割れ方」） |
  | 引き分け | 全員拍手・歓声、「えーっ！引き分けー？」、ホットヘッドは審判に卵 |
  | カウントダウン／スタート | 前のめりで身構え、スタートで歓声（居眠り客は飛び起きる） |
  | 失敗・HP 減少 | 失敗した側のファンは頭を抱える・首を振る、2人用では相手のファンが指さして笑う |
  | ウェーブ・応援の拍 | 右スタンドから来たウェーブが通ると立ち上がって両手を上げる。応援団長の 0.5 秒の拍で頭上の手拍子 |
  | 勝者のダンス（判定後） | 盛り上げ役と勝者側のファンの約 4 割が、勝者と同じエモートを同じ拍で踊る |

## 素材

| ファイル | 内容 |
| --- | --- |
| `goal_stand.glb` | スタンド本体 `GS_Stand`（段・青いベンチ・胸壁・ペナント・チーム旗・海中の柱とアーチ）と電光掲示板 `GS_Scoreboard`。ヘッダー看板・電球盤・鋼板の画像を埋め込み |
| `goal_stand_spectator.glb` | 観客リグ（23ボーン）＋髪型7種のボディ＋手持ち小道具＋アニメーション52本 |
| `goal_stand_props.glb` | 飛んでいく卵と殻の破片 |
| `goal_stand_layout.json` | 段の高さ・立ち位置・通路（Blender空間。Godotでは (x, z, -y)） |
| `goal_stand_clips.json` | クリップ長・ループ・卵を放す時刻（0.3秒）・ダンスの元の長さ（`source_seconds`）・ウェーブで立つ時刻（`rise`）・肩車の位置（`kid`）・応援の拍（`leader_beat`） |
| `goal_stand_egg_contents.glb` | 生卵の中身の基準形（シェーダーが曲げて使う単位形）：白身 `GSE_White`（72本のスポークの放射状ディスク）、黄身 `GSE_Yolk`（UV球）、カラザ `GSE_Chalaza`（3本撚りの縄）、雫 `GSE_Drip`（旋盤）、糸 `GSE_Strand`（管）、筋 `GSE_Ribbon`（帯）。`source/build_egg_contents.py` をライブの Blender で実行して作る（`goal_stand_crowd.blend` の `GS_EggContents`）。glTF は V を反転するので、シェーダーは t = 1 − UV.y で読む |
| `source/textures/sb_*.png` | 電光掲示板のヘッダー看板・鋼板（Higgsfield）と電球盤（手続き生成）。`prep_scoreboard_textures.py` で作成 |

アニメーション（30fps）：

- 独自（`author_actions.py`、IKで作成）：`SPEC_Cheer` `SPEC_Clap` `SPEC_Rage` `SPEC_Despair` `SPEC_Wave`
  `SPEC_Anticipate` `SPEC_PointLaugh` `SPEC_SignUp`
- Quaternius UAL（CC0、`assets/animations/cc0_quaternius`）から：`SPEC_Idle` `SPEC_Talk` `SPEC_Phone` `SPEC_FoldArms`
  `SPEC_ShakeHead` `SPEC_Nod` `SPEC_HoldUp` `SPEC_Throw` `SPEC_DanceBounce` `SPEC_Shout`
- 追加演出（`author_crowd_extras.py`）：`SPEC_Gasp` `SPEC_Doze` `SPEC_WakeUp`（一回だけ） `SPEC_Eat` `SPEC_HighFiveL/R`
  `SPEC_ShoulderL/R` `SPEC_Selfie` `SPEC_Binoculars` `SPEC_Megaphone` `SPEC_Drum` `SPEC_ChantClap` `SPEC_StandWave`
  `SPEC_TowelSpin` `SPEC_CarryKid` `SPEC_KidRide` `SPEC_KidSit` `SPEC_VendorWalk`（UAL `Walk_Loop` の脚） `SPEC_VendorCall`
- ゲームのエモート（Mixamo FBX）をリターゲット：`SPEC_Dance_YMCA` `Gangnam` `Silly` `HokeyPokey` `RunningMan`
  `WaveHipHop` `Swing` `StepHipHop` `SlideHipHop` `Moonwalk` `HipHop` `House` `HipHop2` `Thriller`（4部を連結）。
  FBX は 60fps なので元の 2 フレームを 1 フレームにして、実際の速さ・全長で作る（2026-10-14 までは半分の速さだった）。
  両リグは同じTポーズ・-Y向きなので、ボーンごとにワールド空間の回転差分を移し、
  腰の移動は脚の長さ比で縮めてから1.5秒の移動平均を引いて段から出ないようにしている。

小道具の追加（`build_crowd_props.py`）：`GSP_Popcorn` `GSP_HotDog` `GSP_Phone` `GSP_Binoculars` `GSP_Megaphone`
`GSP_Drum`（太鼓とバチ）`GSP_Towel` `GSP_TowelNeck` `GSP_Keg` `GSP_Cup`。色の役割に 12 ポップコーン・13 赤・14 金属・15 パンを追加。

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

`scripts/world/goal_stand/goal_stand_eggs.gd`（飛行・着弾・殻）と `goal_stand_egg_contents.gd`（中身）。着弾時の速度と当たった面の向きから計算する。

- 卵は面に数フレーム潰れてから割れる。殻の破片は面で跳ね返り、空気抵抗を受けて回転しながら床で弾み、平らに寝て止まってから消える。
  体に当たったときは破片の35%が白身に刺さって残り、飛ぶ破片のうち最大3個は白身の糸（`GoalStandEggStrand`）でしばらくつながる。
- 体のどこで割れるか：投げた向きをカメラ側へ傾けたレイで、標的の本当の面を探す（`GoalStandEggBody`）。ブロックマンは部位ごとの箱、
  審判（スキン付きのマスコット）はボーンごとのカプセル（半径はスキンの頂点から一度だけ測る）。胸の下に続く腰のように同じ面に並ぶ箱は1枚の面として扱う。
  中身は標的の子にせず、毎フレーム部位の座標系に合わせる。P2 勝利でステージが左右反転しても、座標系はいつも右手系にする（裏返って照らされない）。

### 中身の物理（`GoalStandEggRheology`・`GoalStandEggSplat`）

卵は実物の約5.6倍（長さ0.32 m）だが重力は実物どおりなので、フルード数とボンド数の相似で定数を換算する
（速さと時間は √S 倍、動粘性は S^1.5 倍、表面張力/密度は S² 倍、体積は S³ 倍）。こうすると「実物の卵を近くで撮った」動きになる。

| 段階 | 動き |
| --- | --- |
| 衝撃（0〜60 ms） | 水様卵白が法線方向の速さの約0.6〜0.9倍で膜になって広がり、35〜70 ms で止まる。投げた向きほど遠くへ伸び、縁には間隔も長さも不ぞろいな指が出る。長い指の先から飛沫が飛ぶ |
| 跳ね戻り（〜300 ms） | 濃厚卵白のドームは行き過ぎてから 10〜18% 戻る（減衰するばね）。黄身は扁平から1〜3回だけ揺り戻して1秒以内に止まる（ゼリーのように揺れ続けない） |
| 重力（斜面のみ） | 水様卵白が一番低い山に集まって筋になり、下向きの縁まで流れて雫になる（接触線が引っかかるので u = 0.12·g·sinθ·h²/3ν）。濃厚卵白はビンガム流体のようにゆっくり下がり、薄くなると2〜4秒で止まる。黄身は付着力（5〜12 m/s²）が重さに負けると白身の中を滑り、縁を越えると落ちる |
| 雫（`GoalStandEggDrip`） | テイトの法則の量までたまると、体積を保ったまま糸が伸びて細くなり、切れる。下は落ち、糸の中ほどは衛星滴になり、縁に残った糸は跳ね上がって玉になる。水様卵白は0.2秒ほど、濃厚卵白は1〜2秒の長い糸。ぶら下がった雫は体の動きに遅れて揺れる |
| 黄身の破裂 | 強い命中（体では55%、床では35%）や黄身への重ね当てで膜が裂ける。斜面では黄身が厚い筋になって流れ出し、袋はしわを寄せてしぼむ。床では平たく広がる。体積は保存 |

床に落ちた雫・飛沫・黄身は、敗者のリフトの天板（`ResultFinaleStage.egg_support()`、リフトと一緒に上下する）か、なければコンベアに水たまりを作り、近くの水たまりや外れた卵に合流する。

### 描き方

すべてのスプラットが1つのマテリアルを共有し、物理の結果をデータテクスチャの1行（48本の縁の半径＋膜・ドーム・面の範囲・筋）で受け取る。
メッシュは単位形で、シェーダーが面の範囲で箱の角を折り返したり（丸み5 mm）、カプセルに巻き付けたりする。CPU 側の `GoalStandEggSplat.wrap_point()` と同じ式。

- 白身（`shaders/goal_stand_egg_white.gdshader` / `_lite`、本体は `.gdshaderinc`）：透明な薄膜と、わずかに濁ったゲルのドームの2層。縁に表面張力の盛り上がりと光る線。
  BALANCED 以上（デスクトップ）は膜の厚みに応じて背景を屈折させる（ずれ = 厚み × 0.35 × 投影 ÷ 距離）。LOW・モバイルは屈折なしの乳白色の層。
- 筋（`goal_stand_egg_rivulet`）：帯に放物線の断面と膨らんだ先端。黄身の流れは袋のあった所で広いしみになってから細くなり、縁は淡い黄色。
- 黄身（`goal_stand_egg_yolk`）：球と同じ体積の半回転楕円体のドーム（高さ/幅0.58）。卵黄膜はクリアコートのつやと逆光の透け、胚盤、潰れたときだけ出る細かいしわ。破れた所はつやのない黄身と淡い膜の縁。
- 雫（`goal_stand_egg_drip`）：縁の付け根・糸・滴をなめらかにつないだ旋盤。落ちる滴は小さなレンズとして背景を逆さに屈折させ、揺れる。
- 糸（`goal_stand_egg_strand`）：2次ベジェの管。張るほど細く、切れる直前に数珠状になる。カラザは黄身の両極から出る目立たない縄。

### GPU 流体（HIGH / ULTRA、デスクトップ）

`goal_stand_egg_fluid.gd` ＋ `shaders/goal_stand_egg_fluid.glsl`（計算）＋ `goal_stand_egg_fluid_surface.gdshader`（描画）。
体への命中では水様卵白の35%を粒子として流体に渡し（スプラットの帳簿から差し引く）、そのスプラットは CPU の飛沫を出さない。

- 粒子の5分の3は膜と一緒に外へ飛ぶ飛沫、残りは膜の中に残って体を伝い、縁から滴って天板に溜まる。
- 位置ベース流体（PBF）：1/120秒刻み、密度の制約を2回反復、引っ張りの補正（s_corr）で粒がまとまってしがみつく。
  XSPH の粘性は水様卵白・濃厚卵白・黄身で変える。体の当たり判定（大きい順に16個）と天板・コンベアに触れている粒は、
  斜面の重さが保持力（4.5〜8.5 m/s²）に負けると滑り、勝っていれば体と一緒に動く。補正は1回に間隔の4分の1まで、速さは 25 m/s まで。
- 粒子はリングバッファ（HIGH 4096 個・間隔 1.8 cm、ULTRA 8192 個・1.5 cm）で、古いものから上書きされ、12秒で薄れて消える。
- 描画：天板を中心にした 1.8 × 2.4 × 1.8 m の3Dグリッド（HIGH 1.6 cm、ULTRA 1.3 cm）に粒を積み、8ボクセルごとの粗いグリッドで
  空の所を飛ばしながらレイマーチし、等値面を二分法で詰める。深度を書くので体や白身との前後関係は正しい。透明な滴は背景を屈折させる。
- ヘッドレス・Compatibility・モバイル・BALANCED 以下では動かず、CPU の飛沫だけになる。

### 上限（投げ続けても増えない）

| | LOW | BALANCED | HIGH | ULTRA |
| --- | --- | --- | --- | --- |
| 体のスプラット（標的ごと） | 5 | 7 | 10 | 12 |
| 床のスプラット | 6 | 10 | 14 | 16 |
| 水たまり | 8 | 14 | 24 | 32 |
| 垂れている雫 | 3 | 6 | 10 | 14 |
| 落ちている滴 | 16 | 28 | 44 | 60 |
| 落ちた黄身 | 3 | 5 | 6 | 8 |
| 糸（同時） | 0 | 3 | 9 | 9 |

上限を超えたら一番古いものから1.2秒かけて薄くなって消える（上限+2で即座に消す）。ノードはプールで使い回す。モバイルは BALANCED が上限。
近くのスプラットへの命中は合体する（体積が増え、縁が新しい命中点から押し広げられ、黄身が増える。3個を超えると古い黄身が破れる）。

### 確認

- `Godot --headless --path . --script tests/goal_stand_egg_contents_bootstrap.gd`：物理モデル（体積保存、広がる時刻、跳ね戻り、黄身の揺れ、筋と雫の時間、破裂、反転した体への追従など）
- `Godot --headless --path . --script tests/goal_stand_eggs_bootstrap.gd`：殻・中身・上限・`clear()`
- `Godot --path . --resolution 1280x720 --script res://tests/goal_stand_egg_look_bootstrap.gd -- quality=high [barrage=15] [p2]`：
  リフトの上のブロックマンに決まった順で当て、近距離・側面・遠景・胸の上の縁・床の5カメラで撮る（`artifacts/goal_stand/eggs/<quality>/`）。
  更新時間と GPU 時間を記録し、HIGH 以上では流体の粒子を読み戻して NaN・体へのめり込み・飛び散りすぎがないことを確かめる
- `tests/result_ceremony_runtime.gd`（`runtime case=p1|p2|draw`）：本物のフィナーレで体と床に中身が残ることを確かめ、標的の接写を `<case>_eggs_closeup.png` に保存する
- 中身の形を作り直すとき：ライブの Blender で `goal_stand_crowd.blend` を開き、`exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/build_egg_contents.py", encoding="utf-8").read())`、終わったら保存する

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

生成物の元ファイルは `source/generated/`。

## 編集可能な制作データ（`source/`、Godotの読み込み対象外）

Higgsfield Blender コネクタ（Blender 5.1）で実行する。開いているセッションに `AIQUIZ_GoalStand` シーンを追加して作業し、
他のシーンには触れない（同名の他シーンのオブジェクトがあれば停止する）。

- `gs_common.py` — 定数・パレット・箱メッシュ生成・キー書き込み
- `build_rig.py` — UAL マネキンから指を除いた `RIG_Spectator`
- `build_bodies.py` — 髪型7種のブロック人形（各箱を1ボーンに100%スキン）
- `pose_lib.py` / `author_actions.py` — ポーズソルバー（2ボーンIK）と独自リアクション
- `retarget_dances.py` — エモートのリターゲット（実際の速さ・全長・連結、`source_seconds` を記録）
- `author_crowd_extras.py` / `build_crowd_props.py` — 追加演出の動き 20 本と小道具 10 種
- `preview_crowd_extras.py` — 動きを並べた確認用レンダー（`artifacts/crowd_extras/`）
- `goal_stand_crowd.blend` — 観客の作業ファイル（`build_all.py` の観客部分を実行して保存したもの）
- `bake_ual.py` — UAL クリップの焼き込みと卵を放す瞬間の計測
- `build_props.py` — 卵・卵パック・フォームフィンガー・旗・プラカード
- `prep_word_signs.py` — 手描きの「OH」「MY」「GOT」を看板テクスチャに整える
- `build_stand.py` — スタンド本体と `goal_stand_layout.json`
- `build_scoreboard.py` — 電光掲示板 `GS_Scoreboard`（`goal_stand_layout.json` に画面位置 `scoreboard` を追記）
- `prep_scoreboard_textures.py` — 掲示板のテクスチャ（ヘッダー看板の切り出し・鋼板のタイル化・電球盤の描画）を `textures/sb_*.png` に書き出す
- `export_goal_stand.py` — GLB 3種と `goal_stand_clips.json`（`EXPORT_ONLY = ["spectator"]` で観客だけ）
- `preview.py` — 確認用レンダー（`artifacts/goal_stand/blender/`）
- `key_generated.py` — 生成画像の背景抜き
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
```

## Godot 実装

- `scripts/world/goal_stand/goal_stand.gd` — スタンド・観客の生成（1フレーム6人ずつ）と反応、卵の狙い。
  画質別の人数：HIGH 78 / BALANCED 71 / LOW 48（ホットヘッドは常に6人）。LOW はアニメを30Hz、
  70 m 以遠は15Hz、170 m 以遠は処理停止。
- `scripts/world/goal_stand/goal_stand_scoreboard.gd` — 電光掲示板の表示（スコア表と勝者カットイン）。
- `scripts/world/goal_stand/goal_stand_eggs.gd` — 卵の弾道（最後は動く標的に追従）と割れた後の物理（下の「卵の割れ方」）。
- `scripts/world/goal_stand/goal_stand_egg_*.gd` — 生卵の中身：`contents`（描画と管理）、`splat`（スプラットの物理）、`rheology`（換算定数）、`body`（当たり判定とアンカー）、`drip`（雫）、`strand`（糸）、`fluid`（HIGH 以上の GPU 流体）。
- `scripts/world/crowd/crowd_cues.gd`（`CrowdCues`）— 観客への合図（カウントダウン・スタート・失敗・HP・驚き・ウェーブ・応援・勝者のダンス）。
- `scripts/world/crowd/stand_mascot.gd`（`StandMascot`）— 客席のハテナ。
- `scripts/world/game_world.gd` — ゴールラインと同じ条件で生成・配置し、毎フレーム更新。
- `ResultCeremonyDirector.crowd_egg_target()` / `ResultFinaleStage.egg_target()` — 判定後の卵の標的。

## 検証

```powershell
& $GODOT --headless --path . --script tests/goal_stand_bootstrap.gd
& $GODOT --path . --script tests/result_ceremony_bootstrap.gd --fixed-fps 60 -- runtime case=p1 fps=60 out=check
& $GODOT --path . --script tests/scoreboard_cutin_bootstrap.gd --fixed-fps 60
& $GODOT --path . --script tests/scoreboard_flicker_bootstrap.gd --fixed-fps 60
```

ランタイムテストは配置（コンベア終端の先・タワーより奥）、配役、レース中の盛り上がり・上昇中の緊張・判定後の反応、
卵の命中、ダンス、勝者側の歓声と敗者側の落胆・「ブーー！」、描画コールと更新コストを確認する（`case=p2` / `case=draw` / `quality=low`）。
