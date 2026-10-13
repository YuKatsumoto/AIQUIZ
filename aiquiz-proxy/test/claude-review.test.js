const test = require('node:test');
const assert = require('node:assert/strict');

const {
    ClaudeReviewJob,
    buildRequest,
    contentHash,
    costUsd,
    parseVerdict,
} = require('../claude-review');
const { canonicalizeQuiz, mergeCandidate } = require('../quiz-bank-service');

// ---- Realtime Database の最小限の偽物（once / set / update / remove / transaction / orderByChild） ----
class FakeDb {
    constructor(data = {}) { this.data = data; }
    _get(path) {
        return path.split('/').reduce((node, key) => (node == null ? undefined : node[key]), this.data);
    }
    _set(path, value) {
        const keys = path.split('/');
        let node = this.data;
        for (const key of keys.slice(0, -1)) node = node[key] ??= {};
        if (value === null || value === undefined) delete node[keys.at(-1)];
        else node[keys.at(-1)] = structuredClone(value);
    }
    ref(path) {
        const db = this;
        const snap = value => ({ val: () => (value === undefined ? null : structuredClone(value)) });
        const query = { child: null, equal: undefined, limit: Infinity };
        const ref = {
            once: async () => {
                let value = db._get(path);
                if (query.child && value) {
                    value = Object.fromEntries(Object.entries(value)
                        .filter(([, item]) => item && item[query.child] === query.equal)
                        .slice(0, query.limit));
                }
                return snap(value);
            },
            set: async value => db._set(path, value),
            update: async value => db._set(path, { ...(db._get(path) || {}), ...value }),
            remove: async () => db._set(path, null),
            transaction: async fn => {
                const next = fn(db._get(path) === undefined ? null : structuredClone(db._get(path)));
                if (next !== undefined) db._set(path, next);
                return { snapshot: snap(db._get(path)) };
            },
            orderByChild: child => { query.child = child; return ref; },
            equalTo: value => { query.equal = value; return ref; },
            limitToFirst: n => { query.limit = n; return ref; },
        };
        return ref;
    }
}

class FakeAnthropic {
    constructor() {
        this.created = [];
        this.answers = {};
        const self = this;
        this.messages = {
            batches: {
                create: async ({ requests }) => {
                    self.created.push(requests);
                    return { id: `msgbatch_${self.created.length}` };
                },
                retrieve: async id => ({ id, processing_status: 'ended' }),
                results: async id => {
                    const requests = self.created[Number(id.split('_')[1]) - 1];
                    return (async function* () {
                        for (const request of requests) {
                            const answer = self.answers[request.custom_id];
                            if (answer === 'expired') {
                                yield { custom_id: request.custom_id, result: { type: 'expired' } };
                                continue;
                            }
                            yield {
                                custom_id: request.custom_id,
                                result: {
                                    type: 'succeeded',
                                    message: {
                                        stop_reason: 'end_turn',
                                        content: [{ type: 'text', text: JSON.stringify(answer) }],
                                        usage: { input_tokens: 800, output_tokens: 400 },
                                    },
                                },
                            };
                        }
                    })();
                },
            },
        };
    }
}

function archived(overrides = {}) {
    const quiz = canonicalizeQuiz({
        q: '3 + 4 は？', c: ['5', '7', '8', '9'], a: 1, e: '3と4を足します。',
        subject: '算数', grade: 1, difficulty: '普通', src: 'GEMINI', ...overrides,
    });
    return [quiz.id, mergeCandidate(null, quiz, 100)];
}

const CONFIG = {
    model: 'claude-opus-5-5', effort: 'medium', maxPerRun: 10, monthlyBudgetUsd: 5,
    estimatedUsdPerItem: 0.01, includeUnreviewedGood: false, dryRun: false,
};
const NOW = () => new Date('2026-10-13T00:00:00Z');

test('the request hides the answer and the explanation', () => {
    const [id, item] = archived();
    const request = buildRequest(id, item, CONFIG);
    const sent = request.params.messages[0].content;
    assert.equal(request.custom_id, id);
    assert.ok(!sent.includes('"a"') && !sent.includes('足します'));
    assert.equal(request.params.output_config.format.type, 'json_schema');
    assert.equal(request.params.output_config.effort, 'medium');
});

