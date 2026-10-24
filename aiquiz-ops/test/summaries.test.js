const test = require('node:test');
const assert = require('node:assert/strict');
const { bankSummary, claudeSummary, jobsSummary, moneySummary, playersSummary } = require('../lib/summaries');

// 2026-10-18 12:00 JST
const NOW = new Date('2026-10-18T03:00:00Z');

test('money: totals, model names, 30-day history and month-end projection', () => {
    const daily = {
        '2026-09-30': { usd: 9, requests: 100, models: { 'gemini-3_6-flash': { usd: 9, requests: 100 } } },
        '2026-10-17': { usd: 2, requests: 40, models: { 'gemini-3_6-flash': { usd: 1.5, requests: 30 },
            'gemini-3_1-flash-lite': { usd: 0.5, requests: 10 } } },
        '2026-10-18': { usd: 1, requests: 20, models: { 'gemini-3_6-flash': { usd: 1, requests: 20 } } },
    };
    const m = moneySummary({
        now: NOW,
        budgets: { dailyUsd: 10, monthlyUsd: 85 },
        level: 'yellow',
        pace: { level: 'yellow', targetUsd: 5, timeFrac: 0.5 },
        daily,
        monthly: { '2026-10': { usd: 30, requests: 600 } },
        claude: { totalUsd: 0 },
    });
    assert.equal(m.day, '2026-10-18');
    assert.equal(m.gemini.today.usd, 1);
    assert.equal(m.gemini.month.usd, 30);
    // 17.5 日で $30 → 31 日では約 $53
    assert.ok(Math.abs(m.gemini.month.projectedUsd - 30 / (17.5 / 31)) < 0.01);
    assert.deepEqual(m.gemini.newCount, { first: 10, later: 3, priorityRounds: 2 });
    // 先月の日は今月のモデル別に入らない
    assert.deepEqual(m.gemini.modelsMonth.map(x => [x.model, x.usd]),
        [['gemini-3.6-flash', 2.5], ['gemini-3.1-flash-lite', 0.5]]);
    assert.equal(m.gemini.history.length, 30);
    assert.equal(m.gemini.history.at(-1).day, '2026-10-18');
    assert.equal(m.gemini.history.at(-2).models['gemini-3.1-flash-lite'], 0.5);
    assert.equal(m.gemini.history[0].usd, 0);
});

test('money: no projection on the first day of the month', () => {
    const m = moneySummary({
        now: new Date('2026-11-01T03:00:00Z'),
        budgets: { dailyUsd: 10, monthlyUsd: 85 },
        level: 'green',
        pace: { level: 'green', targetUsd: 2.7, timeFrac: 0.5 },
        claude: {},
    });
    assert.equal(m.gemini.month.projectedUsd, null);
});

test('claude: spend for the month and the estimate for batches not collected yet', () => {
    const c = claudeSummary({
        month: '2026-10',
        builderSpend: { '2026-10': { usd: 1.25, requests: 600 }, '2026-09': { usd: 9 } },
        builderBatches: { a: { state: 'submitted', count: 300 }, b: { state: 'collected', count: 300 } },
        builderConfig: { monthlyBudgetUsd: 15, estimatedUsdPerCall: 0.002, model: 'claude-haiku-5-5' },
        reviewSpend: null,
        reviewBatches: { c: { state: 'submitted', count: 1200 } },
        reviewConfig: { monthlyBudgetUsd: 70, estimatedUsdPerItem: 0.005, model: 'claude-opus-5-5' },
    });
    assert.equal(c.builder.usd, 1.25);
    assert.deepEqual(c.builder.inflight, { batches: 1, items: 300, estUsd: 0.6 });
    assert.equal(c.review.usd, 0);
    assert.equal(c.review.inflight.estUsd, 6);
    assert.equal(c.totalBudgetUsd, 85);
});

test('players: devices from spend and rounds, caps, blocked ids and 14-day history', () => {
    const p = playersSummary({
        now: NOW,
        devices: { d1: { usd: 0.27, requests: 50 }, d2: { usd: 0.01, requests: 3 } },
        ips: { ipA: { usd: 0.28, requests: 53 } },
        rounds: { d1: { rounds: 6 }, d3: { rounds: 2 } },
        roundsHistory: { '2026-10-17': { d1: { rounds: 4 } }, '2026-10-18': { d1: { rounds: 6 }, d3: { rounds: 2 } } },
        blocked: { d2: true, fJCicjuEcwuyAOpz6hBddp: { kind: 'ip', reason: '連打', at: 100, by: 'me' } },
        denials: { daily_budget: { count: 3, requests: 3 }, device_blocked: { count: 7, requests: 7 } },
        caps: { deviceUsd: 0.3, ipUsd: 30 },
        geminiTodayUsd: 0.28,
    });
    assert.deepEqual(p.denials, [{ reason: 'device_blocked', count: 7 }, { reason: 'daily_budget', count: 3 }]);
    assert.deepEqual(p.blockedList.map(b => [b.key, b.kind, b.reason]),
        [['fJCicjuEcwuyAOpz6hBddp', 'ip', '連打'], ['d2', 'ip', '']]);
    assert.equal(p.today.rounds, 8);
    assert.equal(p.today.devices, 3);
    assert.equal(p.today.generatingDevices, 2);
    assert.equal(p.today.nearCapDevices, 1);
    assert.equal(p.today.atCapDevices, 0);
    assert.equal(p.today.usdPerRound, 0.035);
    assert.equal(p.today.blockedCount, 2);
    assert.deepEqual(p.topDevices.map(d => d.id), ['d1', 'd2', 'd3']);
    assert.equal(p.topDevices[1].blocked, true);
    assert.equal(p.topDevices[0].capPct, 0.9);
    assert.equal(p.history.length, 14);
    assert.deepEqual(p.history.slice(-2), [
        { day: '2026-10-17', rounds: 4, devices: 1 },
        { day: '2026-10-18', rounds: 8, devices: 2 },
    ]);
});

