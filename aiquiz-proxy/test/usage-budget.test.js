const test = require('node:test');
const assert = require('node:assert/strict');
const { UsageBudget, costUsd, DEFAULT_PRICES, jstKeys } = require('../usage-budget');

const USAGE = { promptTokenCount: 2568, candidatesTokenCount: 389, thoughtsTokenCount: 96 };
const quiet = { warn() {}, error() {} };

test('cost follows the price table and counts thinking as output', () => {
    const usd = costUsd(DEFAULT_PRICES, 'gemini-3.6-flash', USAGE);
    assert.ok(Math.abs(usd - (2568 * 0.75 + 485 * 3.75) / 1e6) < 1e-12);
    assert.equal(costUsd(DEFAULT_PRICES, 'unknown-model', USAGE), 0);
});

test('days and months roll over at midnight Japan time', () => {
    assert.deepEqual(jstKeys(new Date('2026-10-18T14:59:59Z')), { day: '2026-10-18', month: '2026-10' });
    assert.deepEqual(jstKeys(new Date('2026-10-31T15:00:00Z')), { day: '2026-11-01', month: '2026-11' });
});

test('without Firebase the instance totals stop generation at the daily budget', async () => {
    const budget = new UsageBudget({ dailyBudgetUsd: 0.01, monthlyBudgetUsd: 100, log: quiet });
    assert.equal((await budget.check()).ok, true);
    budget.record('gemini-3.6-flash', USAGE); // ~$0.0037
    assert.equal((await budget.check()).ok, true);
    budget.record('gemini-3.6-flash', USAGE);
    budget.record('gemini-3.6-flash', USAGE);
    const verdict = await budget.check();
    assert.equal(verdict.ok, false);
    assert.equal(verdict.reason, 'daily_budget');
    assert.ok(verdict.retryAfterSec >= 60);
});

test('the monthly budget is checked before the daily one', async () => {
    const budget = new UsageBudget({ dailyBudgetUsd: 0.001, monthlyBudgetUsd: 0.001, log: quiet });
    budget.record('gemini-3.6-flash', USAGE);
    assert.equal((await budget.check()).reason, 'monthly_budget');
});

// Firebase の代わり: update() の increment を足し込み、once() で読み返す
function fakeDatabase() {
    const data = {};
    const valueOf = increment => (increment && increment['.sv'] && increment['.sv'].increment) ?? increment;
    return {
        data,
        ref(path) {
            return {
                async update(fields) {
                    for (const [key, value] of Object.entries(fields)) {
                        const full = `${path}/${key}`;
                        data[full] = Number(data[full] || 0) + Number(valueOf(value));
                    }
                },
                async once() {
                    return { val: () => data[path] ?? null };
                },
            };
        },
    };
}

test('flushed amounts land in Firebase and other instances see them', async () => {
    const db = fakeDatabase();
    const now = () => new Date('2026-10-18T03:00:00Z');
    const a = new UsageBudget({ databaseFactory: () => db, dailyBudgetUsd: 0.005, now, log: quiet });
    const b = new UsageBudget({ databaseFactory: () => db, dailyBudgetUsd: 0.005, now, log: quiet });
    a.record('gemini-3.6-flash', USAGE);
    a.record('gemini-3.5-flash-lite', USAGE);
    await a.flush();
    assert.equal(db.data['proxy_usage/v1/daily/2026-10-18/requests'], 2);
    assert.equal(db.data['proxy_usage/v1/daily/2026-10-18/models/gemini-3_6-flash/requests'], 1);
    assert.ok(db.data['proxy_usage/v1/monthly/2026-10/usd'] > 0.005);
    const verdict = await b.check();
    assert.equal(verdict.ok, false);
    assert.equal(verdict.reason, 'daily_budget');
});
