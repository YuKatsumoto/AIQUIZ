# AIQUIZ HARBOR LAUNCH 画像生成の記録（Codex CLI）

画像はすべて Codex CLI（ChatGPT Pro、組み込みの `image_gen`）で作った。Higgsfield は使っていない（クレジット 0）。
1 枚ごとに `tools/codex_image.sh` を実行する（Codex は一時フォルダで `--ephemeral`、リポジトリには触れない）。
プロンプトの全文は `prompts_src/`、各画像の採否・sha256・画素寸法は `generation_record.json`。

```bash
bash assets/aiquiz_menu_stage/source/tools/codex_image.sh out.png prompts_src/r3_v1.txt concepts/guide_r3_menu_camera.png concepts/r2_master_round_deck.png
```

## 流れ

| 回 | 目的 | 参照（添付の順） | 結果 |
| --- | --- | --- | --- |
| 1 | 方向を 4 案（同時） | `ref_style_board.png` | A「港の発進デッキ」をユーザーが選択。B の着陸灯と吹き流し、C の電球と旗を A に足す |
| 2 | 本物の街を背にした原本 | Blender の下絵 `guide_r2_round_deck.png` → A | `r2_master_round_deck.png`：意匠の原本 |
| 3 | メニューのデモ（コンベア）を残した配置 3 案 | Blender の下絵 `guide_r3_menu_camera.png`（ゲームのメニューのカメラ）→ 原本 | V1「走路の右に発進デッキ」を採用、V3 のガラスの手すりと縁の灯を足す。V2「門」はヘリの経路と重なるので不採用 |
| 4 | Blender の途中のレンダーへの細部の描き足し | 1 回目の組み立てのレンダー → 原本 | スピーカー・舗装・帯の継ぎ目・ヤシ・レンズの光り方を採用 |
| 5 | ビル群の手前（岸辺の街）の作り直し（2 案、同時） | Blender の下絵 `guide_r5_waterfront_A/B.png`（本物の街を海の上から）→ 原本 | A のフェリーターミナル・時計塔・灯台・マリーナ・パステルの家と、B の観覧車・アーチ窓の市場・階段の護岸・日よけ・旗を合わせて採用 |
| 6 | ゲームの実画面（望遠）への仕上げの描き足し（2 枚、同時） | Godot の実画面 `guide_r6_ingame_center/left.png` → 5 回目の案 | 濃いパステルと隣の色の差、屋上テラス（鉢植えのヤシ・植栽・パラソル）、カフェのパラソル、花のプランター、糸杉、桟橋の杭の白い頭、石積みの目地、鎧戸と花箱を採用 |
| 7 | 街並みの建物の型を増やす（見本帳と実画面の描き替え、2 枚、同時） | Godot の実画面 `guide_r7_ingame_center.png` → 6 回目の描き足し | 見本帳 `r7_building_catalogue.png` の 12 の型を形と外壁の画像で作り分け、`r7_street_variety.png` の「隣と型・高さ・窓の割り付けを変える」並べ方を採用 |

## 効いた書き方

- **下絵を 1 枚目、デザインを 2 枚目**：「Image 1 is an exact camera-and-layout render from the game engine … keep its camera, lens, horizon and perspective EXACTLY … keep the entire city skyline exactly as it is」。
  街はゲームの本物（`AQS_BG_City`）を Blender で下絵に写しておくと、生成でもビル一棟ずつの形と位置がそのまま残る。
- **ゲームの約束を文で渡す**：「Nothing may be placed ON the runway surface, and nothing may be above the runway lower than 8 m (walls travel along it and helicopters fly over it)」。
  ヘリの回収と壁の通り道を守った案だけが出てくる（V2 の門はそれでも経路に掛かったので不採用）。
- **UI の場所を空ける**：「The LEFT 40% of the frame must stay calm … the menu buttons will be overlaid there later」。
- **文字はロゴだけ**：「The only readable text in the whole image is the logo word AIQUIZ, spelled exactly A-I-Q-U-I-Z」。
  ゲームの看板の文字は生成画像ではなく `icon.jpg` のロゴから作る（`textures/make_textures.py`）。
