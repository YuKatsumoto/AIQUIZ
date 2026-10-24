// Cloud Run Job の入口: `node jobs/bank-builder.js`
// 1 回動かすと、終わった Batch の回収と新しい Batch の送信を 1 回ずつ行って終了する。
// 必要な環境変数: ANTHROPIC_API_KEY, FIREBASE_DB_URL, FIREBASE_PROJECT_ID
// 任意: BANK_BUILDER_MODEL, BANK_BUILDER_EFFORT, BANK_BUILDER_MONTHLY_BUDGET_USD,
//       BANK_BUILDER_MAX_CALLS_PER_RUN, BANK_BUILDER_MAX_CALLS_PER_BUCKET,
//       BANK_BUILDER_TARGET_PER_BUCKET, BANK_BUILDER_EST_USD_PER_CALL, BANK_BUILDER_DRY_RUN=1
const Anthropic = require('@anthropic-ai/sdk').default;
const { createFirebaseDatabase } = require('../quiz-bank-service');
const { BankBuilderJob, configFromEnv } = require('../bank-builder');

async function main() {
    const config = configFromEnv();
    if (!config.dryRun && !process.env.ANTHROPIC_API_KEY) {
        throw new Error('ANTHROPIC_API_KEY is not configured');
    }
    const job = new BankBuilderJob({
        db: createFirebaseDatabase(),
        anthropic: config.dryRun ? null : new Anthropic(),
        config,
    });
    const result = config.dryRun
        ? { collected: null, submitted: await job.submit() }
        : await job.run();
    console.log(JSON.stringify({ type: 'bank_builder', config: { ...config }, ...result }));
}

main().then(
    () => process.exit(0),
    error => {
        console.error(JSON.stringify({ type: 'bank_builder_error', error: error.message }));
        process.exit(1);
    },
);
