# 試合中の Claude（/claude・/claude-stream）

ゲームの問題づくり（試合中）を Claude に頼む入口。Cloud Run サービス `aiquiz-proxy-claude` として動かす。
それまでの Gemini 系統（`aiquiz-proxy`・`/gemini`）とは別のサービスで、このサービスからは Gemini を呼べない。

## なぜ Claude にしたか

- Gemini API の追加利用規約と Google Cloud Service Specific Terms（§20(d)）は、18 歳未満に向けたサービス、
  または 18 歳未満が使う可能性が高いサービスで生成 AI を使うことを禁じている。このゲームは小学生向け。
- Anthropic は、安全対策（子ども向けの安全指示、AI であることの開示、法令の順守とその公開、監査への協力）を条件に、
  未成年が使うプロダクトへの組み込みを認めている（Guidelines for Organizations Serving Minors）。
- 2026-11-03 の比較で、Sonnet 5.5（effort low）は Gemini 3.6 Flash と正しさ・一対比較で同等、最初の 1 問まで約 2 秒だった
  （`AIQUIZ-Godot/docs/evals/2026-11-03_quiz_generation_gemini_vs_claude.md`）。

## 入口

本文は `{"task": ..., "prompt": ..., "system": ...}` だけ（`system` は省略できる）。ゲームはモデルを指定しない。

| task | 使うところ（ゲーム） | 既定のモデル | 返事 |
|---|---|---|---|
| `generate` | 問題づくり（online_fetch.gd） | Sonnet 5.5・effort low | `/claude-stream` は SSE、`/claude` は `{text}` |
| `explain` | 解説の補充（online_fetch.gd） | Sonnet 5.5・effort low | `{text}`（`[{id, e}]`） |
| `validate` | 正解の確かめ（quiz_validator.gd） | Sonnet 5.5・effort low | `{text}`（`[{id, correct_answer, claimed_ok, grade_ok, issue}]`） |
| `evaluate` | 良問・悪問の評価（quiz_optimizer.gd） | Sonnet 5.5・effort low | `{text}`（`[{id, rating, reason}]`） |

- どの task も、system の先頭に子ども向けの安全指示（`claude-live.js` の `CHILD_SAFETY`）を付ける。ゲームからは外せない。
- `explain`・`validate`・`evaluate` は structured outputs（JSON Schema）で形を固定し、`{items:[...]}` の中身の配列を `text` に入れて返す。
- Sonnet 5.5 にはサーバー側のフォールバック（`fallbacks: "default"`、beta `server-side-fallback-2026-07-01`）を付ける。
- `/claude-stream` の行は `data: {"type":"text"|"done"|"error", ...}`。考えているあいだは 5 秒ごとに `: keep-alive` を送り、
  ゲームの 20 秒の無通信タイムアウトで切れないようにする。
- 失敗の返し方: Anthropic の 429 は 429（ゲームは待つ）、529・5xx・接続失敗は 503（そのラウンドを共有バンクで続ける）、
  拒否（`stop_reason: refusal`）は `/claude` で 422、`/claude-stream` で `error` の行。
- 用途ごとのモデルは `CLAUDE_TASK_MODELS_JSON` で差し替えられる。例: `{"explain":{"model":"claude-haiku-5-5","effort":"low"}}`。

## プロンプトキャッシュ（generate、2026-11-05〜）

10 問モードは 1 試合に `generate` を 6 本呼ぶ。6 本の違いは出題アプローチと担当単元だけで、ほかのルールや出題済みリストは同じ。

- ゲームは、6 本で同じ部分を `system` に入れ、その 1 本だけの部分を `prompt` に入れて送る（`online_fetch.gd` の `compose_prompt_parts`・`_generation_body`）。
  2026-11-05 に書き出した 6 区分では、1 本のうち 77〜85% が `system` に入った。
- プロキシは `generate` の `system` に `cache_control: {type: "ephemeral"}` を付ける（`DEFAULT_TASKS.generate.cacheSystem`）。
  キャッシュは 5 分間有効。1 本目で書き込み（入力の 1.25 倍）、2 本目からは 1 割（$0.20/MTok）で読む。
- キャッシュが読めるのは、1 本目の返事が流れ始めてから。そのためゲームは 1 本目だけ先に送り、返事のヘッダーが届いたら残りを送る（`_launch_fanout`）。
  返事が来ないときも 2 秒で残りを送る。
- 見込みは、問題づくりの入力の費用が約 58% 減、1 試合 約 0.11 ドル → 約 0.07〜0.08 ドル。
  並び替えで問題の質が落ちないことは、本番に出す前に確かめた（`AIQUIZ-Godot/docs/evals/2026-11-05_prompt_cache_order_ab.md`）。
