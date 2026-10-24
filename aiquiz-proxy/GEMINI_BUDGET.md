# Gemini の上限と予算

プロキシの URL と `APP_SECRET` はゲームから取り出せる前提で、ゲーム以外から叩かれても費用が膨らまないように止める。

## 関所（gemini-guard.js）

- **モデル**: `gemini-3.6-flash` / `gemini-3.1-flash-lite` / `gemini-3.5-flash-lite` だけ。ほかは 400。
- **本文**: `systemInstruction` / `contents` / `generationConfig` のテキストだけ。`tools`（検索連携）・画像やファイルの添付・`cachedContent`・`safetySettings` などは 400。本文は 64KB まで（超えると 413）。
- **思考**: `thinkingLevel` の `low` / `minimal` だけ。
- **出力の上限**: `maxOutputTokens` をモデルごとに上書き（3.6-flash 4096 / 3.1-flash-lite 6144 / 3.5-flash-lite 2048）。2026-09〜10 の実測の最大（出力＋思考）の 1.5〜2 倍。
- モデルを足すときは `MODEL_LIMITS`（gemini-guard.js）と `DEFAULT_PRICES`（usage-budget.js）の両方に足す。

## 予算（usage-budget.js）

返ってきた `usageMetadata` から費用を計算し、10 秒ごとに Realtime Database へ加算する。合計は 30 秒ごとに読み直し、超えたら `/gemini` と `/gemini-stream` は Gemini を呼ばずに `503 {"error":"daily_budget"|"monthly_budget"}` を返す（`Retry-After` 付き）。ゲームは 503 を受けると 5 分間オンライン生成を止め、そのラウンドを共有バンクの問題で続ける。

| 環境変数 | 既定値 | 意味 |
|---|---|---|
| `GEMINI_DAILY_BUDGET_USD` | 10 | 1 日（日本時間）の上限。0 で無効 |
| `GEMINI_MONTHLY_BUDGET_USD` | 100 | 月（日本時間）の上限。0 で無効 |
| `GEMINI_PRICES_JSON` | 未設定 | 料金表の差し替え。例: `{"gemini-3.6-flash":{"input":1.5,"output":7.5}}`（3.6 Flash は 2027-01-01 から 2 倍） |

実費は `proxy_usage/v1/daily/<YYYY-MM-DD>`（モデル別の内訳つき）と `proxy_usage/v1/monthly/<YYYY-MM>` に積み上がる。止めたときは Cloud Logging に `type: gemini_budget_block` が出る。`GET /health`（`X-App-Secret` 必須）で今日と今月の合計を見られる。

止まるまでの行き過ぎは「書き出し・読み直しの間隔 × その間の流量 × インスタンス数」程度。インスタンス数は `--max-instances` で抑える。

## 端末ごとの許可証と上限（device-auth.js / device-limits.js）

`APP_SECRET` はゲームから取り出せるので、端末ごとに許可証を出して使える量を抑える。

1. ゲームは初回起動時にランダムな端末 ID（32 桁の16進）を作って `user://device_session.json` に保存する。
2. `GET /session/challenge` で署名つきの課題をもらい、`sha256("challenge:iid:counter")` の先頭 `DEVICE_POW_BITS` ビットが 0 になる counter を探す（18 ビットで平均 26 万回。普通の PC で 0.1〜0.6 秒、遅い PC でも数秒）。
3. `POST /session {iid, challenge, counter}` で許可証（30 日有効）をもらう。ゲームは残り 3 日を切ったら取り直す。
4. `/gemini` と `/gemini-stream` は `X-Device-Token` が無いか正しくないと 401。ゲームは許可証を取り直し、その間のラウンドは共有バンクで続ける。

| 環境変数 | 既定値 | 意味 |
|---|---|---|
| `DEVICE_TOKEN_KEY` | 未設定 | 許可証と課題の署名鍵（Secret Manager `device-token-key`）。未設定だと許可証を使わない（手元の開発用） |
| `DEVICE_TOKEN_REQUIRED` | 1 | `0` にすると許可証が無いリクエストも通す（付いていれば数える） |
| `DEVICE_POW_BITS` | 18 | 課題の難しさ |
| `DEVICE_DAILY_BUDGET_USD` | 0.30 | 端末 1 台の 1 日の上限（10 問モード約 10 試合分） |
| `NEW_DEVICE_DAILY_BUDGET_USD` | 0.10 | 許可証をもらってから 24 時間の上限 |
| `IP_DAILY_BUDGET_USD` | 30 | 1 つの IP の 1 日の上限（学校の教室を想定） |
| `SESSION_PER_IP_PER_HOUR` | 200 | 1 つの IP から 1 時間にもらえる許可証の数 |

