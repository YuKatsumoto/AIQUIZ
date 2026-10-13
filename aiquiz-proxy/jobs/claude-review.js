// Cloud Run Job の入口: `node jobs/claude-review.js`
// 1回動かすと、終わった Batch の回収と新しい Batch の送信を1回ずつ行って終了する。
// 必要な環境変数: ANTHROPIC_API_KEY, FIREBASE_DB_URL, FIREBASE_PROJECT_ID
// 任意: CLAUDE_REVIEW_MODEL, CLAUDE_REVIEW_EFFORT, CLAUDE_REVIEW_MAX_PER_RUN,
//       CLAUDE_REVIEW_MONTHLY_BUDGET_USD, CLAUDE_REVIEW_EST_USD_PER_ITEM,
//       CLAUDE_REVIEW_INCLUDE_GOOD=1, CLAUDE_REVIEW_DRY_RUN=1
const Anthropic = require('@anthropic-ai/sdk').default;
const { createFirebaseDatabase } = require('../quiz-bank-service');
const { ClaudeReviewJob, configFromEnv } = require('../claude-review');

async function main() {
    const config = configFromEnv();
    if (!config.dryRun && !process.env.ANTHROPIC_API_KEY) {
        throw new Error('ANTHROPIC_API_KEY is not configured');
    }
    const job = new ClaudeReviewJob({
        db: createFirebaseDatabase(),
        anthropic: config.dryRun ? null : new Anthropic(),
        config,
    });
    const result = config.dryRun
        ? { collected: null, submitted: await job.submit() }
        : await job.run();
    console.log(JSON.stringify({ type: 'claude_review', config: { ...config }, ...result }));
}

main().then(
    () => process.exit(0),
    error => {
        console.error(JSON.stringify({ type: 'claude_review_error', error: error.message }));
        process.exit(1);
    },
);
