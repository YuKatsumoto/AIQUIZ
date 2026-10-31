# 効果音（SE）

ゲームの効果音は、壁にぶつかった音（2026-10-09、2026-10-12 に差し替え）、スタートのカウントダウンの電子音（2026-10-11）、スタジアムの観客の声・扉の正解と不正解・押し合い・着地、ヘリの乗降・飛行・ブースト、UIクリック・ヘリからの接地・サメの噛みつき・爆散・チップソーの起動（2026-10-12）。メニューでは観客の声は鳴らさない。BGM は `docs/bgm_renewal.md`。

## 鳴る場面

| 音の名前 | 場面 | ファイル |
|---|---|---|
| `bonk` ＋ `door_wrong` | 不正解の扉に当たってハートが 1 つ減ったとき（壁に当たる「打撃」とクイズの「ブー」） | `assets/audio/sfx/se_lab/wall_hit.ogg`、`assets/audio/sfx/game/door_wrong.ogg` |
| `wall_crash` ＋ `door_wrong` | 壁に激突して脱落したとき（最後のハート、扉の間の壁）。打撃を 0.85 倍の音程で少し重く | `se_lab/wall_hit.ogg`、`game/door_wrong.ogg` |
| `door_correct` | 正解の扉をくぐったとき（そのプレイヤーの点数が増えた瞬間） | `assets/audio/sfx/game/door_correct.ogg` |
| `push_kick` | 2人用の押し合いで、押しが決まった瞬間と、同時に押し合った瞬間 | `assets/audio/sfx/se_lab/push_kick.ogg` |
| `jump_land` | 通常のジャンプから着地した瞬間（ヘリからの接地は `heli_land`） | `assets/audio/sfx/se_lab/jump_land.ogg` |
| `countdown_beep` | スタートの壁のカウントダウンで、数字（5・4・3・2・1）が変わった瞬間の「ぷっ」 | `assets/audio/sfx/game/countdown_beep.ogg` |
| `countdown_go` | カウントダウンが終わって壁が割れる瞬間の「ぷーん」 | `assets/audio/sfx/game/countdown_go.ogg` |
| `ai_type_tick` | PV 冒頭で問題文と選択肢を AI が書く演出（ゲームでは鳴らない）で、文字のかたまり（トークン）が 1 つ出るたびの小さな電子音（−12 dB、音程 ±8%。`docs/ai_question_typing.md`） | `assets/audio/sfx/game/ai_type_tick.ogg`（合成） |
| `ai_type_done` | 同じ演出で、問題文と選択肢を書き終えた瞬間の 2 音のきらめき（−10 dB） | `assets/audio/sfx/game/ai_type_done.ogg`（合成） |
| `versus_cutin_in` | オンライン対戦の VS カットインの入り（パネル・稲妻・VS の着地・名前の帯まで、時刻を合わせた 1 本） | `assets/audio/sfx/online/versus_cutin_in.ogg` |
| `versus_charge` | VS の覆いの静止画のあいだ（ゲーム画面を組み立てている間）の溜めの唸り。開く演出で消す | `assets/audio/sfx/online/versus_charge.ogg` |
| `versus_reveal` / `versus_reveal_short` | VS の覆いが稲妻で割れて開く演出（3.20 秒／「みじかい」2.20 秒） | `assets/audio/sfx/online/versus_reveal*.ogg` |

| `score_drum_roll` | 2人用のスコアタワーで、得点の集計が始まる 2.0 秒から塔が登り切る 6.3 秒までのドラムロール（4.3 秒） | `assets/audio/sfx/se_lab/score_roll.ogg`（効果音ラボ「ドラムロール」） |
| `score_drum_finish` | 6.3 秒の静寂のあと、判定の 6.9 秒に鳴るロールの締めの一打（約3秒） | `assets/audio/sfx/se_lab/score_roll_finish.ogg`（効果音ラボ「ロールの締め」） |
| `crowd_goal_cheer` | 誰かがゴールラインを越えた瞬間（2人用は1人ずつ）と、1人用のクリア | `assets/audio/sfx/crowd/crowd_goal_cheer.ogg` |
| `crowd_win_cheer` ＋ `crowd_applause` | 2人用のスコアタワーの判定（6.9秒、引き分けでも） | `crowd_win_cheer.ogg`、`crowd_applause.ogg` |
| `crowd_aww` | 2人用で負けた側のタワーが沈み始める瞬間（7.4秒） | `crowd_aww.ogg` |
| 観客のざわめき（ループ） | ゲーム画面に着いてから、スタート前（WAITING_START / FLYOVER / COUNTDOWN）と、2人用のスコアタワーの判定まで（RESULT_CEREMONY の 0〜6.9 秒） | `crowd_murmur_loop.ogg` |
| 観客の歓声（ループ） | 壁が割れてから（PLAYING / CORRECT / GOAL_RACE）。結果・ゲームオーバー・メニューでは止める | `crowd_race_loop.ogg` |

壁の音は CC0、カウントダウンの音は OtoLogic（CC BY 4.0、クレジット表記が必要）、観客の声は Pixabay・効果音ラボ（クレジット不要、ファイル自体の再配布は禁止）と Freesound の CC0。出典は `assets/audio/sfx/CREDITS.md`。

## 観客の声（2026-10-12）

