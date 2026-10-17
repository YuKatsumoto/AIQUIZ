# PV の撮影（Godot の本編をそのまま撮る）

PV（ゲームクリエイター甲子園2026 応募用、絵コンテは `docs/pv/storyboard.html`）の 3D のカットは、本物の GameWorld を動かして撮る。
外から決めるのは「問題」「壁の速さと位置」「キー入力」「カメラ」「時間の速さ」だけ。ゲーム本体には、PV 撮影のときだけ
通過した壁を残すスイッチ（`quiz_wall.gd` の `keep_after_pass_for_capture`、ゲームでは常に false）を 1 つ足した。

## 撮り方

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_capture_bootstrap.gd -- quality=ultra
```

| 引数（`--` の後ろ） | 内容 |
|---|---|
| `quality=ultra` | 画質（既定 ultra）。最高画質の超解像は上限の 2 倍に固定（内部 3840×2160 → 1920×1080） |
| `frames=<N>` | 撮るフレーム数（既定 562 = S01 221 + S02 116 + S03 225） |
| `only=1,114,228` | そのフレームだけ保存（構図の確認用。シミュレーションは全フレーム回す） |
| `png` | JPEG（品質 0.95）ではなく PNG で保存 |
| `seed=<N>` | ドアの破片の乱数（既定 7） |
| `tag=<名前>` | 出力先 `artifacts/pv_capture/<tag>/`（既定 `s01_s03`） |
| `emote_at=<f>` | P1 のエモートを押す PV フレーム（既定 344） |
| `logo_cam=ex,ey,ez,lx,ly,lz,fov` | 突破のフレームから先のカメラを置き換える（ロゴ案 A の背景用）。目と注視点は P1 からの x・z の差と描画座標の y、fov は縦の画角。使ったカメラは report の `logo_cam` に残る。ロゴ案 A は `docs/pv/logo_a/` |

- 出力は `pv_NNNN.jpg`（PV のフレーム番号。1 = 曲の頭）と `report.json`（4 フレームごとの 2 人・壁・チップソーの位置、脱落した P2 の体の位置つき）。
- `--fixed-fps 60` なので、フレームごとにゲームが 1/60 秒（× time_scale）ずつ進む。何度撮っても同じ絵になる。562 フレームで約 40 秒。
- 撮影中にウィンドウのフォーカスが外れても、押しているはずのキーは押し直す（同じ絵になる）。
- After Effects に連番を読み込んだままだとファイルが上書きできないので、撮り直す前に `release_bg.jsx` で外す（下）。
- 設定ファイルは `user://pv_capture_settings.json` に逸らし、`user://settings.json` が変わらないことを確かめる（report の `settings_unchanged`）。
  戦績・評価・リプレイは記録しない（テストのハーネスとして起動するため）。

## S01〜S03 の中身（`tests/pv_capture/pv_capture_runtime.gd`）

| 項目 | 値 |
|---|---|
| 状態 | `tests/hp_unit.gd` の `fixture(2)`：ローカル 2P・10 問モード・PLAYING。ヘリの到着・カウントダウン・空撮は飛ばす |
| 場所 | 2 人は描画座標 z = +24（ベルトの後端から 36.5 m、両側に観客席）、x = +1.5（P1）／−1.5（P2）から走る |
| 1 問目 | 「Q1 このゲームの もんだいを つくっているのは だれ？」、選択肢「AI」「せんせい」、正解 0 番（青いドア・x=+3.5・画面左） |
| 看板の折り返し | ゲームは改行と和文間の空白を詰めて自動で折り返すので、「Q1 このゲームのもんだいを / つくっているのはだれ？」の 2 行になる文にした（`measure_question.gd`） |
| 2 人の見た目 | P1 プロペラ帽子、P2 キツネ帽子と、それぞれの塗りを定数で固定（このPCの保存データは読まない） |
| ハート | P1 は 3、P2 は 1 から始める（HUD は映らない）。P2 は最初の不正解で脱落し、ゲームどおり壁に激突して吹き飛び、2 秒後に爆散する |
| 壁 | 2.9 m/s（ゲームの典型）。P1 の突破が PV 3.7833 秒（3 小節目の頭の 2 フレーム後）になるよう、P1 の前進量から壁の最初の位置を逆算する |
| チップソー | PV だけ追う距離を 26 m に広げる（ゲームは 14 m）。P2 が前へ飛び出しても S01 のカメラより後ろに留まる |
| スロー | 突破から PV 0.6 秒は `Engine.time_scale = 0.5`、そのあと 0.15 秒で 1.0 へ |
| 画面 | HUD と全 CanvasLayer を隠す（撮影中に足されるものも毎フレーム隠す）。BGM のバスは消音（効果音は残る）。昼の位相 0.25 |

