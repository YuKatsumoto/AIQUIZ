# 共有バンクの Claude 確認

ゲーム中に Gemini が作った問題は、共有アーカイブ（`quiz_archive/v1/items`）に「保留（pending）」で入ります。
この仕組みは、保留の問題を1日1回 Claude にまとめて確認させ、合格したものだけを共有バンク（`quiz_bank/v1/items`）へ入れます。

- 確認は Message Batches API（通常の半額）で行います。正解と解説は伏せ、Claude に自分で解かせます。
- **合格**: Claude の答えが登録の正解と一致し、指摘がなく、自信が low でない → `good` にして共有バンクへ。
- **不合格**: 答えが違う、または指摘あり（正解なし・複数正解・あいまい・事実誤り・学年外・不適切）→ `bad` にして除外。
- **保留のまま**: 自信が low のときは何もしません（共有バンクには入れない）。
- 確認に出した問題の本文・選択肢・正解・解説は、以後クライアントの送信で書き換えられません。
- `QUIZ_BANK_REQUIRE_REVIEW=1` のとき、プレイヤーや Gemini の「good」は票（`good_votes`）として数えるだけで、昇格させません。票が多い問題から先に確認します。「bad」はこれまでどおり即除外です。

## 費用の歯止め

| 環境変数 | 既定値 | 意味 |
|---|---|---|
| `CLAUDE_REVIEW_MONTHLY_BUDGET_USD` | 25 | 月の上限（USD）。回収済みの実費＋未回収分の見込みが超えそうなら送信しない |
| `CLAUDE_REVIEW_MAX_PER_RUN` | 300 | 1回の実行で送る最大件数 |
| `CLAUDE_REVIEW_EST_USD_PER_ITEM` | 0.005 | 未回収分の1問あたり見込み。2026-10 のお試し50問の実費は $0.004/問（Opus 5.5・medium）。実費（`quiz_review/v1/spend/<月>`）を見て合わせる |
| `CLAUDE_REVIEW_MODEL` | `claude-opus-5-5` | 確認に使うモデル |
| `CLAUDE_REVIEW_EFFORT` | `medium` | 考える深さ（`low` / `medium` / `high`） |
| `CLAUDE_REVIEW_INCLUDE_GOOD` | 未設定 | `1` にすると、これまでクライアントの good だけで共有バンクに入った問題も確認し直す |
| `CLAUDE_REVIEW_DRY_RUN` | 未設定 | `1` にすると API を呼ばず、送る予定の件数と先頭3件のリクエストだけを表示 |

実費は `quiz_review/v1/spend/<YYYY-MM>` に月ごとに積み上がります。Batch ごとの記録は `quiz_review/v1/batches/<batch_id>` です。

## 導入手順

順番が大事です。**クライアント（Godot）より先にプロキシを更新してください。**
新しいクライアントは英語と `GEMINI_POOL` の問題も送るため、古いプロキシだと送信がまとめて 400 になります。

1. Claude Console で専用のワークスペースと API キーを作り、Secret Manager に入れる。
   ```
   gcloud secrets create anthropic-api-key --data-file=-
   ```
2. Realtime Database のルールに、`status` の索引を足す（無いと保留の問題を探すたびに全件を読む）。
   ```json
   "quiz_archive": { "v1": { "items": { ".indexOn": ["status"] } } }
   ```
3. プロキシ（Cloud Run サービス）を更新する。この時点では `QUIZ_BANK_REQUIRE_REVIEW` は付けない（従来どおり good で昇格）。
4. 同じイメージで Cloud Run Job を作り、お試し実行で中身を確認する。
   ```
   gcloud run jobs create quiz-claude-review --image <IMAGE> --region <REGION> \
     --command node --args jobs/claude-review.js \
     --set-secrets ANTHROPIC_API_KEY=anthropic-api-key:latest \
     --set-env-vars FIREBASE_DB_URL=<URL>,FIREBASE_PROJECT_ID=<ID>,CLAUDE_REVIEW_DRY_RUN=1
   gcloud run jobs execute quiz-claude-review --region <REGION> --wait
   ```
5. 少数で試す: `CLAUDE_REVIEW_DRY_RUN` を外し、`CLAUDE_REVIEW_MAX_PER_RUN=50` で実行 → 数時間後にもう一度実行して回収。
   合格率・不合格の理由・1問あたりの実費を確認し、`CLAUDE_REVIEW_EST_USD_PER_ITEM` を合わせる。
6. 問題なければサービス側に `QUIZ_BANK_REQUIRE_REVIEW=1` を付け、Cloud Scheduler で Job を1日1回動かす。
   ```
   gcloud scheduler jobs create http quiz-claude-review-daily --location <REGION> \
     --schedule "0 4 * * *" --time-zone Asia/Tokyo \
     --uri https://<REGION>-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/<PROJECT>/jobs/quiz-claude-review:run \
     --http-method POST --oauth-service-account-email <SA>
   ```
   Batch は通常1時間以内、遅くとも24時間で終わります。1日1回の実行で「前日の分を回収 → 新しい分を送信」になります。

## 手元での確認

```
npm test
CLAUDE_REVIEW_DRY_RUN=1 FIREBASE_DB_URL=... FIREBASE_PROJECT_ID=... node jobs/claude-review.js
```