- ループの2つは `AudioManager.set_crowd_ambience()`（`CROWD_MURMUR` / `CROWD_RACE` / `CROWD_NONE`）で切り替える。0.8 秒でクロスフェードし、新しい方はループのランダムな位置から始める。曲の選択と同じく `game_world.gd` の `_on_state_changed()` で選び、エンドレスの途中の問題補充（PRELOADING）では変えない。ゲーム画面に入ったとき（`_ready()`）にざわめきを始め、出るとき（`_exit_tree()`）に止める。
- ポーズ中はループを一時停止する（`set_music_paused()`）。
- 音量：ざわめき −8 dB（ファイルは −18.2 LUFS。声のピークが大きく全体が小さかったので、コンプレッサーで差を縮めてから上げた。スタート前は曲を止めるので、ざわめきだけが聞こえる）、歓声 −14 dB（ファイルは −20 LUFS）、ゴールと判定の歓声 −6 dB、拍手 −9 dB、「あー…」−8 dB（単発はファイルを −18 LUFS にそろえた）。
- ゴールの大歓声は `game_world.gd` の `_update_crowd_reactions()` が `goal_reached_mask` の増えた瞬間に鳴らす（オンラインでも同期される値）。1人用はゴールでそのままクリアになるので、CLEAR になったときにも鳴らす（`min_interval` で重ならない）。判定の歓声と「あー…」は `ResultCeremonyDirector._update_beats()`。
- **リポジトリが公開なので、Pixabay と効果音ラボの音は git に入れていない**（`assets/audio/sfx/crowd/.gitignore`、`assets/audio/sfx/source/crowd/.gitignore`）。どちらもゲームへの組み込みは許可されているが、ファイル自体の再配布は禁止のため。CC0 のざわめきだけは git に入れてよい。ファイルがない環境では、その音だけ鳴らない（エラーにはならない）。
- 加工：レース中の歓声は元の 35〜69 秒、ざわめきは 33〜125 秒を切り出し、終わりの 2 秒を頭へクロスフェードしてループにした（32 秒、90 秒）。単発は頭の無音を詰め、3 ミリ秒のフェードイン。

## カウントダウン（2026-10-11）

- カウントダウンは 4.99 秒（`QuizGameState.COUNTDOWN_SECONDS`）。壁の数字は `ceil(countdown_timer)` で「5・4・3・2・1」を約 1 秒ずつ表示し、0 秒で壁が割れて PLAYING になる。それまでは 3.99 秒で「4・3・2・1」だった。
- 電子音は、数字が変わった瞬間に `countdown_beep`、壁が割れる瞬間（`_on_state_changed()` で `_explode_start_barrier()` を呼ぶところ）に `countdown_go` を鳴らす（`game_world.gd`）。1 つの長い音を流すのではなく数字ごとに鳴らすので、処理落ちしても数字とずれず。オンラインのゲストも、同期された `countdown_timer` で同じ数字を出すので同じ瞬間に鳴る。
- 素材は OtoLogic の「Countdown01」。1 秒おきの「ぷっ」5 回と「ぷーん」の `Countdown01-3`（元素材は `assets/audio/sfx/source/otologic/`）と同じ聞こえ方になる。ゲームでは単発の `Countdown01-5`（ぷっ）と `Countdown01-6`（ぷーん）を使う。`Countdown01-3` の中の音と波形が一致する（相関 0.99 以上）。
- 加工：頭の 0.1 秒の無音を削り、2 ミリ秒のフェードイン。2 つとも同じだけ（+17.6 dB）上げて、元の音量の比率を保った。ピークは「ぷっ」−1.4 dBFS、「ぷーん」−3.0 dBFS。`SFX_CUES` の音量は 2 つとも −10 dB。

## 仕組み

- **音の一覧と音量**：`scripts/autoload/audio_manager.gd` の `SFX_CUES`。音の名前ごとに、ファイル（複数あればランダム）、音量、ピッチの揺らぎ、連打防止の間隔を書く。音量の調整はここだけで済む。
- **壁にぶつかった音**：`game_world.gd` の `_update_wall_hit_sfx()` が、オンラインの同期データにも含まれる値（`get_damage_time()` と `p1_wall_impact` / `p2_wall_impact`）の変化を見て鳴らす。ゲストにもホストと同じタイミングで聞こえる。
- **SFX バス**で鳴るので、設定画面とポーズ画面の「効果音量」で調整できる。

## UIクリック・ヘリからの接地・死亡・チップソー起動（2026-10-12）

| 音 | 発生する瞬間 | 音量 | ファイル |
|---|---|---|---|
| `ui_click` | ボタンの決定、選択肢、タブ、スライダーへのクリック、スキンの部位選択 | −3 dB（素材ピーク −6 dBFS） | `se_lab/ui_click.ogg`（効果音ラボ「カーソル移動1」） |
| `ui_start` | メニューのゲーム開始ボタン（`start_button`）。`ui_click` の代わりに鳴る | −3 dB（素材ピーク −6 dBFS） | `se_lab/ui_start.ogg`（効果音ラボ「決定ボタンを押す53」） |
| `heli_land` | ヘリから降りた物理の身体が初めて床に触れた瞬間 | −4 dB | `game/heli_land.ogg` |
| `shark_bite` | サメがプレイヤーに接触し、身体を食べる演出が始まる瞬間 | −6 dB | `game/shark_bite.ogg` |
| `body_burst` | 身体が破片に分かれた瞬間（壁、サメ、チップソー、結果、メニューの事故） | −6 dB。サメとチップソーではさらに −5 dB | `game/body_burst.ogg` |
| チップソー起動 | 刃が実際に停止から回転へ移った瞬間（本編のみ。メニューでは鳴らさない） | −8 dB（素材ピーク −3 dBFS） | `se_lab/saw_start.ogg`（効果音ラボ「車のエンジンをかける1」の頭 4.0 秒） |