### 入力（本物のキーイベント。`KEYS` の表）

動きは控えめにする。P2 は 1 本の斜めの線で「せんせい」へ、P1 は横へ 1 回寄って最後に前へ走るだけ。ジャンプ・押し合い・
小さな当て直しはしない。前と横を同時に押すと斜めに動く（ゲームが入力を正規化するので各 7.6 × 0.71 m/s）。
P1 = A（画面左）/D/W/Space、P2 = ←（画面左）/→/↑/右 Ctrl。脱落した P2 のキーは送らない。

| PV フレーム | 起きること |
|---|---|
| 3〜24 | P2 が迷わず全速力で、↑＋→ で斜めに「せんせい」のドアの正面へ。そのあと ↑ だけで真っすぐ |
| 81 | P2 が「せんせい」に激突して脱落（ハート 1 → 0）。後ろ・外側へ吹き飛ぶ |
| 128〜143 | P1 が A で「AI」のドアの正面へ寄る |
| 201 | P2 が爆散する（激突の 2 秒後。ゲームの `WALL_RAGDOLL_DURATION`） |
| 212〜227 | P1 が W で走ってドアへ |
| 222 | S02 へ切り替え（P1 の中心は壁の手前の面から 0.9 m。体はまだ扉の手前） |
| 228 | P1 が「AI」のドアを突き破る（突破のフレームで W を離す。そのあとは前へ走らない） |
| 344 | P1 のエモート（カンナムスタイル）。S03 は踊るだけ |

壁の最初の位置は、P1 の入力をフレームごとに正規化して数えた前進量から逆算する（`_compute_scroll0`）。
入力を変えると乱数の消費も変わり、ドアの破片の散り方が変わる。そのときは `seed=` を何通りか試して選び直す（今は 7）。
撮影の終わりに、P1 が生きている・P2 が壁の激突で脱落した・P2 の爆散が S01 の中・S02 への切り替えが突破より前、を確かめ、
外れたら `failures` に書いて終了コード 1 にする。

### カメラ（`CameraController.set_director_pose()`、ゲームの Camera3D をそのまま使う。揺れは乗らない）

揺れて見えないよう、2 人の位置を毎フレーム追わない。カメラの動きは時間で決めたなめらかな動き（イーズ）と、
壁といっしょの等速の動きだけ。S02 からは、S02 の頭で決めた P1 の位置だけを見る。

| カット | フレーム | 位置・向き | 画角（縦） |
|---|---|---|---|
| S01 | 1〜221 | 2 人の後ろ・上から（スタートの 10 m 後ろ・床から約 4.5 m）。1.6 m だけゆっくり引きながら「せんせい」の側へ少し振る。P2 が吹き飛んで爆散する所（スタートの 2.5 m 後ろ・x = −6 あたり）まで画面に収める | 45.75°（24mm 相当） |
| S02 | 222〜337 | P1 がドアに触れる直前に切り替える。壁といっしょに動き、壁の向こう 6.5 m・床から 0.95 m から青いドアを見る。突破のあとは、突破した位置の P1 の前 4.2 m へなめらかに寄り、P1 を見る | 53.70°（20mm 相当） |
| S03 | 338〜562 | S02 の続き。1 秒かけて胸の高さへ上がって 1.5 m 引き、P1 を画面の下半分の中央に置く（上半分にロゴ） | 53.70° |