- 2026-11-05 にリビジョン `aiquiz-proxy-claude-00002-5g5` へデプロイし、`tests/claude_live_runtime.gd`（算数 3 年・普通）で実測した。
  - generate 6 本: 1 本目が 3,984 トークンを書き込み、2〜6 本目が 3,984 トークンずつ読み込んで、合計 $0.044。
    切り替え前の本番は同じ 6 本で約 $0.083 だった。
  - 1 試合（正解の確かめ・解説を含む）は $0.062。11/3 の同じテストは $0.097 だった。
  効いているかは Cloud Logging の `claude_usage`（`task: generate`）の `cache_creation_input_tokens`・`cache_read_input_tokens` で見る。
  1 試合で書き込み 1 本・読み込み 5 本になっていればよい。
- 止めるときは `CLAUDE_TASK_MODELS_JSON={"generate":{"cacheSystem":false}}`。
- `explain`・`validate`・`evaluate` は 1 回きりの呼び出しが多く、書き込みの割増しだけになるので付けていない。
- デプロイはプロキシが先。古いゲームは今までどおり全文を `prompt` で送るので、キャッシュに載らないだけで動く。
  新しいゲームと古いプロキシの組み合わせも動くが、キャッシュは効かない。`system` が 7500 字を超えたら、ゲームは全文を `prompt` に戻す。
  Haiku 5.5 は effort low でも考える時間が長く（最初の 1 問まで約 17 秒）、思考を切ると合格率が 70% に下がったので、問題づくりには使わない。

## 予算（月 100 ドル未満の全体予算のうち）

| 何に | 上限 | 設定 |
|---|---|---|
| 試合中の Claude（このサービス） | 月 40 ドル・1 日 3 ドル | `CLAUDE_MONTHLY_BUDGET_USD` / `CLAUDE_DAILY_BUDGET_USD` |
| 毎週の判定（quiz-claude-review） | 月 20 ドル | `CLAUDE_REVIEW_MONTHLY_BUDGET_USD`（CLAUDE_REVIEW.md） |
| 毎週の補充（quiz-bank-builder） | 月 5 ドル | `BANK_BUILDER_MONTHLY_BUDGET_USD` |
| 最後の歯止め | 月 100 ドル | Claude Console の「支出上限」（手で設定する） |

- 実費は `proxy_usage_claude/v1/daily/<YYYY-MM-DD>`・`proxy_usage_claude/v1/monthly/<YYYY-MM>` に積み上がる（Gemini 系統の `proxy_usage/v1` とは別）。
- 月の予算の進み具合で、10 問のうち何問を新しく作るかを `/round-plan` が決める（round-plan.js。残りは共有バンクから）。
  予算に達すると `/claude*` は 503 を返し、ゲームはそのラウンドを共有バンクで続ける。
- 1 回あたりの実費（2026-11-03、手元で計測）: 問題づくり 4 問 約 0.011 ドル、正解の確かめ 4 問 約 0.004 ドル、
  解説 4 問 約 0.004 ドル、評価 4 問 約 0.005 ドル。
- 端末・回線ごとの 1 日の上限（device-limits.js）は Gemini 系統と同じ仕組み（GEMINI_BUDGET.md の後半）。
  Claude は 1 試合あたりの額が大きいので、このサービスでは `DEVICE_DAILY_BUDGET_USD=0.5`・`NEW_DEVICE_DAILY_BUDGET_USD=0.2` にする。

## デプロイ

```
gcloud run deploy aiquiz-proxy-claude --source . --region asia-northeast1 \
  --project gen-lang-client-0828350684 --max-instances 5 \
  --set-secrets ANTHROPIC_API_KEY=anthropic-api-key:latest \
  --set-env-vars ^@^APP_SECRET=<既存と同じ>@DEVICE_TOKEN_KEY=<既存と同じ>@FIREBASE_DB_URL=<URL>@FIREBASE_PROJECT_ID=aiquiz-a12f6@QUIZ_BANK_REQUIRE_REVIEW=1@CLAUDE_MONTHLY_BUDGET_USD=40@CLAUDE_DAILY_BUDGET_USD=3@DEVICE_DAILY_BUDGET_USD=0.5@NEW_DEVICE_DAILY_BUDGET_USD=0.2
```

- 共有バンク（`/quiz-bank/*`）・端末の許可証（`/session*`）・`/round-plan` は Gemini 系統と同じ Firebase を使う。
  `DEVICE_TOKEN_KEY` を同じにすると、どちらのサービスで取った許可証も使える。
- デプロイしたら、ゲームの `PROXY_URL` の既定値（`AIQUIZ-Godot/scripts/core/api_status.gd`）をこのサービスの URL にする。

## 手元での確認

```
npm test
ANTHROPIC_API_KEY=... PORT=18080 node index.js   # FIREBASE_DB_URL・DEVICE_TOKEN_KEY・APP_SECRET が無ければ、それぞれの確認を飛ばす
```
