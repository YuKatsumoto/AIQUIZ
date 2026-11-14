# ゲームクリエイター甲子園2026 審査用フォルダの下書き

作品登録フォームの「（審査用のみ）作品素材フォルダURL」に入れる Google ドライブのフォルダの中身を、ここで下書きする。
フォルダは審査にだけ使われ、みんなのゲームパレードには載らない。要項は <https://game.creators-guild.com/gck2026-terms/>。
フォームの文章の欄（バージョン情報・作品の短い説明・詳細な作品紹介・スタッフクレジット・自チームで制作していない部分）の下書きは `form_entry.md`（字数は `python docs/submission/form_count.py`）。

## できあがりのフォルダと、このディレクトリの対応

| ドライブに置くもの | 下書き | 状態 |
|---|---|---|
| `00_はじめにお読みください.pdf` | `00_hajimeni.md` | PDF の下書き版あり（A4 1 枚） |
| `02_アピール資料.pdf` | **`02_アピール資料.pptx`**（PowerPoint。2026-11-01 に `pdf/02_appeal.html` から移した。原稿は `02_appeal_script.md`） | 16:9・19 ページ。p4〜p8 が問題生成ライン（以前のライン・その 5 つの問題・改善策・現在のライン・費用の効果）。p3 と p19 に撮影待ちの枠 |
| `04_プレイ動画A〜E.mp4` | A・B は人が遊んだ録画（ゲームバー）。C〜E は `tests/submission_video/` の台本で撮る（下の「04 プレイ動画」） | 2026-11-13：A〜F あり（F は開発中のサドンデス） |
| `スクリーンショット/` | プレイ動画 C〜E の素材（1920×1080 の AVI）から選んだコマ（下の「04 プレイ動画」） | 2026-11-12：あり |

ドライブに上げるファイルは `審査用フォルダ/` に集める（`pdf/out/` からのコピー。PDF を書き出し直したら、コピーし直す）。

2026-11-10：次の 3 つはフォルダに入れないことにした（番号は詰めず、02・04 のまま）。

- `01_PV_85秒.mp4`（PV はフォームの別の欄で出す）
- `03_TESTOPIA_v1.0.0_Windows.zip`（ゲーム本体。同梱する `zip/README.txt`・`zip/CREDITS.txt`・`zip/LICENSES/` の下書きと、下の「書き出し前の整備」は、ゲーム本体を出すときにそのまま使う）
- `05_外部素材とAIの使用箇所.pdf`（`05_credits_ai.md` は、フォームの「自チームで制作していない部分」の欄の元として残す）

`zip/LICENSES/Godot_LICENSE.txt`・`Godot_THIRDPARTY.txt` は、手元の Godot 4.7.2 から `Engine.get_license_text()`・`get_copyright_info()`・`get_license_info()` で書き出したもの。
`OFL-1.1.txt` はその中の OFL 1.1 の全文に、Noto のフォントの中にある著作権表示を付けたもの。

## 02 アピール資料（PowerPoint）

- `02_アピール資料.pptx` を PowerPoint で直す。箱・写真・矢印はそのまま動かせる。写真はトリミングし直せる（図の形式 → トリミング）。
- 提出用の PDF は PowerPoint の「ファイル → エクスポート → PDF/XPS の作成」で `pdf/out/02_アピール資料.pdf` に書き出す。
- 字は Windows に入れた Noto Sans JP（`pdf/fonts/` の 6 本。太さごとに Medium・SemiBold・ExtraBold・Black の名前）。
  ほかの PC で開くときは、そのフォントを入れるか、PowerPoint の「オプション → 保存 → ファイルにフォントを埋め込む」で保存する。
- 下書きの印（下の「下書き 2026-11-01」と、p18 の「下書き：実際の作り方に合わせて直す」）は入れていない。【】の印は残っている。
  `build.py --final` の【】の検査は HTML と Markdown だけなので、PowerPoint では Ctrl+F で「【」を探す。
- HTML から移した道具は `pdf/to_pptx/`（もう一度使うと PowerPoint で直したところが消える）。
- 縦書きの帯のラベルは 1 字ずつ改行して積んである（PowerPoint の縦書きだと Noto Sans JP のかな・カナが横に倒れるため）。