## S03 のロゴ（After Effects）

`docs/pv/previz/ae/build_s03.jsx`：撮影の連番（PV フレーム 338〜562）を背景に、軽くぼかして（14）暗くし（38%）、
タイトルロゴの AEP（`tools/title_logo_ae/AIQUIZ_TitleLogo.aep`。読み込むだけで元のファイルは変えない）の 0.35〜4.622 秒を
2 倍速で重ねる。約 2.14 秒で完成し、残りは止めて 4% だけ寄る。ロゴは画面の上寄り（y = 335）。

```
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/release_bg.jsx   # 撮り直す前（連番を AE から外す）
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s03.jsx
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/render_s03.jsx   # docs/pv/previz/frames_s03/s03.mp4
```

通しの確認用の動画は、PV フレーム 1〜337 の連番と `s03.mp4`、128 BPM のクリック音（`artifacts/pv_capture/click_128bpm_5bars.wav`）を
ffmpeg でつないだもの（`artifacts/pv_capture/out/PV_S01-S03_godot_v4.mp4`、絵コンテ用の 1280×720 は `docs/pv/media/PV_S01-S03_test_v4.mp4`）。

S03 は 2 小節（3.75 秒）にしたので、PV 全体を 75 秒に保つため S20（カスタマイズ）を 1 小節に縮めた（絵コンテに反映済み）。

## S01〜S03 v3（新しい流れ。絵コンテ `docs/pv/storyboard_s01_s03_v2/s01_s03_storyboard_v3.png`）

