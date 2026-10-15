# オンライン専用メニュー画面（計画の土台）

オンライン対戦を、メインメニューとは別の専用画面として育てるための土台と計画。
通信の仕組みは `docs/online_versus.md`、リレーは `C:\AIQUIZ\relay-server`。

## いまの形（土台として実装済み）

### 入口と出口

| どこから | どうなる |
|---|---|
| メインメニューのモード選択「オンライン対戦」（チュートリアルの右。エンドレスの真下にそろう） | 専用画面のトップへ。設定画面は通らない |
| 専用画面のトップで「← もどる」/ Esc | メインメニューのモード選択へ |
| 試合の結果画面「オンラインメニューへ」/ R キー | 専用画面のトップへ（オンラインの結果画面には「もう一度」を出さない） |
| 試合中の「やめる」・切断・不戦勝のパネル | 専用画面のトップへ |

設定画面の「2人プレイ」切り替えからは、オンライン対戦を外した（1人 / 2人だけを回す）。

### 画面の流れ

```
メインメニュー（モード選択）
  └ オンライン対戦 ──→ OnlineMenu
        home ─┬─ ランダムマッチ ─┐
              ├─ ともだちと あそぶ ──→ friend（コードを つくる / コードを いれる）─┐
              └─ スキン設定（キャラの横の 3D の看板をクリック）──→ skin（帽子と体の色。けってい でトップへ）
                                 ↓                                             ↓
        マッチング演出（OnlineStagingDirector）：乗り込み → 操縦席 → 離陸 → 上昇 → 検索中（下の帯 search）
          ──(あいてが決まる)──→ 合流 → 並走 → VS カットイン → 読み込み → 中央の線が開く ──→ ゲーム
          やめる・失敗・時間切れ ──(0.35 秒の暗転)──→ home
        ゲーム ──(結果・やめる・切断)──→ home
```
演出の仕様は `docs/online_match_staging/spec.md`（v1.1）。3D の背景が作れないときは、旧来どおり search と versus（下の帯）で始める。

### ファイル

| ファイル | 役目 |
|---|---|
| `ui/online_menu.tscn` | 画面のシーン（ルートの `OnlineMenu` だけ。中身はスクリプトで組み立てる） |
| `scripts/ui/online/online_menu.gd` | わく（背景・ヘッダー・接続表示・ステータス）、ページの行き来、通信、試合の開始 |
| `scripts/ui/online/online_menu_page.gd` | ページの基底クラス `OnlineMenuPage` |
| `scripts/ui/online/online_menu_style.gd` | 色・文字・部品（カード、金属ボタン、入力欄）。デザイン変更はまずここ |
| `scripts/ui/online/pages/online_home_page.gd` | トップ：なまえ＋サイコロ、あそぶ問題（教科・学年・むずかしさ）、ランダムマッチ、ともだちと あそぶ |
| `scripts/ui/online/pages/online_search_page.gd` | 検索中の下の帯（経過時間、20 秒で条件を広げた案内、ともだちコード、やめる） |
| `scripts/ui/online/pages/online_friend_page.gd` | ともだちコード（えらぶ / いれる）。つくったコードは検索中の帯に出す |
| `scripts/ui/online/pages/online_versus_page.gd` | 3D の背景が作れないときの VS カードとカウントダウン |
| `scripts/ui/online/pages/online_skin_page.gd` | スキン設定：帽子と体の色（`SkinEditor`。体の色はオンライン対戦だけで使う）。右に立つ自分のキャラにすぐ反映し、すぐ保存する。入口はトップで自分のキャラの横に立つ「スキン設定」の看板（`scripts/world/online_heliport/online_skin_sign.gd`。3D のレイで当たりを見て、指すと光る） |
| `scripts/world/online_staging/` | マッチング演出：監督 `online_staging_director.gd`、値 `online_staging_timeline.gd`、カメラ・飛び方・キャラ・雲・操縦士ハテナ |
| `scripts/ui/online/cutin/` | VS カットイン `online_cutin.gd` と、キャラを撮る `cutin_actor.gd` |
| `scripts/world/online_heliport/` | 3D の背景（ヘリポート v2・乗り込めるヘリ） |

旧ロビー（`ui/online_lobby.tscn` / `scripts/ui/online_lobby.gd`）は、この画面に置き換えて削除した。

### ページの決まりごと

- ページは見た目と入力だけを持つ。通信・ほかのページ・シーン遷移には直接さわらず、
  `request(&"find")` のように `action_requested` で `OnlineMenu` に頼む。
- `OnlineMenu` は通ってきたページを積み上げる（`go(id)` / `back()` / `go_home(status)`）。
  すでに通ったページへ `go` すると、そこまで戻る。
- ページが持てるもの：`page_title()`（ヘッダーの見出し）、`enter(args)` / `leave()`、
  `handle_back()`（Esc と「← もどる」を自分で処理したら true）、`default_focus()`（キーボード用）。