## 02 アピール資料の新デザイン版（2026-11-10）

- `02_アピール資料_新デザイン.pptx`（8 ページ。元の 1〜7 ページと 14 ページ「作る → 撮って確かめる → 直す」。
  元の 8〜13・15・16 ページは 2026-11-10 に外した）。残したページの文・写真・図のつながりは 2026-11-03 の `02_アピール資料.pptx` と同じで、見た目だけを作り直した版。
  元の `02_アピール資料.pptx` はそのまま残してある。**提出に使うのは新デザイン版**（2026-11-10 に決定）。
  `審査用フォルダ/` には `02_アピール資料.pdf` の名前で入れる。
- PDF は `pdf/out/02_アピール資料_新デザイン.pdf`（PowerPoint から書き出したもの）。
- 見た目：紺の地・白い字、強調はコンベアの黄色、番号の札は答えのドアの形、手順のページは写真の下にコンベア。
- 字は、見出しが Noto Sans JP ExtraBold・SemiBold、本文が BIZ UDPゴシック。
  PowerPoint の PDF 書き出しで細く出る Regular・Medium・Bold・Black を使っていないので、PDF でも太さがそのまま出る（4・7 ページで確認）。
- 作り直す道具は `pdf/redesign/build_deck.py`（`python -I docs/submission/pdf/redesign/build_deck.py <出力.pptx>`。
  `to_pptx/base.pptx` と `pdf/img/`・`pdf/logos/` を使う）。**もう一度実行すると、PowerPoint で直したところは消える。**
  書き出したあと `to_pptx/export.ps1` で PowerPoint に保存し直したものを置いている。
- 3 つの守りのページ（p7）の項目は 1 列の表。文を直すと、項目の間の線が行数に合わせて動く。
- 元の版から引き継いだままのところ：p4 に商標の注記が無い。
- AI の使用箇所の表（元の p15）を外し、`05_外部素材とAIの使用箇所.pdf` もフォルダに入れないので、
  AI を使った箇所の明記はフォームの「自チームで制作していない部分」の欄だけになる。

## 04 プレイ動画（2026-11-12）

- A（1人・10問）と B（ローカル2人）は、人が遊んだものを Windows のゲームバーで録画し、1920 幅・60fps に書き出し直したもの。
- C（オンライン対戦）・D（チュートリアル 1P 実践コース）・E（AI が問題をつくるようす）は、`tests/submission_video/` の台本で撮る。
  操作はボット（キー入力を `Input.parse_input_event` で入れる）。人の操作らしく、読む間・行き過ぎ・立ち直し・ジャンプ・
  エモート・押し合い（C）を入れてある。作業フォルダの版（開発版）で動かすので、書き出した版と同じ日のうちに撮る。

```
python -X utf8 tests/submission_video/record_take.py online <素材フォルダ>          # C：中継サーバー + ホスト + ゲスト
python -X utf8 tests/submission_video/record_take.py tutorial_solo <素材フォルダ>   # D
python -X utf8 tests/submission_video/record_take.py solo_ai <素材フォルダ>         # E：本番のプロキシに頼む（AI の使用量を 1 試合ぶん使う）
python -X utf8 tests/submission_video/compose.py online <素材フォルダ> <出力.mp4>   # C：2 画面を並べる
python -X utf8 tests/submission_video/compose.py solo <素材.avi> <出力.mp4>         # D
python -X utf8 tests/submission_video/compose.py screen <素材フォルダ> <出力.mp4> --patch-left 6   # E
```

- C と D は Godot の Movie Maker（`--write-movie`）で撮る。画面の取り込みではないので、ほかの窓が写らず、音も PC から鳴らない。
  大きさは `project.godot` の `window_width_override`（1920×1080）になる（`--resolution` は効かない）。
  1080p の書き出しは実時間より遅い（この PC で 1 フレーム 50 ms 前後）。ゲームは 1 フレーム 1/60 秒で進むので、できる動画は 60fps でなめらか。
  C は 2 つのゲームを同じ刻み（`pace=12.5`。80 ms ごとに 1 フレーム）で進め、台本が残したフレームごとの実時刻で 2 本をそろえる。