できあがり：`docs/pv/previz/v3/PV_S01-S03_v3.mp4`（19.7 秒・1920×1080・60 fps・音つき）。確認用の一覧は `docs/pv/previz/check/s01_s03_v3_contact.jpg`。

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_v3_bootstrap.gd -- quality=ultra sub=8 tag=v3_sub8
python tools/pv/merge_subframes.py artifacts/pv_capture/v3_sub8 artifacts/pv_capture/v3_frames   # 各フレームの最後の 4 回を重ねる（動きのブレ・シャッター 180°）
copy artifacts/pv_capture/v3_sub8/{cues,report}.json artifacts/pv_capture/v3_frames/
（AE を立ち上げ直してから）
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s03_c.jsx          # s03_c_bg.json：背景は v3_frames の PV 957〜、保存は AIQUIZ_PV_S01_S03_v3.aep
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s01_s03_v3.jsx      # 01〜09 の撮影とロゴをつなぐ（コンポ PV_S01_S03_v3）
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/render_s01_s03_v3.jsx     # 映像だけ（同じ起動で 2 回目の書き出しはしない）
python tools/pv/mix_audio.py artifacts/pv_capture/v3_frames docs/pv/previz/v3/PV_S01-S03_v3_audio.wav 1180
ffmpeg -i docs/pv/previz/v3/PV_S01-S03_v3_video.mp4 -i docs/pv/previz/v3/PV_S01-S03_v3_audio.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k docs/pv/previz/v3/PV_S01-S03_v3.mp4
```

撮影（`tests/pv_capture/pv_v3_runtime.gd`）は本物の GameWorld を 1 回通しで動かす。外から決めるのは、問題・キー入力・カメラ・時間の速さ・演技の上乗せだけ。

| PV フレーム | カット | 中身 |
|---|---|---|
| 1〜113 | 01 | カウントダウンの状態のまま止める（ベルトは動かず、2 人は立ちポーズ）。問題の壁は空の上に隠す |
| 114〜225 | 02 | 壁がゲームのプレビューの壁と同じ形（2 乗の加速・0.55 秒）で落ち、142 で着地：潰れて戻る、白い土ぼこりの衝撃（BinbunVFX vfx_impact_01 を灰色に）×3、揺れ、`wall_land`、観客のどよめき。2 人はのけぞる（UAL Hit_Chest） |
| 226〜338 | 03 | 2 拍で背中越しのアップへ寄る（扉が 2 人の頭の間に見える高さ）。2 人とも頭を青い扉の中心へ実際に向ける |
| 339〜450 | 04 | 前から 2 人の顔。赤 → 青 → 赤と 1 拍ずつ、頭を扉の中心へ向けて見比べる（頭は扉の向き、体は 20% だけ） |
| 451〜506 | 05 | 前から。P2 は 0.1 秒目から 0.42 秒かけて右腕を上げ（少し行き過ぎて戻る）、赤い扉を指さし、胸を赤い扉へ向ける。P1 は首を振って迷う（UAL2 Idle_No_Loop） |
| 507〜619 | 06 | PLAYING へ。P2 はヒップホップ2 をその場で見せびらかしてから（539 で動き出す）、踊りながら斜めに赤い扉へ。P1 は腕を組んで（UAL2 Idle_FoldArms_Loop）P2 を目で追う |
| 620〜661 | 07 | 626 で P2 がゴツン（ハート 1 なので脱落）、吹き飛ぶ。キツネ帽子は頭に付いたまま飛ぶ（下の「帽子」） |
| 662〜773 | 07b | 煽る：P1 が体ごと P2 へ向き直り、0.38 秒かけて腕を上げて指さし（662〜）、シリーダンスで煽る（704〜、0.3 秒でつなぐ）。横から 2 人を一緒に撮る。746（激突のちょうど 2 秒後）で P2 が爆散：このPVだけ破片を外へ 18〜30 m/s で飛ばし、爆発（BinbunVFX vfx_explosion_01 の火花・輪・土ぼこり）・強い揺れ・`barrier_explosion` を重ねる |
| 774〜839 | 08 | P1 が青い扉の正面へ寄って走る（低い追従） |
| 840〜956 | 09 | 壁の向こう側から。P1 がカンナムスタイルを踊りながら 846 で突き破る（0.6 秒だけ 0.5 倍のスロー） |
| 957〜1180 | ロゴ | 胸の高さへ上がって引く（S03 と同じ）。この上に AE でロゴ案 C |

- このPVだけベルトは 1.0 m/s（ゲームの典型は 2.9）。壁を 12.6 m 先に落としたまま、煽るパートの 1 小節を入れるため。
- 壁の止まる位置（スタートの 12.6 m 先）は P1 の突破（846）から、P2 の動き出し（539）は P2 のゴツン（626）から逆算する（`_plan`）。
- 踊りの最初のフレームは骨格がまだ初期姿勢（T ポーズ）なので、0 秒の位置を当てて写し直す（`_fix_emote_start`）。
- 演技の上乗せ（`StagingPuppet` の UAL クリップ）は、切り替わる前のフレームの終わりで姿を覚えて 0.18 秒でつなぐ。
- 突破の 3 フレーム前に乱数を入れ直す（手前の煙・人形で、ドアの破片の散り方が変わらないように）。
- 撮影だけの上乗せ：影のアトラス 16384、物理を 60×sub Hz で進める。
- 帽子（2026-10-17 に直して撮り直し）：壁に激突したプレイヤーは、隠れる表示用の体とは別のラグドールになって飛ぶ。
  前は帽子が表示用の体の付け根に残って隠れていたので、激突した瞬間に帽子が消えていた（ゲームでも同じ）。
  いまはゲーム本体（`scripts/world/player_controller.gd` の `_attach_ragdoll_hat`）がラグドールの頭へ帽子を付け替え、
  爆散では帽子も破片になる。ラグドールを片付けるとき（`_teardown_ragdoll`）に元の付け根へ戻す。
- 効果音は撮影中に鳴ったキュー（`cues.json`：壁の着地・P2 のゴツンと不正解の音・爆散と爆発音・正解の音）を、ゲームと同じファイル・音量で同じ時刻に置く。観客はスタートまでざわめき、そこから声援。曲はまだ入れていない。

## S03 のロゴ（案 C：今の 2D の登場演出を強化）

絵コンテ v3（`docs/pv/storyboard_s01_s03_v2/s01_s03_storyboard_v3.png` の C1〜C6）を After Effects で作ったもの。
`docs/pv/previz/ae/build_s03_c.jsx` が新しいプロジェクト `AIQUIZ_PV_S03_C.aep` にコンポ `PV_S03_C`（2 小節・3.75 秒・60 fps）を組む。
文字の形・ベルトの色・影はメニューのタイトルロゴと同じ `tools/title_logo_ae/layout.json` から作る（1 論理 px＝4.8 px、文字は y 70〜339、ベルトは y 313〜365）。
背景は撮影の続き（PV フレーム 338〜562）を、ぼかさず暗くもせずに使う。

| 拍 | 中身 |
|---|---|
| 1 | 細い黄色い線が左から右へ走る（白く光る先端） |
| 2 | 線が開いてベルトになる（行き過ぎて戻る）。目盛りが流れ始める |
| 2.6〜4 | 文字はメニューのタイトルの登場と同じ動き（`tools/title_logo_ae/build_title_logo.jsx` の落下・着地・ベルト運びを 2 倍速）。Z → I → U → Q → I → A の順に、傾いてベルトの左端（A の位置）へ落ち、つぶれて 2 回跳ね、ベルトが右のそれぞれの位置へ運んでカチッと止める。着地の土ぼこりつき |
| 5（2 小節目の頭） | 最後の A が着地してベルトが止まる（全部の文字がそろう）：白い閃光、横の光の筋、斜め線、ズームパンチ（107%）、ベルトが跳ねる |
| 5.6〜6.2 | メニューと同じく、A と Q をつなぐ斜めの棒が Q から A の足元へ伸びる |
| 6〜7 | 止めて見せる：4% だけ寄る、きらめき、右の観客席のフラッシュ |
| 8 | ベルトがロゴごと左へ流れ出し、右から黄色い斜めの帯が画面を覆う（最後のフレームは全面が黄色。次の S04 はこの帯が抜けるところから始める） |

```
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s03_c.jsx
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/render_s03_c.jsx   # docs/pv/previz/frames_s03/s03_c.mp4
```

確認用の一覧は `docs/pv/previz/check/s03_c_contact.jpg`。この PC の AE 2026 は、1 回書き出すと同じ起動のうちの次の書き出しが
エラーか空の画像になるので、書き出し直すときは AE を再起動し、立ち上がりきってから実行する（起動中に送ると「スクリプト機能のプラグインが
インストールされていません」のダイアログが出る）。

## S04〜S07（設定 → ヘリのお迎え → 問題の壁が空から落ちる → 5教科×6学年）

できあがり：`docs/pv/previz/v4/PV_S01-S07.mp4`（S01〜S07 の通し 34.7 秒・1920×1080・60 fps・音つき。曲はまだ）。
S04 と S05 は 2 小節ずつ（最初は 1 小節ずつだったが、場面の切り替えが速すぎて頭に入らなかったので伸ばした。PV 全体は 77.8 秒・42 小節）。
S04 は v3 の 1180 フレームのすぐ後ろ（PV フレーム 1181〜）から始める（128 BPM の 42 拍目の頭より 1.25 フレーム早い）。

新しいテイクは共通の土台 `tests/pv_capture/pv_take_base.gd`（引数・画質・サブフレームの撮影・設定を汚さない・効果音のキュー・
report）の上に、テイクごとの台本 `pv_<テイク>_runtime.gd` を書く。起動は `pv_take_bootstrap.gd -- take=<テイク>`。
カットの間を詰める（ゲームだけ進めて PV の時刻を止める）ための `begin_skip()` / `end_skip()` もある。v3 はまだ自分の
`pv_v3_runtime.gd` のまま。

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s04_s05 quality=ultra sub=8 tag=s04_s05_sub8
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s06_s07 quality=ultra sub=8 tag=s06_s07_sub8
python tools/pv/merge_subframes.py artifacts/pv_capture/s04_s05_sub8 artifacts/pv_capture/s04_s05_frames
python tools/pv/merge_subframes.py artifacts/pv_capture/s06_s07_sub8 artifacts/pv_capture/s06_s07_frames
copy artifacts/pv_capture/s04_s05_sub8/{cues,report}.json artifacts/pv_capture/s04_s05_frames/   （s06_s07 も同じ）
（AE を立ち上げ直してから。v3 の 2 本は上の「S01〜S03 v3」と同じ）
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s03_c.jsx
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s01_s03_v3.jsx
node assets/aiquiz_menu_stage/source/ae/ae_run.mjs docs/pv/previz/ae/build_s04_s07.jsx         # テロップ・教科名・シャッターの光、通しのコンポ PV_S01_S07（AIQUIZ_PV_S01_S07.aep）
"G:\adobe\Adobe After Effects 2026\Support Files\aerender.exe" -project C:\AIQUIZ\AIQUIZ-Godot\docs\pv\previz\ae\AIQUIZ_PV_S01_S07.aep -comp PV_S01_S07 -RStemplate 最良設定 -OMtemplate "H.264 - レンダリング設定を一致 - 40 Mbps" -output C:\AIQUIZ\AIQUIZ-Godot\docs\pv\previz\v4\PV_S01-S07_video.mp4
python tools/pv/mix_s01_s07.py docs/pv/previz/v4/PV_S01-S07_audio.wav
ffmpeg -i docs/pv/previz/v4/PV_S01-S07_video.mp4 -i docs/pv/previz/v4/PV_S01-S07_audio.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k docs/pv/previz/v4/PV_S01-S07.mp4
```

