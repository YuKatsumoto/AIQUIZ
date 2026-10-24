// プロキシ（aiquiz-proxy）と同じ計算を使うための読み込み口。
// 段階の判定・新作の数・夜のジョブの既定値・区分の一覧を、プロキシのコードからそのまま借りる。
// 管理ソフトとプロキシで数字がずれないようにするため、ここで書き直さない。
const path = require('path');

const PROXY_DIR = process.env.AIQUIZ_PROXY_DIR || path.join(__dirname, '..', '..', 'aiquiz-proxy');

function load(name) {
    try {
        return require(path.join(PROXY_DIR, name));
    } catch (error) {
        throw new Error(`aiquiz-proxy の ${name} を読み込めません（${PROXY_DIR}）。`
            + `aiquiz-proxy で npm install 済みか確認してください: ${error.message}`);
    }
}

const usageBudget = load('usage-budget.js');
const roundPlan = load('round-plan.js');
const bankBuilder = load('bank-builder.js');
const claudeReview = load('claude-review.js');
const deviceLimits = load('device-limits.js');
const quizBank = load('quiz-bank-service.js');

module.exports = {
    BLOCKLIST_PATH: deviceLimits.BLOCKLIST_PATH,
    BUILDER_PATH: bankBuilder.BUILDER_PATH,
    DeviceLimits: deviceLimits.DeviceLimits,
    NEW_COUNT_TABLE: roundPlan.NEW_COUNT_TABLE,
    PRIORITY_ROUNDS: roundPlan.PRIORITY_ROUNDS,
    USAGE_PATH: usageBudget.USAGE_PATH,
    UsageBudget: usageBudget.UsageBudget,
    builderConfigFromEnv: bankBuilder.configFromEnv,
    jstKeys: usageBudget.jstKeys,
    loadPrompts: bankBuilder.loadPrompts,
    newCountFor: roundPlan.newCountFor,
    putBankItem: quizBank.putBankItem,
    removeBankItem: quizBank.removeBankItem,
    reviewConfigFromEnv: claudeReview.configFromEnv,
};