- F（サドンデス「つきやぶれ！スカイゲート」）は開発中の機能で、書き出した版には入っていない（`sudden_death_available` はデバッグ版だけ）。
  `record_take.py sudden_death` で撮り、`compose.py solo ... --start 19.5 --end 156.2 --label "開発中の機能…"` で、画面の左下に
  「製品版には入っていません（操作は自動）」の札を出しつづける。2 人の 10 問を始めてすぐ、F9 と同じ入口でスコアタワーを引き分けにし、
  そこからは本物の流れ（動画は引き分けの演出から）。00 の PDF にも開発中と書いてある。
- E だけは実時間で撮る（AI の待ち時間を本当の長さで写すため）。ゲームを 2 台目のモニターに全画面で出し、ffmpeg（ddagrab）で取り込む。
  音はゲームが自分で WAV に残す。撮っている間は 2 台目のモニターを使わない。
- 窓がフォーカスを失うと Godot は押しているキーを離すので、台本は押しているはずのキーを毎フレーム確かめて押し直す。
- 撮影のあいだ、設定とスキンの保存先は撮影用のファイルに替える（プレイヤーの設定には書かない）。C は名前をプロセスの中だけで替える。
- E の音は Godot の Dummy の音声ドライバーで録る。Dummy は実時間より少し遅く回るので（1 秒あたり約 2 ms）、`compose.py` がそのぶん音を引きのばす。
  2 台目のモニターの左端には、となりのモニターの窓のふちが数 px 写り込むので、`--patch-left 6` で右どなりの列で埋める。
- 中継サーバー（`relay-server`）は、撮影のあいだだけ無通信の待ち時間を延ばして起動する（`RELAY_HEARTBEAT_S=120`。ふつうは 6 秒）。
  撮影中のゲームは実時間の約 1/5 の速さで進み、ping の間が空くため。延ばさないと「さいかい します」の表示が写る。
- E の設定画面は、書き出した版と同じにしてある（サドンデスの行はデバッグ版だけ、管理ダッシュボードはエディタだけに出るので隠す）。
- スクリーンショット（15 枚・1920×1080・PNG）は、台本が撮影中に残した画面（`shots=`。圧縮なし）と、E の取り込みのコマから選んだもの。
  C の動画は 1280×720 で描いたもの（画面の中では 1280×720 と 544×306 に置く）。画面写真用に、同じ台本を 1920×1080 でもう一度動かした。

## PDF の組み方（00・05）

```
python docs/submission/pdf/make_fonts.py       # はじめに 1 回だけ。fonts/ に太さごとの Noto Sans JP を作る（fonttools が要る）
python docs/submission/pdf/build.py            # img/ に画像を用意して、out/ に 00・05 と、02 の HTML 版（02_アピール資料_HTML版.pdf）を書き出す
python docs/submission/pdf/build.py --final    # 提出用。PDF に出る部分に【】が残っていたら、一覧を出して止まる
```

- 00・05 は Markdown（最初の `---` から `<!-- pdf:end` まで）を `pdf/doc.css` で組む。02 の HTML 版（PowerPoint に移す前の元）は `pdf/02_appeal.html` と `pdf/deck.css`。
- 書き出しは Microsoft Edge のヘッドレス印刷。
- フォントは、Windows に入っている Noto Sans JP（可変フォント）から `make_fonts.py` が作った、太さ 400〜900 の 6 本（`pdf/fonts/`、読み込みは `pdf/fonts.css`）。
  可変フォントのままだと PDF の文字が図形（Type 3）として入り、Acrobat で書き換えにくい。固定の太さにすると普通のフォントとして入り、字の形は同じ。
  `build.py` は、Type 3 で入った文字があると知らせる。CSS で新しい太さを使うときは、`make_fonts.py` と `fonts.css` にも足す。
  `fonts/` の .ttf（約 35MB）は作り直せるので git には入れない（`fonts/.gitignore`）。
