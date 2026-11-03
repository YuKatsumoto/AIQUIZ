const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');

process.env.APP_SECRET = 'test-app-secret';
process.env.DEVICE_TOKEN_KEY = 'test-device-key';
process.env.DEVICE_POW_BITS = '4';
delete process.env.FIREBASE_DB_URL;
const { app, budget, deviceAuth, deviceLimits } = require('../index');
const { newCountFor } = require('../round-plan');
const { UsageBudget } = require('../usage-budget');

const HEADERS = { 'Content-Type': 'application/json', 'X-App-Secret': 'test-app-secret' };
const quiet = { warn() {}, error() {} };

test('the first two rounds of a device keep more new questions when the budget is tight', () => {
    assert.deepEqual([1, 2, 3].map(i => newCountFor('green', i)), [10, 10, 10]);
    assert.deepEqual([1, 2, 3].map(i => newCountFor('yellow', i)), [10, 10, 3]);
    assert.deepEqual([1, 2, 3].map(i => newCountFor('orange', i)), [6, 6, 0]);
    assert.deepEqual([1, 2, 3].map(i => newCountFor('red', i)), [3, 3, 0]);
    assert.deepEqual([1, 3].map(i => newCountFor('stop', i)), [0, 0]);
});

test('the pace compares today spend with the share of the monthly budget left per day', async () => {
    // 2026-10-18 12:00 JST: 14 days left including today, half of today gone.
    const now = () => new Date('2026-10-18T03:00:00Z');
    const usage = usd => ({ promptTokenCount: Math.round(usd / 0.75 * 1e6) }); // 3.6-flash input only
    const make = () => new UsageBudget({ dailyBudgetUsd: 10, monthlyBudgetUsd: 85, now, log: quiet });
    const levelAfter = async usd => {
        const b = make();
        if (usd > 0) b.record('gemini-3.6-flash', usage(usd));
        return (await b.paceLevel()).level;
    };
    const { targetUsd } = await make().paceLevel();
    assert.ok(Math.abs(targetUsd - 85 / 14) < 1e-9);
    assert.equal(await levelAfter(0), 'green');
    assert.equal(await levelAfter(targetUsd * 0.55), 'green');
    assert.equal(await levelAfter(targetUsd * 0.7), 'yellow');
    assert.equal(await levelAfter(targetUsd * 0.9), 'orange');
    assert.equal(await levelAfter(targetUsd * 1.01), 'red');
});

async function withProxy(callback) {
    const proxy = app.listen(0, '127.0.0.1');
    await new Promise(resolve => proxy.once('listening', resolve));
    try {
        await callback(`http://127.0.0.1:${proxy.address().port}`);
    } finally {
        await new Promise(resolve => proxy.close(resolve));
    }
}

function tokenFor(iid) {
    return deviceAuth.issueToken(iid).token;
}

async function plan(base, token, mode = 'ten') {
    const response = await fetch(`${base}/round-plan`, { method: 'POST',
        headers: token ? { ...HEADERS, 'X-Device-Token': token } : HEADERS, body: JSON.stringify({ mode }) });
    return { status: response.status, body: await response.json() };
}

test('round plans count the rounds of each device and need a device token', async () => {
    await withProxy(async base => {
        assert.equal((await plan(base, null)).status, 401);
        const token = tokenFor(crypto.randomBytes(16).toString('hex'));
        const first = await plan(base, token);
        assert.equal(first.status, 200);
        assert.equal(first.body.level, 'green');
        assert.equal(first.body.round_index, 1);
        assert.equal(first.body.new_count, 10);
        assert.equal(first.body.endless_new_ratio, 1);
        assert.equal((await plan(base, token, 'endless')).body.round_index, 2);
        assert.equal((await plan(base, token)).body.round_index, 3);
        // another device starts from its own first round
        assert.equal((await plan(base, tokenFor(crypto.randomBytes(16).toString('hex')))).body.round_index, 1);
    });
});

test('an exhausted budget or device gives bank-only rounds', async () => {
    await withProxy(async base => {
        const iid = crypto.randomBytes(16).toString('hex');
        const token = tokenFor(iid);
        deviceLimits.record({ iid, ipKey: '' }, 1.0);
        const capped = await plan(base, token);
        assert.equal(capped.body.level, 'stop');
        assert.equal(capped.body.new_count, 0);

        const saved = budget.dailyBudgetUsd;
        budget.record('claude-sonnet-5-5', {}, 0.01);
        budget.dailyBudgetUsd = budget.totals().dailyUsd;
        try {
            const stopped = await plan(base, tokenFor(crypto.randomBytes(16).toString('hex')));
            assert.equal(stopped.body.level, 'stop');
            assert.equal(stopped.body.new_count, 0);
        } finally {
            budget.dailyBudgetUsd = saved;
        }
    });
});
