# オンライン対戦（プロトコル v2）

2人対戦のまま、ランダムマッチ・予測・再接続を備えた形にしたもの。リレーは
`C:\AIQUIZ\relay-server`（README にプロトコル表とデプロイ手順）。

## 流れ

1. メインメニューのモード選択で「チュートリアル」の横の「オンライン対戦」→ 専用画面
   `ui/online_menu.tscn`（`OnlineMenu`。ページ構成と今後の計画は `docs/online_menu.md`）。
   設定画面は通らないので、教科・学年・むずかしさはこの画面のトップで選ぶ。
2. なまえを入力するか、横のサイコロ（`DiceButton`）で二つ名（`NetEpithets`: 肩書き×名前
   5000 通り超＋レア二つ名）を振り、「ランダムマッチ」。なまえは `NetNameFilter`（12 文字・
   使える文字・数字 3 こまで・NG ワード）で検査し、リレーの `relay/name_filter.py` でも同じ規則で
   検査する（NG リストの一致は relay のテストで照合）。弾かれたなまえは相手に届かず、
   プリセットのニックネーム（`NetNicknames`）で表示され、本人にも VS 画面で知らせる。
   キーは モード・教科・学年帯（1-2/3-4/5-6）。20 秒待つと同じ学年帯の他教科とも組む。
   「ともだちと あそぶ」は 5 文字コードの非公開待ち合わせ。
3. 先に待っていた方がホスト（問題を作る側）。VS 表示 3 秒のあとホストが `start` を送り、
   両者がゲーム画面へ。ゲストは画面の準備ができたら `ready`、ホストはそろうか 12 秒で自動開始。

## 同期の仕組み（`scripts/core/net_game_state.gd`）

- ホストが判定と状態遷移を持つ。オンライン時だけ 1/60 秒の固定ティックで進め、
  ゲストのコマンドを 1 ティック 1 個ずつ使う（3 個溜めてから開始、空なら動かさない）。
- スナップショットは 30Hz の差分（2 秒ごとに全体）。ジャンプは回数カウンタで送る。
- ゲストの自分（スロット 2）は `NetPredictor` で予測し、ホストの結果と未確認コマンドの
  再生で補正（誤差は 0.1 秒で溶かし、1.5 以上はスナップ）。壁は自分の扉と正解で判定を先取り。
- 相手は `NetInterpBuffer` で 100ms 過去を補間。表示スクロールは「自分の入力がホストで
  処理される時刻」まで先回りさせるので、ゲストが通った扉とホストの判定が一致する。
- スロットは入れ替えない。`local_slot` / `slot_label()` で HUD・入力・見た目を自分視点に。
- 問題はシグネチャで変更を検出して再送。オフラインバンクの問題も送れる。
- のこぎり・サメの噛みつき演出は同期済み。体の押し合いはホストのみ（ゲストは描画上だけ離す）。
- 押し合い: 判定はホストの `local_push`。ゲストの左右キーの押下・解放はティック内の時刻付きで
  コマンドに載せ、ホストがそのティックの直前に `submit_local_push_key` へ渡す。押し合いの状態
  （接触・予備動作・命中・のけぞりの時刻、踏ん張り）はスナップショットで送り、ゲストは時刻だけ
  進めて姿勢を再生する。接触中と押された直後は自分の左右位置も補間の時間軸で描く（0.15 秒で
  切り替え）。粒と線は `push_fx` イベント。相殺の窓はオンラインのみ 0.10 秒（オフライン 0.05 秒）。

## 切断

- どちらかが落ちると両者一時停止（`NetOverlay`）。リレーは 30 秒待ち、戻れば
  ホストが `resync`（問題・勝者・全スナップショット）を送り 3-2-1 で再開。猶予切れは不戦勝。
- ESC はポーズではなく「やめる？」（やめると相手の勝ち）。F8 で RTT などの回線表示。

## まだオンラインで止めているもの

表彰式、ゴーストシャーク、サドンデス、ユニットスロット。

ヘリ登場はオンラインでも出す（2026-10-11、`docs/online_match_staging/plan.md` 9.4）。中央の線が開いたあと、両方の画面がそれぞれの
ヘリ登場を再生し、自分の画面の 2 人が着地してから準備完了にする（ゲストは `ready` を送り、ホストは両方そろうか 12 秒で開始）。

## テスト

    python ../relay-server/tests/test_relay.py                 # リレー単体（18 件、なまえの検査を含む）
    Godot --headless --path . --script res://tests/net/net_names_unit.gd   # なまえと二つ名の全組み合わせ
    Godot --path . --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_menu_runtime.gd  # 専用画面の導線
    python tests/net/run_pair.py --headless                    # 2 プロセス通し（本物のリレー）
    python tests/net/run_pair.py --headless --netsim "lat=60,jit=20,stall_p=0.005,stall_ms=200"
    python tests/net/run_pair.py --headless --kill-at 3        # ゲスト切断→再接続
    python tests/net/run_pair.py --headless --kill-at 4 --kill-role host
    python tests/net/run_pair.py --headless --quit-at 2        # 相手が消えたら不戦勝
    python tests/net/run_pair.py --headless --scenario push    # 押し合い（命中・接触のイベント一致）
    python tests/net/run_pair.py --headless --relay wss://aiquiz-relay-818033448758.asia-northeast1.run.app
    python tests/net/run_pair.py                               # 画面付き。artifacts/net/shots にスクショ
    python artifacts/hp_system/run_network.py                  # HP 同期（本物のリレー）

## マッチング演出との受け渡し（2026-10-11）

マッチング演出（`docs/online_match_staging/spec.md` 12）に合わせて、開始のしかたを次のようにした。リレーは変えていない。

| いつ | 送る側 | 種類 | 中身 |
|---|---|---|---|
| VS カットインが入りきったとき | ホスト | `start` | 今と同じ（教科・学年・むずかしさ・モード・LLM）。前は VS の秒数が過ぎたとき |
| ゲーム画面の準備の描画が終わったとき | ゲスト | `ready` | `{"phase": "loaded"}`（開始の合図ではない） |
| ゲストの `loaded` がそろったとき | ホスト | `evt` | `{"event": "reveal", "at": サーバー時刻 ms}`（今から 250 ms 後）。両方がこの時刻に中央の線を開く |
| 開始の壁の準備ができたとき | ゲスト | `ready` | 今と同じ（`phase` なし、または `"start"`） |

- `NetGameState` は、`ready` の `phase` が `"loaded"` のときは `guest_loaded`、それ以外は今と同じ `guest_ready` にする。
- `GameWorld._sync_online_reveal()`：ゲストは `evt reveal` を、ホストはゲストの `loaded` を 4 秒まで待ち、来なければ自分の準備ができしだい開く。
- 試合の前（合流〜カットイン）に相手がいなくなったら、ランダムマッチは空のまま 1 回だけ探し直す（`OnlineMenu._on_opponent_gone`、D12）。
  相手の通信が止まっているあいだ（`peer_paused`）は、カットインのまま待つ。