書き出しは AE のコマンドラインの `aerender`（日本語のテンプレート名をそのまま渡すので PowerShell から）を使う。AE の画面を使わないので、
「1 回書き出すと同じ起動の次の書き出しが失敗する」問題も、立ち上げ直しも要らない（2080 フレームで約 2 分）。AE の中から書き出す
`render_s01_s07.jsx` も残してある（その場合は AE を立ち上げ直してから）。

### S04〜S05（`pv_s04_s05_runtime.gd`：本物のメインメニュー、1 人）

| テイクのフレーム | カット | 中身 |
|---|---|---|
| 1〜225 | S04 | 設定パネル（UI あり）。1 拍ごとに矢印を押す（教科 国語 → 社会、学年 3 → 4 年、教科 → 英語 → 算数。押すのはボタンの `pressed` なのでクリック音も鳴る）。156（5.5 拍目）で「ゲーム開始」：ゲームと同じ順に、ボタンを止めて決定音、「LETS'GO」のシャッター、UI が下がる、1 フレームおいてヘリの出発（189）。そのあとはメニューのカメラ（ヘリの演出が空へ向ける）のまま、ヘリが近づいてくるところまで等速 |
| 226〜366 | S05a | 横から寄った PV のカメラ。ヘリが降りてきて縄ばしごを下ろし、揺れが収まるとキャラが走って飛びつく。切らずに見せ、367（S05 の 6 拍目の頭）でつかまる |
| 367〜450 | S05b | つかまったヘリの下、桟橋の床すれすれから見上げる。エンジンをためる 0.8 秒を 1.5 拍に縮め、409 で打ち上がり、等速で飛び去るのを見送る |