- `ui_click` と `ui_start` は2026-10-12にユーザーが用意した効果音ラボの素材（`se_lab/` は git に入れない）。ボタンは `AudioManager` が `BaseButton` のメタ `ui_sound_cue` を見て鳴らす音を決める（未設定なら `ui_click`）。メニューの `_ready()` がスタートボタンに `ui_start` を設定している。
- ほかの4つはこのゲーム用に合成した素材。ヘリの接地は両足の重い床の音、噛みつきは短い噛み音と水、爆散は低い破裂音と散る破片。チップソーは約4秒の回転の立ち上がり（`SPINUP_SECONDS = 3.99`）に合わせたモーター音。`tools/audio/make_event_sfx.py` で再生成できる。
- UIは `AudioManager` が `BaseButton.pressed` などを共通で接続する。後から生成されたボタン、キーボード／ゲームパッドでの決定、ポーズ画面にも対応し、プログラムによる値の初期設定や無効なボタンへのクリックでは鳴らない。通常のSEとは別の2つの声を使い、UIの操作で着地・死亡音を切らない。通常のSEは8声。
- ヘリは `HelicopterArrivalDirector` の `floor_contacted` と `impact_played` の切り替わりで鳴らす。物理的な跳ね返りで繰り返さず、乗降中は `game_world.gd` の通常ジャンプの着地音を抑える。
- 噛みつきは `PlayerController.begin_ocean_shark_explosion()` の1回だけの開始処理、爆散は `_init_explosion()` が実際の破片を作ったときに鳴る。チップソーの切断は、保持していたラグドールを破片へ移す処理に合わせる。死亡描画の事前読み込みはこれらの開始関数を通らず無音。
- チップソーは `SawChaseController` が実際の回転率の立ち上がりを見て鳴らす。モデルごとの専用プレイヤーなので、刃の本数や更新回数に応じて重複しない。静止した予熱、非表示、暗転、停止中は鳴らず、機体と一緒に音も片付く。1人用の10問など、チップソーが出ないモードでは鳴らない。
- `tests/event_audio_runtime.gd` は実際のマウスクリック、動的に追加したボタン、無効・初期設定・ポーズ中の操作、1P/2Pの Start と床の接触、実際のサメの攻撃と壁の死亡、メニューと本編の起動を検証する。結果と録音は `artifacts/event_audio/`。`python tools/audio/analyze_helicopter_capture.py --folder artifacts/event_audio` で録音をWAVに変換し、ピークと音割れを検査できる。

## 幽霊サメ（2026-10-16）

2人用で片方が脱落すると、その魂が幽霊サメに乗って生き残った側へ突進する（`GhostSharkRideController`）。その一連の流れに音を付けた。素材はすべてこのゲーム用に合成した（`tools/audio/make_ghost_shark_sfx.py`、48 kHz ステレオ、ピーク −3 dBFS。チャージのループだけ −6 dBFS）。ファイルは `assets/audio/sfx/ghost_shark/`。

| 音 | 発生する瞬間 | 音量 |
|---|---|---|
| `ghost_soul_rise` | 脱落した身体から魂が浮き上がる瞬間（`_begin_soul_rise()`）。息のような上昇音ときらめき | −10 dB |
| `ghost_shark_rise` | 死亡ワイプが落ち着き、サメが海の底から浮上し始める瞬間（`start_ghost_rendezvous_ascent()` が成功したとき）。水中の唸りと上がっていく幽霊の声（浮上 2.45 秒に合わせた長さ） | −8 dB |
| `ghost_shark_breach` | サメが水面を突き破った瞬間（`SharkSwimmer.ghost_breached` シグナル。水しぶきの演出と同じ）。水しぶき・飛沫・遠吠え | −6 dB |
| `ghost_awaken` | 魂が両腕を広げて幽霊として目覚める瞬間（演技の 1.27 秒。吸い込みの 0.16 秒あとに和音が鳴るので 1.11 秒に鳴らす。`GhostRiderPresentation` の拍 `awaken_sound`）。吸い込み・明るい幽霊の和音・低い「ドン」・上へ流れるきらめき（2026-10-21 追加） | −9 dB |
| `ghost_mount_land` | 魂が鞍へ落ちて乗り移る瞬間（`_begin_mounting()` の `_play_mount_impact()`）。体の重いどすん・鞍のはたき・グリップの金属音・サメへ流れ込む幽霊の唸り（2026-10-21 追加） | −6 dB |
| `ghost_mount_beam` | 乗り込んだあと光の柱が立つ瞬間（`ghost_mount_beam_fired`）。点火・持続の唸り・0.34 秒で開き 1.39 秒で落ちる柱の時刻に合わせた電源断・上昇の風切り | −9 dB |
| チャージの唸り（ループ） | 突進ボタンを押しているあいだ（照準中に本当に溜めているときだけ）。メーターに合わせて音程 0.75〜1.7 倍、音量 −14〜−6 dB。メーターが一周して 0 に戻ると音程も下がる | 専用プレイヤー |
| `ghost_dash` | 溜めを離し、構え（WINDUP）のあとに突進が始まる瞬間（`_start_charge()`）。PERFECT は +1.5 dB・1.08 倍の音程、それ以外は溜めの強さで 0.94〜1.04 倍 | −6 dB |
| `ghost_hit` | 突進が生き残った側に当たった瞬間（`_apply_charge_hit()`）。PERFECT は +1.5 dB | −5 dB |
| `ghost_vanish` | 突進を終えたサメが消える瞬間（クールダウンの開始） | −11 dB |
| `ghost_portal_open` | 戻りのポータルが開く瞬間（`_spawn_return_portal()`） | −9 dB |
| `ghost_portal_cross` | サメがポータルから飛び出す瞬間（ポータルの閃光・カメラの揺れと同じ） | −8 dB |

- 2026-10-21 の 2 音は `python tools/audio/make_ghost_shark_sfx.py --only ghost_awaken.ogg ghost_mount_land.ogg` で作った（ほかの音を作り直さない。この 2 音は音ごとの乱数で、作る順に左右されない）。搭乗の見せ方は `docs/ghost_rider_mount.md`。

### サドンデスへ行くときの幽霊の復活（2026-10-21）

引き分けで幽霊のまま表彰台にいる人が、サドンデスの前に体を取り戻す（`docs/sudden_death_v2/ghost_revive.md`、`GhostRevival`）。同じ道具で合成した（`python tools/audio/make_ghost_shark_sfx.py --only ghost_revive_gather.ogg ghost_revive_snap.ogg ghost_revive_burst.ogg`）。体を呼ぶ瞬間は既存の `ghost_awaken`、弾ける瞬間は既存の `sg_revive`（効果音ラボ「回復魔法1」）も重ねる。