- 上限を超えると `503 {"error":"device_daily_budget"|"ip_daily_budget"}`。ゲームはそのラウンドを共有バンクで続ける。
- 端末・回線を止めるときは管理ソフト（`../aiquiz-ops`）のプレイヤーのタブから。
  Realtime Database の `device_blocklist/v1/<iid または ipKey>` に値が入り、1 分以内に効く。
  止めた端末・回線には 503（`device_blocked` / `ip_blocked`、Retry-After 1 時間）を返し、ゲームは共有バンクで続ける。
- 止めた回数は理由ごとに `proxy_usage/v1/denials/<日付>/<理由>/count` に数える
  （`daily_budget`・`monthly_budget`・`device_daily_budget`・`ip_daily_budget`・`device_blocked`・`ip_blocked`・
  `device_token`・`rate_limited`・`session_rate_limited`・`round_no_new`）。
- 利用額は `proxy_usage/v1/devices/<日付>/<iid>` と `proxy_usage/v1/ips/<日付>/<IPの鍵つきハッシュ>` に積み上がる。IP そのものは保存しない。ログには発行時 `device_session`、上限で止めたとき `device_limit_block` が出る。
- 古い日付のノードは溜まっていくので、ときどき消す（今は自動では消さない）。

## ラウンドの作り方（round-plan.js、フェーズ C1）

月の上限に収めるため、ゲームはラウンド開始時に `POST /round-plan {"mode":"ten"|"endless"}`（`X-Device-Token` 必須）を呼び、10 問のうち何問を Gemini で新しく作るかを受け取る。残りは共有バンク（同じ難易度）→ 端末内の問題プール → 同梱の問題 → 共有バンク（別の難易度）の順に、その端末がまだ見ていない問題で埋める。エンドレスは補充のうち `endless_new_ratio` だけを新作にする。

全体の使用ペース（`今日使ってよい額 ＝（月の上限 − 昨日までの今月の使用額）÷ 今月の残り日数`、日の上限以下）と、その端末の今日の何試合目かで決める。

| ペース | 判定 | 1〜2 試合目 | 3 試合目以降 |
|---|---|---|---|
| green | 今日の使用額の割合 ≦ 今日の経過時間の割合 + 0.1 | 10 | 10 |
| yellow | ≦ 経過時間の割合 + 0.3 | 10 | 3 |
| orange | それより速い | 6 | 0 |
| red | 今日の目安を使い切った | 3 | 0 |
| stop | 日・月の上限、または端末・IP の上限に達した | 0 | 0 |

- 返り値: `{level, round_index, new_count, endless_new_ratio}`。ログには `round_plan` が出る。
- 端末ごとの今日のラウンド数は `proxy_usage/v1/rounds/<日付>/<iid>/rounds`。
- `ROUND_PLAN_FORCE_LEVEL`（`green`〜`stop`）: 運用のスイッチ。予算が残っていても全員をその段階にする（例: `stop` で全員バンクだけ）。日・月の上限を超えているときは常に `stop`。
- ゲームは計画を受け取れなかったとき（古いプロキシ・通信失敗）は従来どおり 10 問とも作る。

## レート制限

IP ごと・インスタンスごとに 1 分あたり Gemini 30 回、共有バンクと `/health` 120 回（枠は別）。

## デプロイ

```
gcloud run deploy aiquiz-proxy --source . --region asia-northeast1 --project gen-lang-client-0828350684 \
  --max-instances 5 \
  --update-env-vars GEMINI_DAILY_BUDGET_USD=10,GEMINI_MONTHLY_BUDGET_USD=85 \
  --update-secrets DEVICE_TOKEN_KEY=device-token-key:latest \
  --remove-secrets OPENAI_API_KEY
```

`device-token-key` を初めて作るとき（値は 32 バイト以上のランダム値）:

```
python -c "import secrets,sys; sys.stdout.write(secrets.token_urlsafe(48))" | gcloud secrets create device-token-key --data-file=- --project gen-lang-client-0828350684
```

鍵を変えると、配った許可証はすべて 401 になる（ゲームは自動で取り直す）。

クライアントより先にプロキシを更新する（新しいクライアントは `/health` を使う）。古いクライアントは生成はそのまま動くが、設定画面の接続確認だけ 400 になる。

## APP_SECRET の差し替え

古い値は公開リポジトリの履歴に残っているので、差し替える以外に無効にする方法はない。差し替えると古いビルド（exe・Android）は 403 で繋がらなくなる。

1. 新しい値を作って Secret Manager に新しい版として入れる（サービスは `latest` を参照している）。
2. プロキシを再デプロイして新しい版を読ませる。
3. ゲーム側の `.env` の `APP_SECRET=` を新しい値にして書き出し直す（`.env` は git 管理外、書き出しには含まれる）。