- メニューの起動演出（タイトルロゴ・初回の案内・保守船の入港）は飛ばす。見た目は撮影用（P1 プロペラ帽子）で、`PlayerSkinStore` は撮影中だけ別のファイル・書き込み停止。
- 設定のベルトはゲームのまま（0.28 秒）。「設定 / API状態」とお知らせは隠す。
- メニューの「ゲーム開始」から先は実時間 12 秒で打ち切る待ちがあるので、`_on_start_pressed` を使わず同じ手順を自分で呼ぶ（場面は切り替えない）。
- 時間の速さは撮影中に決める（`_plan_speed`）。縄ばしごの揺れが収まってキャラが走り出す時刻は物理で決まり、早回しの速さでも
  変わる（同じ台本でも 2.3〜2.6 秒とぶれた）ので、決め打ちの値では合わない。走り出すまでは 1.45 倍で回し、走り出したら
  「走る時間（プレイヤーが決めた duration の残り）＋飛びつく 0.62 秒」が 367 で終わる速さに、つかまったら「エンジンをためる 0.8 秒」が
  409 で終わる速さに切り替える。ここから先は物理によらないので、report の `grab_frame` / `launch_frame` は計画と 1 フレーム以内でそろう。
  `measure` を付けると等速で回して出来事の時刻を report に書く。