| 音 | 発生する瞬間 | 音量 |
|---|---|---|
| `ghost_revive_gather` | 部位を呼び始める（復活の 0.25 秒）。速くなる渦の風・部位が飛んでくる風切り 12 回・上がっていく幽霊の声、最後に吸い込みが弾ける瞬間（1.43 秒後）でぴたりと止まる | −8 dB |
| `ghost_revive_snap` | 部位が 1 つはまるたび。磁石のような「コッ」・短いクリック・ガラスの「チン」・きらめき。はまる順に長音階で音程を上げる（0.72 倍から） | −9 dB（呼ぶ側で −2 dB） |
| `ghost_revive_burst` | 体がそろって弾ける。鋭い破裂・低いドン・広がる長和音・きらめきの雨、0.30 秒後に台へ着地する重い音と床をたたく音 | −5 dB |
- チャージの唸りは `AudioManager` の共通の声ではなく、コントローラーの子の `GhostChargeAudio`（SFX バス、ループ）で鳴らす。音程と音量を毎フレーム変えるため。構え・突進中、メニュー（`menu_sfx_muted`）では鳴らさず、ポーズ中はツリーと一緒に止まる。
- 乗り手が生き返る・結果演出へ降りるなどで途中で畳まれたときは、長い音（魂・浮上・ビーム・ポータル）を 0.3 秒でフェードアウトし、唸りを止める（`_cleanup_ghost_ride()`）。
- 幽霊サメはローカルの2人用だけ（オンライン・リプレイでは出ない）なので、音もローカルだけ。
- `tests/ghost_shark_audio_runtime.gd`（`--script res://tests/ghost_shark_audio_bootstrap.gd`、ウィンドウが要る）が、実際の壁の脱落 → 魂 → 浮上 → 水面 → ビーム → 照準 → PERFECT で外す突進 → ポータルからの復帰 → 生き残った側への命中までを通し、音の順番・鳴ったフェーズ・唸りの音程・離したら止まること・片付けで残らないことを 26 項目で確かめる。SFX バスの録音は `artifacts/ghost_shark_audio/`（`python tools/audio/analyze_helicopter_capture.py --folder artifacts/ghost_shark_audio` で WAV に変換）。2026-10-16 の実行で全項目合格、ピーク −6.1 dBFS・音割れ 0。各音の最大 80 ms RMS は −15〜−22 dB で、同じ録音の爆散（−17.6 dB）・不正解のブー（−15.6 dB）と同じくらい。
- 待ち時間は秒数で書いている。このPCではテストのゲームが約 190 fps で回るので、フレーム数で待つと（`tests/ghost_hud_runtime.gd` の 1800 フレームなど）幽霊サメが照準に着く前に打ち切られる。

## サドンデス「つきやぶれ！スカイゲート」（2026-10-20）

2人用「10問」の引き分けからのサドンデス（`docs/sudden_death_v2/`）に音を付けた。それまでは今ある音の代用で、代用のうち `door_open`・`rotor_spool`・`whoosh_flyby`・`belt_click`・`split_whoosh` などはファイルが無く、実際には鳴っていなかった。水上機のエンジンの音も無かった。

素材はすべて効果音ラボ（ユーザーの指示で 2026-10-20 に 27 ファイルを入手。原本は `assets/audio/sfx/source/se_lab/`）。`tools/audio/make_sudden_death_sfx.py` が切り出し・フェード・ピーク −3 dBFS（ループは −6 dBFS）にそろえて `assets/audio/sfx/se_lab/` の `sd_*`・`fp_*`・`sg_*` を作る。**再配布が禁止なので git に入れない**（`se_lab/.gitignore`。ファイルが無い環境ではその音だけ鳴らない）。作り直したらエディタにファイルを走査させる（取り込み直さないと、ゲームは前の音のまま鳴る）。音量は `SFX_CUES` で、同じ録音の最大 80 ms RMS（再生の大きさ）が今ある音とそろうように決めた（ふつうの出来事は −20 dB 前後、大きな見せ場は −15 dB 前後）。

