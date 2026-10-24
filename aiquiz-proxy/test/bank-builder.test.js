const test = require('node:test');
const assert = require('node:assert/strict');
const { BankBuilderJob, parseQuestions } = require('../bank-builder');
const { questionId } = require('../quiz-bank-service');

// パスで値を持つだけの Realtime Database の代わり
function fakeDatabase(initial = {}) {
    const root = JSON.parse(JSON.stringify(initial));
    const get = path => path.split('/').reduce((node, key) => (node == null ? undefined : node[key]), root);
    const set = (path, value) => {
        const keys = path.split('/');
        let node = root;
        for (const key of keys.slice(0, -1)) node = node[key] = node[key] || {};
        if (value === null) delete node[keys[keys.length - 1]];
        else node[keys[keys.length - 1]] = JSON.parse(JSON.stringify(value));
    };
    const ref = path => ({
        async once() {
            const value = get(path);
            return { val: () => (value === undefined ? null : JSON.parse(JSON.stringify(value))), exists: () => value !== undefined };
        },
        async set(value) { set(path, value); },
        async update(fields) { for (const [k, v] of Object.entries(fields)) set(`${path}/${k}`, v); },
        async transaction(fn) {
            const current = get(path);
            const next = fn(current === undefined ? null : JSON.parse(JSON.stringify(current)));
            if (next === undefined) return { committed: false };
            set(path, next);
            return { committed: true };
        },
        orderByChild(child) {
            return { equalTo(value) {
                return { async once() {
                    const all = get(path) || {};
                    const hit = Object.fromEntries(Object.entries(all).filter(([, item]) => item && item[child] === value));
                    return { val: () => hit };
                } };
            } };
        },
    });
    return { root, ref };
}

const PROMPTS = {
    version: 1,
    questions_per_prompt: 4,
    system: 'SYSTEM',
    prompts: [
        { subject: '算数', grade: 3, difficulty: '普通', units: ['わり算'], prompt: 'P-math-1' },
        { subject: '算数', grade: 3, difficulty: '普通', units: ['時こく'], prompt: 'P-math-2' },
        { subject: '国語', grade: 2, difficulty: '簡単', units: ['漢字'], prompt: 'P-ja-1' },
    ],
};

function config(overrides = {}) {
    return { model: 'claude-haiku-5-5', effort: 'medium', monthlyBudgetUsd: 15, maxCallsPerRun: 100,
        maxCallsPerBucket: 3, targetPerBucket: 10, estimatedUsdPerCall: 0.002, dryRun: false, ...overrides };
}

function bankItem(subject, grade, difficulty, q) {
    return { q, c: ['1', '2', '3', '4'], a: 0, subject, grade, difficulty };
}

test('questions are read from plain, fenced or wrapped JSON', () => {
    assert.equal(parseQuestions('[{"q":"a"}]').length, 1);
    assert.equal(parseQuestions('```json\n[{"q":"a"},{"q":"b"}]\n```').length, 2);
    assert.equal(parseQuestions('はい。\n[{"q":"a"}]\n以上').length, 1);
    assert.equal(parseQuestions('not json').length, 0);
});

test('submission goes to the buckets furthest from the target, with an avoid list', async () => {
    const items = {};
    for (let i = 0; i < 9; i++) items[`m${i}`] = bankItem('算数', 3, '普通', `算数の既存問題${i}`);
    const db = fakeDatabase({ quiz_bank: { v1: { items } } });
    const created = [];
    const anthropic = { messages: { batches: { async create(params) { created.push(params); return { id: 'msgbatch_1' }; } } } };
    const job = new BankBuilderJob({ db, anthropic, config: config(), prompts: PROMPTS, random: () => 0.5 });
    const summary = await job.submit();
    assert.equal(summary.batch_id, 'msgbatch_1');
    const requests = created[0].requests;
    // 国語2（0 問）は 3 回まで、算数3（9 問・目標 10）は 1 回
    const contents = requests.map(r => r.params.messages[0].content);
    assert.equal(contents.filter(c => c.startsWith('P-ja-1')).length, 3);
    assert.equal(contents.filter(c => c.startsWith('P-math')).length, 1);
    assert.ok(contents.find(c => c.startsWith('P-math')).includes('算数の既存問題'));
    assert.equal(requests[0].params.model, 'claude-haiku-5-5');
    assert.equal(requests[0].params.output_config.effort, 'medium');
    assert.equal(db.root.bank_builder.v1.batches.msgbatch_1.state, 'submitted');
    assert.equal(db.root.bank_builder.v1.batches.msgbatch_1.requests.r0.subject, '国語');
});