- 見上げのカットだけ、ローターの風で舞う破片（`downwash`）を隠す（床すれすれのカメラではレンズの前を横切る大きな白い四角になる）。
- メニューでは UI 以外の効果音が鳴らないので、ヘリの音（ローター・つかまる音・ジェット点火）は `mix_s01_s07.py` が置く。

### S06〜S07（`pv_s06_s07_runtime.gd`：本物の GameWorld、1 人）

| テイクのフレーム | カット | 中身 |
|---|---|---|
| 1〜225 | S06 | 問題の準備中（PRELOADING）。ゲームのとおり、問題が 1 問届くたびにその壁が空から落ちる（奥から手前へ。ONLINE の出題なので 1 枚ずつ）。届ける更新だけを決め、3〜10 問目の壁を 1 拍ごとの頭（1, 29, 57 … 198）に着地させる（1・2 問目はカットの前）。HUD の「AIが問題をつくっています n/10」はゲームのまま（右上へ寄せて 0.7 倍）。カメラは着地する壁の 24 m 手前を 1 拍に 30 m ずつ下がり、最後は P1 の頭の上を越えて背中の高さで止まる |
| 226〜450 | S07 | いちばん手前の壁を正面から（選手は映さない）。1.5 拍ごとに問題を替える（算数 4 年・国語 6 年・理科 3 年・社会 6 年・英語 3 年。`offline_bank.json` の問題と一致するか確かめる）。英語だけ 2 拍 |

- 問題集の補充を止めるため GameWorld は `_replay_mode` のまま（ゲームの状態を進めない）。画面の揺れはこちらがゲームと同じ速さで減らす。
- 届ける更新 = 着地させたいフレームの最初の更新 − 落とし始めるまでの 4 回 − 落下 0.28 秒ぶんの更新（`_plan_arrivals`）。
- 全部の壁が着地してもカウントダウンの壁は落とさない（`_barrier_spawned_for_session`）。S07 に入るとき、着地の火花を止める。
- 絵コンテの「ゲームでは左右から飛んできて合体する」は古い。今のゲームは準備中の壁を空から 1 枚ずつ落とすので、S06 はゲームの演出のまま。

### 編集（`build_s04_s07.jsx`）

- S03 の黄色い帯は、そのまま左へ抜けて S04 を見せる（0.32 秒）。S04 は「ゲーム開始」まで設定パネルを中心に 1.0 → 1.12 倍へ寄り、
  そのまま止める。S04 のテロップは UI が下がりきる 184（6.5 拍目）で消す。S07 は 1.0 → 1.03 倍。
- テロップは `pv_telop.jsxinc`（絵コンテの「テロップの決まり」：白い文字に紺のふち、要のことばは黄色、0.2 秒で押し上げて出し 0.15 秒で消す。
  書体は絵コンテの Dela Gothic One がこの PC に無いので Noto Sans JP Black）。S04 は右下（左に UI）、S06 は左下（2 小節目から補足）、
  S07 は上の中央（扉が画面の下半分）。
- S07 は左上に教科名と学年（例「算数 4年」）、切り替えごとに白い光（シャッター）。音は `helicopter/belt_click` ＋ `ui_click` の「カチッ」。
- ExtendScript は `a ? b : c ? d : e` を `(a ? b : c) ? d : e` と読むので、入れ子の三項演算子には括弧を付ける。

## 参考：Blender のプリビズ

`docs/pv/previz/` の `AIQUIZ_PV_S01-S03.blend` は、最初にカメラの距離・画角とタイミングを決めるのに使った Blender のプリビズ。
撮影はすべて Godot で行うので、今後は使わない。