test('verdicts: matching answer passes, mismatch or issues fail, low confidence is unsure', () => {
    const [, item] = archived();
    const msg = out => ({ stop_reason: 'end_turn', content: [{ type: 'text', text: JSON.stringify(out) }] });
    const base = { answer: 1, issues: [], confidence: 'high', note: '' };
    assert.equal(parseVerdict(msg(base), item).verdict, 'pass');
    assert.equal(parseVerdict(msg({ ...base, answer: 2 }), item).verdict, 'fail');
    assert.equal(parseVerdict(msg({ ...base, issues: ['multiple_correct'] }), item).verdict, 'fail');
    assert.equal(parseVerdict(msg({ ...base, confidence: 'low' }), item).verdict, 'unsure');
    assert.equal(parseVerdict(msg({ ...base, answer: 7 }), item), null);
    assert.equal(parseVerdict({ stop_reason: 'refusal', content: [] }, item), null);
});

test('batch pricing is half the standard rate', () => {
    // Opus 5.5: $4 / $20 per MTok → Batch $2 / $10
    assert.equal(Number(costUsd('claude-opus-5-5', { input_tokens: 1e6, output_tokens: 1e6 }).toFixed(2)), 12);
});

test('a full cycle promotes only the questions Claude confirms', async () => {
    const [goodId, goodItem] = archived();
    const [badId, badItem] = archived({ q: '日本の首都は？', c: ['大阪', '東京'], a: 0, subject: '社会', grade: 3 });
    const [lostId, lostItem] = archived({ q: '1 + 1 は？', c: ['2', '3'], a: 0 });
    const db = new FakeDb({ quiz_archive: { v1: { items: {
        [goodId]: goodItem, [badId]: badItem, [lostId]: lostItem,
    } } } });
    const anthropic = new FakeAnthropic();
    const job = new ClaudeReviewJob({ db, anthropic, config: CONFIG, now: NOW, log: () => {} });

    const first = await job.run();
    assert.equal(first.submitted.count, 3);
    assert.equal(db._get(`quiz_archive/v1/items/${goodId}/review/state`), 'submitted');
    // 確認に出した後はクライアントが内容を書き換えられない
    const frozen = mergeCandidate(db._get(`quiz_archive/v1/items/${goodId}`),
        canonicalizeQuiz({ ...goodItem, src: 'GEMINI', a: 3 }), 120);
    assert.equal(frozen.a, 1);

    anthropic.answers[goodId] = { answer: 1, issues: [], confidence: 'high', note: '7' };
    anthropic.answers[badId] = { answer: 1, issues: [], confidence: 'high', note: '東京' };
    anthropic.answers[lostId] = 'expired';
    const second = await job.run();
    assert.deepEqual(
        { pass: second.collected.pass, fail: second.collected.fail, error: second.collected.error },
        { pass: 1, fail: 1, error: 1 },
    );
    assert.equal(db._get(`quiz_archive/v1/items/${goodId}/status`), 'good');
    assert.equal(db._get(`quiz_bank/v1/items/${goodId}/src`), 'OFFLINE_FIREBASE');
    assert.equal(db._get(`quiz_archive/v1/items/${badId}/status`), 'bad');
    assert.equal(db._get(`quiz_bank/v1/items/${badId}`), undefined);
    assert.equal(db._get('quiz_bank/v1/meta/revision'), 1);
    assert.ok(db._get('quiz_review/v1/spend/2026-10/usd') > 0);
    // 期限切れは再送される（2回目の送信に含まれる）
    assert.equal(second.submitted.count, 1);
    assert.equal(anthropic.created[1][0].custom_id, lostId);
});

test('the monthly budget stops new submissions', async () => {
    const [id, item] = archived();
    const db = new FakeDb({
        quiz_archive: { v1: { items: { [id]: item } } },
        quiz_review: { v1: { spend: { '2026-10': { usd: 4.995 } } } },
    });
    const anthropic = new FakeAnthropic();
    const job = new ClaudeReviewJob({ db, anthropic, config: CONFIG, now: NOW, log: () => {} });
    const result = await job.submit();
    assert.equal(result.skipped, 'budget');
    assert.equal(anthropic.created.length, 0);
});

test('a question whose content changed after submission is not judged on the old text', async () => {
    const [id, item] = archived();
    const db = new FakeDb({ quiz_archive: { v1: { items: { [id]: item } } } });
    const anthropic = new FakeAnthropic();
    const job = new ClaudeReviewJob({ db, anthropic, config: CONFIG, now: NOW, log: () => {} });
    await job.submit();
    db._set(`quiz_archive/v1/items/${id}/a`, 2);
    assert.notEqual(contentHash(db._get(`quiz_archive/v1/items/${id}`)), contentHash(item));
    anthropic.answers[id] = { answer: 2, issues: [], confidence: 'high', note: '' };
    const summary = await job.collect();
    assert.equal(summary.error, 1);
    assert.equal(db._get(`quiz_archive/v1/items/${id}/status`), 'pending');
});