test('nothing is submitted when the budget or the targets do not allow it', async () => {
    const db = fakeDatabase({ bank_builder: { v1: { spend: { [new Date().toISOString().slice(0, 7)]: { usd: 15 } } } } });
    const job = new BankBuilderJob({ db, anthropic: null, config: config(), prompts: PROMPTS });
    assert.equal((await job.submit()).skipped, 'budget');
    const full = fakeDatabase();
    const jobFull = new BankBuilderJob({ db: full, anthropic: null, config: config({ targetPerBucket: 0 }), prompts: PROMPTS });
    assert.equal((await jobFull.submit()).skipped, 'targets_met');
});

test('collected questions enter the archive as pending; duplicates and broken ones are skipped', async () => {
    const existing = questionId('国語', 2, '「山」の読みは？');
    const db = fakeDatabase({
        quiz_archive: { v1: { items: { [existing]: { q: '「山」の読みは？', status: 'good', seen_count: 5 } } } },
        bank_builder: { v1: { batches: { msgbatch_1: { state: 'submitted', model: 'claude-haiku-5-5', count: 1,
            requests: { r0: { subject: '国語', grade: 2, difficulty: '簡単' } } } } } },
    });
    const generated = [
        { q: '「川」の読みは？', c: ['かわ', 'やま', 'もり', 'うみ'], a: 0, e: '川は「かわ」と読みます。', g: '漢字', t: 3 },
        { q: '「山」の読みは？', c: ['やま', 'かわ', 'そら', 'うみ'], a: 0, e: '', g: '漢字' },
        { q: '選択肢が足りない', c: ['a', 'b'], a: 0 },
        { q: '同じ選択肢', c: ['a', 'a', 'b', 'c'], a: 0 },
    ];
    const anthropic = { messages: { batches: {
        async retrieve() { return { processing_status: 'ended' }; },
        async results() {
            return (async function* () {
                yield { custom_id: 'r0', result: { type: 'succeeded', message: {
                    usage: { input_tokens: 4000, output_tokens: 4000 },
                    content: [{ type: 'thinking', thinking: '' }, { type: 'text', text: JSON.stringify(generated) }],
                } } };
            })();
        },
    } } };
    const job = new BankBuilderJob({ db, anthropic, config: config(), prompts: PROMPTS });
    const summary = await job.collect();
    assert.equal(summary.archived, 1);
    assert.equal(summary.duplicates, 1);
    assert.equal(summary.invalid, 2);
    const id = questionId('国語', 2, '「川」の読みは？');
    const item = db.root.quiz_archive.v1.items[id];
    assert.equal(item.status, 'pending');
    assert.equal(item.original_src, 'CLAUDE_HAIKU');
    assert.equal(item.e, '川は「かわ」と読みます。');
    // 既存の問題は書き換えない
    assert.equal(db.root.quiz_archive.v1.items[existing].seen_count, 5);
    assert.equal(db.root.bank_builder.v1.batches.msgbatch_1.state, 'collected');
    const spend = Object.values(db.root.bank_builder.v1.spend)[0];
    assert.ok(Math.abs(spend.usd - (4000 * 0.10 + 4000 * 0.50) / 1e6 * 0.5) < 1e-9);
    assert.equal(spend.questions, 1);
});

test('the bundled prompts cover every bucket the game offers', () => {
    const { loadPrompts } = require('../bank-builder');
    const prompts = loadPrompts();
    const buckets = new Set(prompts.prompts.map(p => `${p.subject}|${p.grade}|${p.difficulty}`));
    assert.equal(buckets.size, 84);
    assert.ok(prompts.system.length > 0);
});