- 通信のシグナル（あいてが決まった・失敗・不戦勝など）は `OnlineMenu._network_handlers()` に
  まとまっている。結果はページへ `go_home("理由")` や `show_code()` のように伝える。

### ページの足し方

1. `scripts/ui/online/pages/` に `OnlineMenuPage` を継承したスクリプトを作る。部品は `OnlineMenuStyle` から。
2. `OnlineMenu` に id（`const RECORDS := &"records"` など）を足し、`_ready()` で `_add_page(id, ページ.new())`。
3. 入口のボタンをどこかのページに置き、`request(&"open_records")` → `_on_page_action` で `go(RECORDS)`。
4. `tests/net/online_menu_runtime.gd` に行き来のチェックを足す。

## マッチング演出（乗り込み → 飛行 → 合流 → VS カットイン → ステージ）

「マッチング開始」からステージが開くまでの演出は、別の資料にまとめた：
仕様書 `docs/online_match_staging/spec.md`、計画書 `docs/online_match_staging/plan.md`（9 に実施の記録）、絵コンテ `artifacts/storyboard/online_matching_storyboard_v2.png`。
背景はパッド 1 つのヘリポートと乗り込めるヘリ（`assets/vehicles/helicopter_boarding/`）。

- この画面（`OnlineMenu`）が受け持つこと：通信、ページと画面の飾り（`menu`／`band`／`staging`／`none`）、やめるの暗転、
  ゲーム画面の別スレッドの読み込み、カットイン、SWAP（画面を写して `SceneTransition.hold_versus_split`）。
- 監督（`OnlineStagingDirector`）が受け持つこと：状態と時刻表、ヘリ・キャラ・ハテナ・カメラ・海と雲の流し。
  画面へはシグナル（`departure_started`・`cruise_started`・`join_started`・`cutin_started`・`hold_started`・`swap_ready`・`requeue_finished`）で知らせる。
- デバッグ版では F7 で、左上に状態・経過時間・カメラ・読み込みを出す。

## これから決めること・作るもの（候補）

上から順におすすめ。★ は進める前に決めてほしいこと。

| # | やること | 中身 | 必要なもの |
|---|---|---|---|
| 1 | ★ 画面のデザイン方針 | いまは紺のグラデーションに半透明カード（仮）。メインメニューのように 3D の背景（対戦会場・観客席など）にするか、2D のイラストにするか | 方針が決まれば `OnlineMenuStyle` とわくの差し替え |
| 2 | 自分のキャラを表示 | トップの横に、きせかえ済みの自分のキャラ（帽子・色）を立たせる。VS では相手も並べる | 既存のプレビュー部品の流用 |
| 3 | きょうの せんせき | `MatchHistory` の `online: true` の記録から、勝ち・負け・最近のあいての なまえ | ページ 1 枚（起動ごとに消える仕様のままでよいか ★） |
| 4 | あそびかた | はじめての子向けに、オンラインのルール（やめると相手の勝ち、Esc の意味など）を 1 枚で説明 | ページ 1 枚 |
| 5 | もう一度 さがす | 結果画面から直接ランダムマッチへ（いまはトップに戻るだけ） | `return_from_match` に「すぐさがす」引数 |
| 6 | 同じあいてと もう一回 | 試合のあと両者が望めば再戦 | リレーに再戦の取り決め（プロトコル追加・再デプロイ） |
| 7 | いま さがしている人数 | リレーの `/health` が返す `queued` などを、トップに小さく表示 | リレーの公開範囲を決める ★ |
| 8 | お知らせ | `LiveConfigManager` のお知らせをトップに出す | 小 |
| 9 | ランキング | 全国の順位 | サーバー側の保存・不正対策（大きい） |

あわせて、オンラインでまだ止めている機能（表彰式・ゴーストシャーク・サドンデス・
ユニットスロット）の対応も、この画面の「ルール」表示と関わる（`docs/online_versus.md`）。

## 守ること

- 小学生向け：自由チャットは置かない。なまえは `NetNameFilter` とリレーの両方で検査する。
- トップに並べるボタンは少なく。いちばん押してほしいのは「ランダムマッチ」（`featured`）。
- 通信の処理は `OnlineMenu` の一か所にまとめ、ページを増やしても散らさない。

## テスト

    Godot --path . --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_menu_runtime.gd shots=artifacts/net/menu_shots
    Godot --path . --fixed-fps 60 --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_staging_runtime.gd shots=artifacts/online_staging/shots
    python tests/net/run_pair.py    # 試合のあと専用画面へ戻るところまで（returned_to_online_menu）
    python tests/net/run_pair.py --headless --scenario staging    # 演出つき（カットインの名前とポーズ、マッチから開くまでの秒数）
    python tests/net/run_pair.py --headless --quit-at-cutin       # カットイン中に相手が消える → 空のまま探し直す

ほかのコマンド（重さ・動画）は `docs/online_match_staging/plan.md` の 6。

`online_menu_runtime.gd` はリレーなしで動く（閉じたポートをリレーに見立て、失敗時にトップへ戻ることを確かめる）。