- PDF を Acrobat などで開いたままだと上書きできず、`PermissionError` で止まる。閉じてから書き出す。
- Acrobat で直したところは、次に `build.py` で書き出すと消える。直すのは最後の仕上げだけにして、同じ直しを HTML にも入れておく。
- 画像は PV のコマと `artifacts/` の画面写真から `build.py` の `PV_FRAMES`・`STILLS` で選ぶ。テロップの入るカットは、テロップの無い撮影の連番（`artifacts/pv_capture/*_frames/`）を使う。
- HTML 版の p4 のロゴのうち Cloud Run と Firebase は、`pdf/logos/` に置いた Google の公式素材（出典と使い方の決まりは `pdf/logos/README.md`）。Gemini と Claude はロゴを使わず、名前の札にしている。
- `--shots <フォルダ>` を付けると、ページごとの確認用の画像を撮る。
- 下書きのあいだは、スライドの下に「下書き 2026-11-01」と出る。`--final` で消える。

## 書き出し前の整備（ゲーム本体）

- `build/AIQUIZ.exe` は 8/21 の古い書き出し。`--export-release` で書き出し直す。
- `config/name`（`project.godot`）と `application/product_name`（`export_presets.cfg`）が「AIQUIZ 3D」のまま。ウィンドウのタイトルに出る。
- **タイトルロゴの形のデータ `assets/branding/logo/testopia_logo.json` は、`.gdignore` のあるフォルダにあるので書き出しに入らない。**
  書き出した版では、ベルトコンベアで組み立つロゴが作れず、平らな画像のロゴ（`assets/ui/branding/testopia_logo.png`）になるはず。
- Windows の `exclude_filter` が Android より緩い。使っていない第三者・AI の素材（`TripoModels/`、jeremy のヘリ、Godot AI、Tripo Bridge など）と、`.gdignore` の無い `source/` の .blend が入る。
- サドンデスはデバッグ版でしか出ない（`scripts/core/game_state.gd` の `sudden_death_available`）。
- 効果音の `se_lab/` と `crowd/` は git に無い。書き出す PC にあるか確かめる。

## 提出前に決める・確かめること

- [ ] サドンデスを審査用の版で有効にするか
- [ ] Android 版（約 1.07GB・AI の出題なし）を参考として入れるか
- [ ] ソースコードを入れるか
- [ ] Suno の生成時のプラン（`assets/audio/bgm/LICENSE.md` が TODO のまま）
- [ ] AI を使った箇所の書き方（`05_credits_ai.md` と `02_appeal_script.md` の p18）
- [x] PV のテロップ「壁のスピードも、AIが決める」を直すか（今のしくみでは、AI の予測は速さの下限にしか使っていない）
  （2026-11-05：外すことに決定。`tools/pv/pv_master.py` の `TELOP_SKIP` に `S09_1`）
- [ ] サメとキリン帽の出典、Stereofunk（ロゴの字形）の利用条件
- [ ] 公開リポジトリに入っている Mixamo の FBX と Stereofunk の `.ttf`
- [x] 本番のプロキシで、端末ごとの上限（`DEVICE_TOKEN_KEY`）とサーバー側の Claude のジョブが動いているか
  （2026-11-01：`DEVICE_TOKEN_KEY` は Secret Manager から設定済み、`QUIZ_BANK_REQUIRE_REVIEW=1`。判定 4:00・補充 3:00 のジョブは前回成功）
- [ ] 02 の p6・p7 の数字（共有バンクの問題数・合格率など。2026-11-01 の値）と p8 の費用（1 試合の額・判定 1 問の額・予算。2026-11-02 の値）を、
  提出の直前に管理ソフト（http://localhost:3002/#pipeline と「お金」「プレイヤー」）で見直す
- [ ] PowerPoint で書き出した 02 の PDF は、Black・Regular・Medium・Bold の字が細く出る（Windows の可変フォント版 Noto Sans JP が、いちばん細い形のまま埋め込まれる。
  SemiBold と ExtraBold は固定の太さのフォントで入っていて正しい）。2026-11-01 に書き出した版から同じ
- [ ] 2 台目の PC での動作と fps（`00_hajimeni.md`・`zip/README.txt`）
- [ ] 撮影待ち：同じ設定で 2 回遊んだときの壁の比較（02 の p3）、Android の実機（02 の p19）
- [ ] ゲームの中の看板（スタジアムの「AIQUIZ STADIUM」、スコアタワー）が旧タイトルのまま。資料の写真にも写る
- [ ] チーム名、最終の版と日付
