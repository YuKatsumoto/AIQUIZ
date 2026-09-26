# ゴール観客席（Goal Stand）

ゴールを越えたコンベアの先端に建つ3段の立見スタンド。ブロック人形の観客がゴールと勝敗に反応する。
勝った側のファンは歓声・旗・プラカードで喜び、負けた側は頭を抱え、ホットヘッド（鉢巻き・はげ頭の短気な客）は
激怒して負けたプレイヤーに卵を投げつける（引き分けなら審判に）。パーティ客はゲームのエモートをランダムに踊る。

制作は Higgsfield 主体：Blender は Higgsfield コネクタ経由で組み立て・リグ・アニメーション・書き出しまで行い、
看板・プラカード・卵の飛び散り画像と観客の掛け声は Higgsfield の生成モデルで作った。

## 配置と挙動

- スタンド正面はゴールラインから `GoalStand.GOAL_OFFSET`（25.8 m）先。演出中のコンベア終端（+24 m）と
  サイドフレームのはみ出し（1.2 m）のすぐ外側で、海中の柱とアーチで立っている。幅26 m、段差0.55 m、奥行1.35 m×3段。
- P1 側（ワールド +X、画面左）はオレンジ系、P2 側は青系のファン。10% は中立の客。
- 役割：ホットヘッド（片側3人、卵パック持ち）、プラカード（がんばれ／ファイト、負けると「ブーー！」に裏返す）、
  チーム旗、フォームフィンガー、パーティ客（ダンス）、一般ファン。
- 反応：
  | 状況 | 反応 |
  | --- | --- |
  | 通常プレイ中 | 待機（おしゃべり・電話・うなずき・腕組み）。170 m 以上離れると静止して処理を止める |
  | ゴールレース | 手振り・拍手・叫び・祈り。パーティ客は軽くノる。女性の「がんばれー！あとちょっと！」 |
  | 誰かがゴール | そのプレイヤーのファンが歓声ジャンプ、他は拍手（2.8秒）＋歓声 |
  | 演出 0–4.1秒 | 拍手と旗・プラカード。4.1秒〜判定までは息をのむ（祈り・腕組み） |
  | 判定（6.9秒〜） | 勝者側：歓声・指さして笑う・旗振り。敗者側：頭を抱える・首振り・プラカードが「ブーー！」。歓声とブーイング |
  | 卵 | 敗者側ホットヘッドが激怒（顔が赤くなる）→投球を繰り返す。1人3個・全体18個まで、25%は床に外れる。黄身は当たった体に貼り付いて一緒に動く |
  | 引き分け | 全員拍手・歓声、「えーっ！引き分けー？」、ホットヘッドは審判に卵 |

## 素材

| ファイル | 内容 |
| --- | --- |
| `goal_stand.glb` | スタンド本体（段・青いベンチ・胸壁・ペナント・看板・チーム旗・海中の柱とアーチ）。看板画像を埋め込み |
| `goal_stand_spectator.glb` | 観客リグ（23ボーン）＋髪型7種のボディ＋手持ち小道具＋アニメーション25本 |
| `goal_stand_props.glb` | 飛んでいく卵と殻の破片 |
| `goal_stand_layout.json` | 段の高さ・立ち位置・通路（Blender空間。Godotでは (x, z, -y)） |
| `goal_stand_clips.json` | クリップ長・ループ・卵を放す時刻（0.3秒） |
| `textures/egg_splat.png` | 卵の飛び散り（Higgsfield z_image、背景抜き） |
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
プラカードの板だけは画像テクスチャのマテリアル。

## Higgsfield で生成したもの（計 2.75 クレジット）

| 素材 | モデル | 備考 |
| --- | --- | --- |
| 看板 `source/textures/banner.png` | seedream_5_0_flash | ゲームロゴ（icon.jpg）を参照画像に使用 |
| プラカード P1「がんばれ！」/ P2「ファイト！」/「ブーー！」 | seedream_5_0_flash | 単色背景で生成し `key_generated.py` で抜き |
| 卵の飛び散り | z_image | マゼンタ背景から抜き |
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
- `build_stand.py` — スタンド本体と `goal_stand_layout.json`
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
python assets/goal_stand/source/synth_crowd_audio.py
```

## Godot 実装

- `scripts/world/goal_stand/goal_stand.gd` — スタンド・観客の生成（1フレーム6人ずつ）と反応、卵の狙い、効果音。
  画質別の人数：HIGH 78 / BALANCED 71 / LOW 48（ホットヘッドは常に6人）。LOW はアニメを30Hz、
  70 m 以遠は15Hz、170 m 以遠は処理停止。
- `scripts/world/goal_stand/goal_stand_eggs.gd` — 卵の弾道（最後は動く標的に追従）、黄身の貼り付け、殻の破片。
- `scripts/world/game_world.gd` — ゴールラインと同じ条件で生成・配置し、毎フレーム更新。
- `ResultCeremonyDirector.crowd_egg_target()` / `ResultFinaleStage.egg_target()` — 判定後の卵の標的。
- `AudioManager.play_crowd_cue()` — 群衆の効果音（初回使用時に読み込み）。

## 検証

```powershell
& $GODOT --headless --path . --script tests/goal_stand_bootstrap.gd
& $GODOT --path . --script tests/result_ceremony_bootstrap.gd --fixed-fps 60 -- runtime case=p1 fps=60 out=check
```

ランタイムテストは配置（コンベア終端の先・タワーより奥）、配役、レース中の盛り上がり・上昇中の緊張・判定後の反応、
卵の命中、ダンス、勝者側の歓声と敗者側の落胆・「ブーー！」、描画コールと更新コストを確認する（`case=p2` / `case=draw` / `quality=low`）。