| 音 | 鳴る瞬間 | 素材（効果音ラボ） |
|---|---|---|
| `sd_whistle` | 決着演出 8.4 秒、審判の笛（両者が踊りをやめて振り向く） | 警官のホイッスル2 |
| `sd_siren` | 8.6 秒「SUDDEN DEATH!」と回転灯。乗り込みの頭（スタンドが上がる）にも小さく | 警報が鳴る（頭 3.2 秒） |
| `sd_tower_move` | 9.0 秒、両方のタワーが床まで沈む。帰還で勝者のタワーが伸び直す。昇降台のデッキが起きる | 巨大モーター起動（頭 2.0 秒） |
| `sd_stand_lift` | 乗り込みの頭、台座の横のスタンドが塔で持ち上がる | 巨大シャッターが開く（頭 3.0 秒） |
| `sd_stand_lower` | 昇降台が 2 人を乗せて下りる・離水のあとスタンドが下りる | 巨大モーター起動（頭 3.6 秒） |
| `sd_servo` | 水上機の上のふたが開く | ロボットが腕を動かす1 |
| `fp_ramp` | スロープが開く・閉まる（油圧。開く速さに合わせて音程を変える） | 巨大ロボットが腕を動かす3 |
| `fp_ramp_latch` | スロープが閉まりきる | 鉄の扉を閉める |
| `fp_belt` | ベルトを締める・外す | 既存の `helicopter/belt_click.ogg`（合成） |
| `fp_flyby` | 乗り込みで水上機が台座の真上を低く越える（いちばん大きい所＝頭から 1.2 秒を、真上を通る時刻（約 1.3 秒）に合わせる。その間エンジンのループを 9 dB 下げる） | プロペラ機上空通過（軍用） |
| `fp_touchdown` | 着水のしぶき | 水面に石投げ2（巨大な石） |
| `fp_green_light` | 降下と帰還で降下灯が緑になる（2026-10-20 に開演ブザーから替えた：不正解のブーとまぎらわしかった） | 既存の `game/countdown_go.ogg`（スタートの壁が割れる「ぷーん」。OtoLogic） |
| `fp_ramp_wind` | 空でスロープが開き、風が吹き込む（2 秒でふくらむ） | 風が吹く2（40〜45.5 秒） |
| `fp_jump` | スロープから飛び出す（降下・帰還） | ジャンプ（風を切る音） |
| `sd_cloud_whoosh` | 雲の覆い（白・暗転）。いちばん強い所が 0.5 秒あたり＝画面が覆われている間 | 突風が吹く（0.42 秒から） |
| `sg_gate_rush` | ボードの高さを通る瞬間（時間切れ） | 高速移動 |
| `sg_tear` | 正解のパネルをつき破る（2 通りからランダム。`door_correct` も一緒） | 紙を破く2・3 |
| `sg_bounce` | まちがいの紙にはね返される（`wall_crash` を小さく重ねる） | ボヨン |
| `sg_safe` | 判定「セーフ！」（全員が正解） | キラッ1 |
| `sg_revive` | 2人とも同じゲートでアウト → その場で復活 | 回復魔法1 |
| `sg_round_gong` | ROUND 2 以降の開始 | 試合開始のゴング |
| `sg_round_clear` | 2人とも地上へ（「ROUND n」） | ラッパのファンファーレ |
| `sg_overtime` | 延長戦 | 突撃ラッパ（頭 3.3 秒） |
| `sg_notice` | 「ボードが動く！」「ボードが小さく・速く！」「早い者勝ち！」 | 警告音2 |
| `sg_chute_open` | パラシュートが開く（2人なら音程を少しずらす） | 傘をさす |
| `sg_float_splash` | 着地台に降りる（`jump_land` と一緒） | 水をバシャッとかける1 |
| `sg_winner` | 決着のあと勝者が着地台に降りる | ジャジャーン |

- **水上機のエンジン**：`FloatplaneSound`（`scripts/world/sudden_death/floatplane/floatplane_sound.gd`、機体の子）。2 つのループを重ねる：エンジン `fp_engine_loop`（戦闘機内（飛行中）の 4〜17 秒、1 秒のクロスフェード）と、プロペラ `fp_prop_loop`（プロペラ機上空通過の近づく間 1.0〜2.2 秒。羽根の音 68 Hz が動かない所。音量のふくらみをならし、前向き＋逆向きでつないだ 2.3 秒）。機体の回転（`prop_speed`）・逆推力（`reverse_mix()`）・推力（`thrust`。`FloatplaneStaging` が場面ごとに入れる）で音量と音程を変える。回転いっぱい・すぐ近くでエンジン −7 dB・プロペラ −7 dB。カメラが機内（貨物室・操縦席）にいるときはこもった音（高域 1500 Hz まで、スロープが開くと 5200 Hz まで）で、エンジンを 1 dB・プロペラを 7 dB 下げる。外では 30 m より遠いと小さく、140〜300 m で消え、高域を落とし、左右に振り、ドップラー（0.86〜1.16 倍）。専用のバスを SFX へ送る。乗り込みの頭（`begin_board`）で有効にし、`hide_all` で止める（試合の頭の描画の予熱では鳴らない）。機体が隠れたとき（飛び去ったあと）は 0.25 秒で消し、カメラのカット（1 フレームで 25 m 以上）はドップラーに数えない。メニュー・ポーズ・画面の暗転では鳴らない。
- **落ちる風**：`SkyGatePresenter` の専用のプレイヤー（`sd_freefall_loop`、風が吹く2 の 10〜34 秒、ふくらみを半分ならして 2 秒のクロスフェード、22 秒）。ルールカードの間は 45%、本戦は `_wind()`（ゲートが近いと弱く、つき破る瞬間に強く）、着地で開く前は 115%、開いたら 22%、着地で消す。スローの間は音程を 0.72 倍まで下げる。本戦を隠す・片付けるときに止める。
- 鳴らす場所：分岐の笛・警報・タワーは `HeliSuddenDeathDirector._update_branch()`、雲の風は `SuddenDeathCloudCover.play()`/`play_black()`、水上機の場面は `FloatplaneStaging`、本戦は `SkyGatePresenter`。監督が試合の頭（`prepare_for_match()`、読み込みの覆いの下）に `AudioManager.preload_sfx(AudioManager.SUDDEN_DEATH_SFX_CUES)` で読んでおく。
- 種目発表のドラムロール・締め、爆散（`barrier_explosion`・`body_burst`）、幽霊（`ghost_soul_rise`）、カウントダウン、扉の正解・不正解、帰還の着地と歓声は今までの音のまま。スロープの踏み音（`step_metal`）は素材が無く、今も鳴らない。
- 音量の見直し（2026-10-20、round2 の録音）：降下でカメラが機外へ出た瞬間（全開の機体のすぐ横・吹き込む風・2 人の飛び出し）が SFX バスでピーク +3.1 dBFS・1 秒の RMS −19 dB になっていたので、機外のエンジンとプロペラを 3〜4 dB、吹き込む風 3 dB、飛び出し 4 dB（2 人めはさらに 5 dB）下げた。2 人ぶん重なる紙・パラシュート・しぶきとボヨンも 2〜3 dB 下げた。
- **着地台のまわりの観客船（2026-10-21、`docs/sudden_death_v2/sky_gate.md` 第9章）**：クラッカーと打ち上げ花火の専用の音はまだ無いので、手持ちの音で代用している。音の名前は専用にしてあるので、替えるときは `SFX_CUES` のファイルだけ替える。音は聞こえる所（カメラ）までの距離の分だけ遅らせ（340 m/秒）、遠いほど少し小さくする（`SkyGateFireworks._sound`）。効果音の声が 8 本しかないので、1 回のクラッカーの波で音を鳴らすのは 3 本だけ（ほかは音なし）。

  | 音 | 鳴る瞬間 | いまの代用 |
  |---|---|---|
  | `sg_popper` | 着地の瞬間、観客がクラッカーを鳴らす（決着はダンスの途中でもう一度） | 爆発の音（`barrier_explosion`）を 2.1〜2.5 倍の音程で短く・−17 dB |
  | `sg_firework_launch` | 船の打ち上げ筒から花火が上がる | 高速移動（`sg_gate_rush`）・−15 dB |
  | `sg_firework_burst` | 花火がはじける | 爆発の音（`barrier_explosion`）を 0.82〜1.0 倍の音程で・−8 dB |
  | `crowd_win_cheer` | 決着で勝者が着地台に着いた（観客船の歓声） | 今までの観客の歓声 |
  | `crowd_goal_cheer` | ROUND のあと 2 人とも着地台に着いた | 今までの観客の歓声 |