test('bank: stock per bucket, pending states, origins and per-batch verdicts', () => {
    const prompts = { prompts: [
        { subject: '算数', grade: 3, difficulty: '普通' },
        { subject: '算数', grade: 3, difficulty: '簡単' },
        { subject: '国語', grade: 1, difficulty: '簡単' },
    ] };
    const reviewedAt = Math.floor(NOW.getTime() / 1000) - 3600;
    const archive = {
        q1: { subject: '算数', grade: 3, difficulty: '普通', status: 'good', original_src: 'CLAUDE_HAIKU',
            review: { state: 'done', verdict: 'pass', batch_id: 'rb1', reviewed_at: reviewedAt } },
        q2: { subject: '算数', grade: 3, difficulty: '普通', status: 'good', original_src: 'GEMINI_STREAM' },
        q3: { subject: '算数', grade: 3, difficulty: '普通', status: 'bad',
            review: { state: 'done', verdict: 'fail', batch_id: 'rb1', reviewed_at: reviewedAt } },
        q4: { subject: '算数', grade: 3, difficulty: '簡単', status: 'pending' },
        q5: { subject: '算数', grade: 3, difficulty: '簡単', status: 'pending', review: { state: 'submitted', batch_id: 'rb2' } },
        q6: { subject: '算数', grade: 3, difficulty: '簡単', status: 'pending', review: { state: 'error', batch_id: 'rb1' } },
    };
    const bank = {
        q1: { subject: '算数', grade: 3, difficulty: '普通' },
        q2: { subject: '算数', grade: 3, difficulty: '普通' },
        x9: { subject: '英語', grade: 1, difficulty: '簡単' },
    };
    const b = bankSummary({
        now: NOW,
        prompts,
        bank,
        archive,
        builderBatches: { bb1: { state: 'collected', submitted_at: 100, count: 300, questions: 1100, usd: 0.4 } },
        reviewBatches: {
            rb1: { state: 'collected', submitted_at: 200, count: 3, usd: 0.01 },
            rb2: { state: 'submitted', submitted_at: 300, count: 1 },
        },
        target: 2,
    });
    const cell = (s, g, d) => b.cells.find(c => c.subject === s && c.grade === g && c.difficulty === d);
    assert.deepEqual([cell('算数', 3, '普通').bank, cell('算数', 3, '普通').pending], [2, 0]);
    // エラーになったものは在庫に数えない
    assert.deepEqual([cell('算数', 3, '簡単').bank, cell('算数', 3, '簡単').pending], [0, 2]);
    assert.equal(cell('英語', 1, '簡単').planned, false);
    assert.equal(cell('英語', 1, '簡単').bank, 1);
    assert.deepEqual(b.totals, { bank: 3, plannedBuckets: 3, bucketsAtTarget: 1, emptyBuckets: 2, shortfall: 4 });
    assert.deepEqual(b.origins, { claude: 1, player: 1, unknown: 1 });
    assert.deepEqual(b.pending, { waiting: 1, inReview: 1, unsure: 0, errored: 1 });
    assert.equal(b.review.passRate, 0.5);
    assert.deepEqual(b.reviewBatches.map(x => [x.id, x.pass, x.fail, x.error]), [['rb2', 0, 0, 0], ['rb1', 1, 1, 1]]);
    assert.equal(b.builderBatches[0].questions, 1100);
    // 在庫と確認中の合計が少ない順。同じならバンクに入っている数が少ない方が先
    assert.deepEqual(b.lowest.map(c => `${c.subject}${c.grade}${c.difficulty}`), ['国語1簡単', '算数3簡単', '算数3普通']);
});

test('jobs: last run state and the scheduler entry that runs each job', () => {
    const jobs = jobsSummary({
        jobs: [{ name: 'quiz-bank-builder', label: '補充' }, { name: 'quiz-claude-review', label: '判定' }],
        executions: {
            'quiz-bank-builder': [
                { name: 'x/e2', startTime: 't2' },
                { name: 'x/e1', startTime: 't1', completionTime: 't1b', succeededCount: 1 },
            ],
            'quiz-claude-review': [{ name: 'x/e3', startTime: 't3', completionTime: 't3b', failedCount: 1 }],
        },
        schedulers: [
            { schedule: '0 3 * * *', timeZone: 'Asia/Tokyo', state: 'ENABLED', scheduleTime: 'next',
                httpTarget: { uri: 'https://run.googleapis.com/v2/.../jobs/quiz-bank-builder:run' } },
        ],
    });
    assert.equal(jobs[0].lastRun.state, 'running');
    assert.equal(jobs[0].recent[1].state, 'succeeded');
    assert.equal(jobs[0].nextRunAt, 'next');
    assert.equal(jobs[0].lastAttemptOk, null);
    assert.equal(jobs[1].lastRun.state, 'failed');
    assert.equal(jobs[1].schedule, null);
});
