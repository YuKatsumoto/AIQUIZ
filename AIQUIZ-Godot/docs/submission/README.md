# ゲームクリエイター甲子園2026 審査用フォルダの下書き

作品登録フォームの「（審査用のみ）作品素材フォルダURL」に入れる Google ドライブのフォルダの中身を、ここで下書きする。
フォルダは審査にだけ使われ、みんなのゲームパレードには載らない。要項は <https://game.creators-guild.com/gck2026-terms/>。
フォームの文章の欄（バージョン情報・作品の短い説明・詳細な作品紹介・スタッフクレジット・自チームで制作していない部分）の下書きは `form_entry.md`（字数は `python docs/submission/form_count.py`）。

## できあがりのフォルダと、このディレクトリの対応

| ドライブに置くもの | 下書き | 状態 |
|---|---|---|
| `00_はじめにお読みください.pdf` | `00_hajimeni.md` | PDF の下書き版あり（A4 1 枚） |
| `01_PV_85秒.mp4` | `docs/pv/previz/v6/PV_full.mp4` を Drive で再生できる重さに書き出し直す | 未 |
| `02_アピール資料.pdf` | **`02_アピール資料.pptx`**（PowerPoint。2026-11-01 に `pdf/02_appeal.html` から移した。原稿は `02_appeal_script.md`） | 16:9・19 ページ。p4〜p8 が問題生成ライン（以前のライン・その 5 つの問題・改善策・現在のライン・費用の効果）。p3 と p19 に撮影待ちの枠 |
| `03_TESTOPIA_v1.0.0_Windows.zip` | ゲームの書き出し ＋ `zip/README.txt`・`zip/CREDITS.txt`・`zip/LICENSES/` | 同梱する文書は下書き済み。書き出し前の整備が要る（下） |
| `04_プレイ動画A〜E.mp4` | 撮るものは `02_appeal_script.md` と計画どおり | 未 |
| `05_外部素材とAIの使用箇所.pdf` | `05_credits_ai.md`（「3. 提出前に確かめること」は PDF に入れない） | PDF の下書き版あり（A4 横・4 ページ） |
| `スクリーンショット/` | `artifacts/pv_capture/*_frames/` から選ぶ（PV の S06 と「AI が書く」演出は台本で撮ったものなので使わない） | 未 |

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

## 書き出し前の整備（03）

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