- 確かめ方：`tests/sudden_death_v2/skygate_audio_runtime.gd`（`--script res://tests/sudden_death_v2/skygate_audio_bootstrap.gd -- case=p1|round2|both`、ウィンドウが要る。`--fixed-fps 60`）。実際の通しで、場面ごとに鳴るはずの音が鳴ったか、エンジンが乗り込み〜帰還で聞こえて巡航では機内の音になるか、本戦で落ちる風が聞こえるかを見る。Master を絞って SFX バスを録音する（`artifacts/sudden_death_audio/<case>/sfx.f32`、`python tools/audio/analyze_helicopter_capture.py --folder artifacts/sudden_death_audio/<case>` で WAV）。
- 2026-10-20 の結果：p1・round2・both とも失敗 0（場面の順・勝者も合う。鳴った音は 79・115・88 回）。エンジンは乗り込み・巡航・降下・迎え・帰還で聞こえ、巡航では機内の音になり、終わったあとは残らない。本戦の落ちる風は最大 95%。SFX バスの録音（Master の前）のピークは −1.3・−0.4・0.0 dBFS で、2 人が同時に爆散する瞬間（今までの爆発の音 2 つ）の 1 サンプルだけが 1.0 に届く（Master のリミッターが抑える）。いちばん大きい 80 ms の RMS は爆散の瞬間（今までの爆発の音）の −13 dB 前後で、新しい音の山（降下の飛び出し・勝者の着地・水上機の通過・笛と警報）は −14.5 dB 前後。録音全体の RMS は −21 dB。このPCではテストが実時間の約 2.4 倍の速さで回る（`--max-fps 60` を付けても）ので、録音の中の音は実際の遊びより詰まって重なる。

## チュートリアル（練習）（2026-10-26）

新しいチュートリアル（`docs/new_tutorial/phase9_design.md` 2章）の音。それまでは今ある音（効果音ラボの `ui_click`・`ui_start`・`push_kick`・`sg_bounce`・`sd_cloud_whoosh`）の音程を変えて代わりにしていた。すべてこのゲーム用に合成した（`python tools/audio/make_practice_sfx.py`、numpy と ffmpeg、48 kHz モノラル、ピーク −3 dBFS）。自分で作った音なので git に入れている。ファイルは `assets/audio/sfx/practice/`。

| 音 | 鳴る所 | 音量 |
|---|---|---|
| `practice_pop` | 吹き出しが出る「ぽこっ」（ゲーム画面の吹き出しと、画面のコーチの吹き出し） | −12 dB（UI の声。メニューの上でも鳴る） |
| `practice_tick` | 課題の ✓「ピコン」（チェックのカード・看板の ✓・1-6 の端に触れた） | −11 dB（UI の声） |
| `practice_stamp` | クリアカードのスタンプ「ポン」 | −6 dB（UI の声） |
| `practice_rewind` | まきもどし（0.6 秒。テープを巻き戻す「キュルルル」と、止まる「カチッ」） | −7 dB |
| `practice_fence` | 1-2 の見えないさくにはね返される「ぽよん」 | −16 dB |
| `practice_sign_fly` | 看板の壁が空へ戻る「ひゅーん」 | −10 dB |
| `practice_high_five` | 2-1 のハイタッチの「パチン」 | 0 dB |

- 音量は、同じ場面で鳴っていた代わりの音と、最大 80 ms の RMS（再生の大きさ）がそろうように決めた（例：`practice_pop` は、−4 dB で鳴らしていた `ui_click` と同じ −24 dB 前後）。
- 吹き出し・✓・スタンプはメニューの上でも鳴るので `AudioManager.UI_CUES` に入れた（メニューではゲームの効果音を止めているため）。
- 作り直したら、エディタでファイルを走査させる（取り込み直さないと前の音のまま鳴る）。

## 削除したもの

2026-10-09 にほかの効果音はすべて削除した。今回追加した音（UI のホバー・クリック・決定・戻る、ワイプ、カウントダウン、問題のチャイム、ブザー、ハート、ジャンプ、落下、水しぶき、花火、環境音など）と、それより前からあった音（正解音、爆発音、リザルト演出、観客の歓声と卵、サメ、ヘリのローター、のこぎりの船とオペレーター、ロケット椅子、サドンデス、講義ホール）が対象。コードと素材は git の履歴（コミット `e9f2eb1` 以前）から戻せる。

## ヘリ（2026-10-12）