- **描き足し（paint-over）**：「Keep image 1's camera, perspective and every object's position, size and silhouette EXACTLY … Improve only surface detail」。
  形を変えずに細部だけを提案させると、そのまま Blender の修正の一覧になる。

## 参考にした Web の資料（7 回目、2026-09-29）

建物の型を決めるために、アパート・マンションの外観を紹介する次のページを読み、見た目の特徴だけを型の一覧にまとめてプロンプトとビルダーに使った（文章や写真は使っていない）。

- マンションの外壁材と色・質感：[SUUMO「マンション外観は資産価値に影響を与える？」](https://suumo.jp/article/oyakudachi/oyaku/ms_shinchiku/ms_knowhow/ms_gaikan/) → タイル・サイディング・打ち放し、中立色と差し色
- タワーマンションの外観の手法：[アットホーム「タワーマンション・特徴的なデザイン」](https://www.athome.co.jp/mansion/shinchiku/tag/tower/column/column43/) → 濃淡の縦横のパターン、手すりのリズム、頂部
- バルコニー手すりの 3 型（腰壁・ガラス・格子）：[積水化学 クレガーレ「バルコニーの手すりの違い」](https://www.eslontimes.com/cregare/enjoy/0163.html)、[LIXIL モダンパネル](https://www.lixil.co.jp/lineup/veranda_balcony/modern_panel/) → 横ラインのマンションの手すりの種類
- デザイナーズアパートの外観：[RadIAnce「デザイナーズアパートの外観アイデア集」](https://radiance.ria-partners.co.jp/archives/2225) → 差し色・素材の切り替え
- 外廊下・外階段：[step-museum「外階段とは」](https://www.step-museum.com/knowledge/outside-stairs.html)、[文化シヤッター 屋外鉄骨階段廊下ユニット](https://bunka-s-pro.jp/product/danjuro-2-3kai) → アパートの外廊下と鉄骨の外階段
- バルコニーの型（片持ち・凹み・積み重ね・ジュリエット）：[Wikipedia: Balcony](https://en.wikipedia.org/wiki/Balcony)、出窓：[Wikipedia: Bay window](https://en.wikipedia.org/wiki/Bay_window)
- 散らしたバルコニー・色の箱・段々：[Homedit「Stylish Balconies Become Integral Parts Of Their Building's Facade」](https://www.homedit.com/stylish-balconies-facade/)
- ロッジア・ウィンターガーデン：[ArchDaily「Transforming Balconies and Loggias into Livable Spaces」](https://www.archdaily.com/1020845/transforming-balconies-and-loggias-into-livable-spaces)
- 運河の家の破風（階段・首・鐘）：[Amsterdam for visitors「Canal House Gables」](https://amsterdamforvisitors.com/canal-house-gables/)、[Grachtenmuseum「Architecture」](https://grachten.museum/en/architecture-in-the-canal-district/)
- 地中海の街の外壁（パステル・鎧戸・鉄のバルコニー）：[Cerrad「Mediterranean-Style Façade」](https://cerrad.com/en/news-2/mediterranean-style-facade/)

## 気づいたこと

- Codex は生成画像の保存先を返さないことがある。`~/.codex/generated_images/<session id>/` に残るので、`codex.log` の
  `session id` で拾う（同時に複数走らせると「最新の画像」では取り違える）。
- `-i` は複数の値を取るので、プロンプトを位置引数で渡すと画像と取り違える。プロンプトは標準入力で渡す。
- 同じプロンプトを同時に 2 本走らせると、同じ画像が 2 枚返ることがあった（r2 の a と b）。案を増やしたいときはプロンプトを変える。
- 1 枚 約 1.5〜3 分。参照画像が 2 枚だと長くなる。
- 出力の相対パスは、呼び出した場所から解決する（ラッパーは一時フォルダへ移ってから保存するので、先に絶対パスにしている。2026-09-29 に直した）。
- 遠い帯（ビル群の手前）は、実際のカメラの画面では 60px ほどの高さしかなく描き足しに向かない。本物の街を写した海の上の近景の下絵で意匠を決め、
  組み立てた後はメニューのカメラの位置からの望遠（ゲームの実画面）に描き足してもらうと、形を保ったまま仕上げの一覧が得られる。
