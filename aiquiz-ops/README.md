# aiquiz-ops（AIQUIZ 運用の管理ソフト）

公開後の費用・共有バンク・プレイヤーの様子を、自分の PC で見て、必要なら止めたり直したりするためのソフトです。

- 段階1（見る）: お金・共有バンク・プレイヤー
- 段階2（操作）: 端末・回線のブロック、問題を共有バンクから外す・戻す、夜のジョブを今すぐ実行、操作の記録

## 起動

```
cd C:\AIQUIZ\aiquiz-ops
npm install      # 初回だけ
npm start
```

ブラウザで http://localhost:3002 を開きます。`起動.cmd` をダブルクリックしても同じです。
`起動.cmd` は、もう動いているときはブラウザでお金のタブを開くだけ、止まっているときは起動して準備ができてから開きます
（デスクトップの「AIQUIZ 予算ダッシュボード」ショートカットはこれを最小化で動かします）。

- この PC からだけ開けます（127.0.0.1 で待ち受け、Host が localhost 以外のリクエストは断る）。
- データは gcloud のログイン（Application Default Credentials）で読みます。
  起動できないときは `gcloud auth application-default login` をしてからもう一度。
- `../aiquiz-proxy` のコード（段階の判定・新作の数・夜のジョブの既定値・区分の一覧）を読み込むので、
  aiquiz-proxy で `npm install` 済みである必要があります。

## 画面

| タブ | 見られるもの | 読み直し |
|---|---|---|
| お金 | Gemini の今日・今月と予算、今の段階と新作の数、月末の見込み、30日のグラフ、モデル別。Claude（夜の補充・判定）の今月の額と回収待ちの見込み | 1分ごと |
| 生成ライン | 問題が作られて出題されるまでの流れの図（試合ごとの流れと、夜のジョブで共有バンクを育てる流れ）。各箱に今の数字を載せ、押すと詳しいタブに移る | 1分ごと（共有バンクの数は「更新」） |
| 共有バンク | 教科×学年×難易度の在庫（目標との比較）、判定待ち・判定中、合格率、夜のジョブの前回・次回、最近の Batch | 開いたときと「今すぐ読み直す」 |
| プレイヤー | 今日の試合数・端末数・回線数、1試合あたりの額、上限に近い端末、14日のグラフ、使用額の多い端末と回線、止めた回数（理由ごと）、ブロック中の一覧 | 1分ごと |
| 記録 | 管理ソフトでした操作（新しい順・50件） | 開いたとき |

## 操作（本番を書き換えます）

どの操作も確認の画面を出してから実行し、`ops_log/v1` に「いつ・誰が・何を」を残します。

| 操作 | 場所 | 何が起きるか |
|---|---|---|
| 端末・回線のブロック／解除 | プレイヤー | `device_blocklist/v1/<ID>` に書く。プロキシが1分以内に読み直し、その端末・回線では新作を作らない（503）。ゲームは共有バンクの問題で続く。回線を止めると、同じ回線（学校など）のほかの人も止まる |
| 問題を外す／戻す | 共有バンク →「問題を探す」 | 共有バンクから外し、消した印を残す（差分同期で各端末からも消える）。アーカイブも「不合格」にするので、判定や投票で勝手に戻らない。前の状態を残すので「外した問題を表示」から戻せる |
| 夜のジョブを今すぐ実行 | 共有バンク → 夜のジョブ | Cloud Run ジョブを1回動かす。Claude のクレジットを使うが、月の上限はジョブ側で守られる |

書き換えの API は、この画面からの JSON（`X-Ops-Request` ヘッダー付き）だけを受け付けます。
別のサイトのページから送らせることはできません。

共有バンクのタブは全件（約 5MB）を読むので、10分間は同じ結果を使います。
Firebase の読み出し量（ダウンロード料金）を増やしすぎないためです。

## 数字の出どころ

| 表示 | 読む場所 |
|---|---|
| Gemini の使用額 | RTDB `proxy_usage/v1/daily`・`monthly`（プロキシが実際の利用トークンから計算した額） |
| 予算・端末と回線の上限 | Cloud Run サービス `aiquiz-proxy` の環境変数 |
| 段階 | プロキシの `/round-plan` と同じ計算（`aiquiz-proxy/usage-budget.js`） |
| Claude の使用額 | RTDB `bank_builder/v1/spend`・`quiz_review/v1/spend`（回収済みの Batch の実費） |
| Claude の上限 | Cloud Run ジョブ `quiz-bank-builder`・`quiz-claude-review` の環境変数 |
| 共有バンク・判定 | RTDB `quiz_bank/v1/items`・`quiz_archive/v1/items`・各 `batches` |
| 夜のジョブ | Cloud Run Jobs の実行履歴と Cloud Scheduler |
| プレイヤー | RTDB `proxy_usage/v1/devices`・`ips`・`rounds`・`denials`、`device_blocklist/v1` |
| 操作の記録 | RTDB `ops_log/v1` |

Gemini の額はプロキシの見積もりです。Google の請求額とは少しずれることがあります。
円は 1 ドル 150 円で換算しています（環境変数 `JPY_PER_USD` で変えられます）。

## 設定（環境変数・すべて省略可）

| 名前 | 既定 |
|---|---|
| `OPS_PORT` | 3002 |
| `JPY_PER_USD` | 150 |
| `GCP_PROJECT` | gen-lang-client-0828350684 |
| `FIREBASE_DB_URL` | https://aiquiz-a12f6-default-rtdb.asia-southeast1.firebasedatabase.app |
| `FIREBASE_PROJECT_ID` | aiquiz-a12f6 |
| `AIQUIZ_PROXY_DIR` | ../aiquiz-proxy |

## テスト

```
npm test
```

集計（`lib/summaries.js`）・操作（`lib/actions.js`）・サーバーの振る舞いを、本番に触れずに確かめます。