- `OnlineHeliportHelicopter` に機体ごとの `helicopter_sound.gd` を持たせ、メニューの登場・迎え、本編の降下、オンラインの搭乗・離陸・合流で共用する。旧 SE カタログには依存しない。ローターは qubodup の実録 CC0 素材をモノラル化し、低域・高域を整理、ピークを圧縮、0.30 秒のクロスフェードでループ化した。ほかの音はこのゲーム用に合成した。素材は `assets/audio/sfx/helicopter/`、再生成は `tools/audio/make_helicopter_sfx.py`。
- ローターの回転率 `spool` に合わせて音量と音程を連続的に変える。通常飛行のローターは −7 dB、ジェットの溜めは −11 dB、噴射の持続音は −8 dB、点火は −4 dB。溜めと持続音はループを保ったまま音量・音程を変え、点火だけを実際の `jets_ignited` の立ち上がりに 1 回鳴らす。
- ハッチ／ドアの開閉は動き始め、ラッチは閉じきった瞬間、ベルトは締め終わる直前、縄は繰り出し開始、掴む音は手の接触完了に鳴る。巻き上げ音は実際に縄が巻かれているあいだだけ鳴る。初期配置や非表示の状態変化は音を出さず基準値だけ更新する。
- カメラに対する距離と位置で音量・左右定位・高域を変え、遠ざかると薄く消える。ドップラーは 0.88〜1.12 倍に制限して急なカメラ移動でも極端な音程にならないようにした。近くの機体が 2 機なら各音量を約 3 dB 下げる。専用バスを `SFX` に送るので効果音量の設定が効き、メニューの SubViewport でも専用の 3D リスナーを必要としない。
- **オンラインの検索中（マッチング待機）は自機のヘリの音を −10 dB 下げる**：`OnlineStagingDirector._enter()` が `CRUISE` に入ると `helicopter_sound.gd` の `waiting` を立て、全体の音量（`_waiting_scale`）を 0.25 秒ほどかけて `WAITING_DUCK_DB`（−10 dB）まで下げる。`CRUISE` 以外（乗り込み・離陸・合流・並走など）では元の音量に戻る。相手のヘリは下げない。
- メニューの事前組み立て・描画の予熱は無音。実際の乗降開始で有効にし、ワイプの被覆量でフェードする。完了・スキップ・キャンセルはループと単発をすべて停止し、機体が消えると専用バスも削除する。オンラインのキャンセルも残響を即座に停止する。
- `tests/helicopter_audio_runtime.gd` は現在のメニューの無音の事前準備、実際の Start 経路（1P / 2P）、オンライン搭乗・合流、キャンセル・スキップ・音量設定を検証する。`artifacts/helicopter_audio/runtime.json` に出来事とチェック結果、同じフォルダに実機画面と音声を保存する。音声は `AudioEffectCapture` の生データ（各記録の `sample_rate` の stereo float32）を `.f32` に保存する。`python tools/audio/analyze_helicopter_capture.py` で試聴用 WAV とピークの計測結果を作る。7.1 ch の実機ではキャプチャに各ステレオ組が混在するため、このスクリプトで前方の組を取り出す。

## スコアタワーのドラムロール（2026-10-12）

- 素材はユーザーが用意した効果音ラボの「ドラムロール」と「ロールの締め」（`se_lab/` は git に入れない。原本は `source/se_lab/` の `drum_roll.mp3`、`roll_finish.mp3`）。以前の合成スネアロール（`game/score_drum_roll.ogg`）は使わなくなった。
- ドラムロール `score_roll.ogg`：原曲 4.48 秒の頭から 4.3 秒を使い、終わりを 0.12 秒でフェードアウト、−3.2 dB（平均音量は以前の合成ロールと同じ −22.6 dB）。得点の集計が始まる 2.0 秒（`finale_motion.json` の `cast_start`）から、塔が登り切る 6.3 秒までの 4.3 秒（`RESULT_SCORE_ROLL_DURATION`）にちょうど収まる。
- 締め `score_roll_finish.ogg`：頭から 3.0 秒を使い、2.4 秒から 0.6 秒でフェードアウト、+2.4 dB（ピーク −1.4 dBFS）。6.3〜6.9 秒の静寂（ハッシュ）をはさんで、判定の 6.9 秒に結果の曲・歓声・拍手と一緒に鳴る。
- `ResultCeremonyDirector._update_beats()` が鳴らす。ロールは 2.0 秒の瞬間だけ鳴らし、サドンデスの後に判定をやり直すときは（2.0 秒を過ぎているので）ロールは鳴らさず、締めだけが判定で鳴る。演出の片付け（`_reset_presentation()`）で `AudioManager.stop_sfx()` が両方を止めるので、途中で抜けても音が残らない。
- 実際の演出で、2.0 秒にドラムロール、6.9 秒に締め・結果の曲・判定の歓声と拍手、7.40 秒に「あー…」が鳴ることを確かめる（`tests/result_ceremony_audio_probe.gd`。画像を保存するのでウィンドウが要る。`--audio-driver Dummy` で音は出さない）。

## 問題壁の着地・カウントダウン壁・メニューの無音（2026-10-12）

ユーザーが用意した効果音ラボの素材を使う（`se_lab/` は git に入れない。原本は `source/se_lab/`）。

| 音 | 発生する瞬間 | 音量 | ファイル |
|---|---|---|---|
| `wall_land` | 問題壁がコンベアに着地した瞬間（準備中の落下アニメーション。カメラに近い壁ほど大きい） | −4 dB（0.4〜1.0 倍で距離の減衰） | `se_lab/wall_land.ogg`（「ロボットを殴る2」） |
| `barrier_land` | カウントダウン壁が落ちてきて着地した瞬間（カメラシェイクと同時） | −3 dB | `se_lab/barrier_land.ogg`（「ロボットを殴る3」） |
| `countdown_rumble` | カウントダウン中、カウントダウン壁が振動しているあいだ。振動に合わせて 5 秒かけて大きくなり、壁が割れるときに止める | −8 dB | `se_lab/countdown_rumble.ogg`（「ゴゴゴゴ」の頭 5.0 秒） |
| `barrier_explosion` | カウントダウン壁が爆散する瞬間（`countdown_go` の電子音も同時に鳴る） | −3 dB | `se_lab/barrier_explosion.ogg`（「爆発2」） |

- 加工：頭の無音を削り、2 ms のフェードイン、ピーク −3 dBFS。チップソーは頭 4.0 秒（回転の立ち上がり `SPINUP_SECONDS = 3.99` に合わせる）で終わりを 0.5 秒フェードアウト。ゴゴゴゴは 5.0 秒（`COUNTDOWN_SECONDS = 4.99`）に切り、音量を −16 dB から 0 dB へ 2 乗のカーブで上げる（壁の振動 `pow(progress, 4)` に合わせて強くなる）。爆発は終わりを 0.25 秒フェードアウト。
- `game_world.gd` の `_update_start_barrier()` がカウントダウン中に `countdown_rumble` を鳴らし、`_explode_start_barrier()`・カウントダウン以外の状態・ゲーム画面を出るときに `AudioManager.stop_sfx()` で止める。オンラインのゲストも同じ `countdown_timer` で動くので同じ音になる。
- **メニュー画面は UI 以外の効果音を鳴らさない**：`main_menu.gd` が `AudioManager.set_menu_sfx_muted()` でメニュー画面にいるあいだ `menu_sfx_muted` を立てる。`play_sfx()` は UI の音（`UI_CUES`）以外を捨て、メニューで動くチップソー（`saw_chase_controller.gd`）とヘリ（`helicopter_sound.gd`）も鳴らさない。BGM・観客のざわめき・ボタンの音は今まで通り。メニューを出ると（`_exit_tree`）解除する。メニューが入れ替わるときに新しいメニューの無音を解除しないよう、解除できるのは設定したメニュー本人だけ。
- 本編に入ってからのヘリ（降下・接地）とチップソーは今まで通り鳴る。

## 扉・押し合い・着地（2026-10-12）

- 素材：壁の音・押し合い・着地はユーザーが用意した「打撃1」「小キック」「ジャンプの着地」（効果音ラボの素材とみられるので、観客の声と同じく git に入れない：`assets/audio/sfx/se_lab/.gitignore`）。扉の正解・不正解は OtoLogic の「Quiz-Ding_Dong02-1(Fast)」と「Quiz-Buzzer02-1(Mid)」（CC BY 4.0、クレジット表記が必要）。ほかの版（Slow、Single、Short、Long、Multi）は `assets/audio/sfx/source/otologic/` にある。
- 2026-10-09 から使っていた Kenney の壁の音（`game/bonk_1.ogg`、`bonk_2.ogg`、`wall_crash.ogg`）は、使われなくなった（ファイルは残してある）。
- 鳴らす場所はどれも `game_world.gd`。オンラインの同期データにも入っている値の変化を見るので、ゲストにもホストと同じ瞬間に聞こえる。
  - 不正解・脱落：`_update_wall_hit_sfx()` が `get_damage_time()` と `p1_wall_impact` / `p2_wall_impact` の変化を見る（前からの仕組み）。
  - 正解：同じ関数が、PLAYING / CORRECT / GOAL_RACE の間に `score` / `player2_score` が増えた瞬間に鳴らす。
  - 着地：同じ関数が、高さ（`player_y` / `player2_y`）が 0.25 を超えてから 0 に戻った瞬間に鳴らす。生きていて、コース上の状態（スタート前・プレイ中）のときだけ。
  - 押し合い：`_on_local_push_event()` が、デュエルの `hit` と `clash` の出来事で鳴らす。
- 加工：頭の無音を削り（3 ミリ秒前から）、2 ミリ秒のフェードイン。打撃・小キック・着地はピークを −3 dBFS に、ピンポン・ブーは −18 LUFS にそろえた。音量は打撃 −11 dB（脱落は −9 dB）、ピンポン・ブー −6 dB、小キック −13 dB、着地 −5 dB。ピークだけでなく実際の打音の強さを踏まえ、押し合いと着地の聞こえ方をそろえた。
- 実際のゲーム画面で鳴ることを `tests/gameplay_sfx_runtime.gd`（`--script res://tests/gameplay_sfx_bootstrap.gd`）で確かめた。

## 音量バランスの調整（2026-10-12）

- 押し合い −8 dB、通常着地 +7 dB、ヘリ接地 +2 dB、チップソー起動 +5 dB。強かった壁の打撃は −7 dB、脱落時は −8 dB、カウントダウンは −2 dB、ドラムロールは −1 dB、噛みつきは −1 dB。爆散と正解／不正解の音は据え置き。
- ヘリはローター +4 dB、溜めと噴射 +5 dB、巻き上げ +10 dB。近距離の基準を 26 m から 36 m、高域の減衰開始を 30 m から 45 m に変えた。遠方のフェードと2機時の補正は維持。機構音は素材に合わせ、開 −7 dB／閉 −11 dB／ラッチ −3 dB／ベルト −1 dB／縄 −6 dB／掴む音 −4 dB。
- 観客のざわめき −3 dB、レースの持続歓声 −2 dBで、動作音が埋もれにくくした。BGM本体の音量とユーザーの保存済みスライダーは変更していない。
- Master に `AudioEffectHardLimiter`（入力ゲイン 0 dB、上限 −1 dB、release 0.1秒）を1つ置く。通常の音量を上げず、2人の接地や死亡音が重なった瞬間のピークだけを抑える。
- `tools/audio/probe_audio_balance.gd` を実機ゲームへ注入し、2Pの実際の Start → ヘリ降下 → 接地と、BGM・観客音のある共通SEを録音した。`python tools/audio/analyze_audio_balance.py` が最も強い80ミリ秒のRMSと最終ピークを比較する。Masterで押し合いと通常着地の差は13.86 dB → 0.74 dB。最大スライダーで接地／噛みつき／爆散を2人分同時に鳴らした出力は、+3.57 dBFS・83クリップサンプル → −2.11 dBFS・0クリップサンプル。
- 録音・画面・計測値は `artifacts/audio_balance/`。`balance_before_after.mp3` は前半が変更前、1秒の間を挟んだ後半が変更後。各ブロックは押し合い → 通常着地 → ヘリ接地 → 壁の順で、追加の音量正規化はしていない。
