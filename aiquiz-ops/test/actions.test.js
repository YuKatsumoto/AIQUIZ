const test = require('node:test');
const assert = require('node:assert/strict');
const { OpsActions } = require('../lib/actions');

const NOW = new Date('2026-10-18T03:00:00Z');
const IID = '0123456789abcdef0123456789abcdef';
const QID = 'a'.repeat(64);

// Realtime Database のうち、操作で使うところだけを真似る
function fakeDatabase(initial = {}) {
    const root = JSON.parse(JSON.stringify(initial));
    let pushes = 0;
    const get = p => p.split('/').reduce((n, k) => (n == null ? undefined : n[k]), root);
    const set = (p, v) => {
        const keys = p.split('/');
        let n = root;
        for (const k of keys.slice(0, -1)) n = n[k] = n[k] || {};
        if (v === null || v === undefined) delete n[keys[keys.length - 1]];
        else n[keys[keys.length - 1]] = JSON.parse(JSON.stringify(v));
    };
    const snap = v => ({ val: () => (v === undefined ? null : JSON.parse(JSON.stringify(v))) });
    return {
        root,
        ref(p) {
            return {
                async once() { return snap(get(p)); },
                async set(v) { set(p, v); },
                async remove() { set(p, null); },
                async push(v) { pushes += 1; set(`${p}/k${String(pushes).padStart(4, '0')}`, v); },
                async transaction(fn) {
                    const next = fn(get(p) === undefined ? null : JSON.parse(JSON.stringify(get(p))));
                    if (next !== undefined) set(p, next);
                    return { committed: next !== undefined, snapshot: snap(get(p)) };
                },
                orderByKey() {
                    return { limitToLast(n) { return { async once() {
                        const entries = Object.entries(get(p) || {}).sort(([a], [b]) => a.localeCompare(b)).slice(-n);
                        return snap(Object.fromEntries(entries));
                    } }; } };
                },
            };
        },
    };
}

function actions(db, extra = {}) {
    return new OpsActions({
        db,
        now: () => NOW,
        actor: 'tester@pc',
        jobs: [{ name: 'quiz-bank-builder', label: '補充' }],
        runUrl: p => `https://run/${p}`,
        gcpRequest: async () => { throw new Error('not expected'); },
        ...extra,
    });
}

test('block and unblock devices and lines, with checks and a log entry each', async () => {
    const db = fakeDatabase();
    const a = actions(db);
    await a.block({ kind: 'device', key: IID, reason: '連打' });
    assert.deepEqual(db.root.device_blocklist.v1[IID],
        { kind: 'device', reason: '連打', at: NOW.getTime() / 1000, by: 'tester@pc' });
    await a.block({ kind: 'ip', key: 'fJCicjuEcwuyAOpz6hBddp' });
    await assert.rejects(a.block({ kind: 'device', key: IID }), { status: 409 });
    await assert.rejects(a.block({ kind: 'device', key: 'not-a-device' }), { status: 400 });
    await assert.rejects(a.block({ kind: 'ip', key: IID.slice(0, 4) }), { status: 400 });
    await assert.rejects(a.block({ kind: 'other', key: IID }), { status: 400 });

    await a.unblock({ key: IID });
    assert.equal(db.root.device_blocklist.v1[IID], undefined);
    await assert.rejects(a.unblock({ key: IID }), { status: 404 });

    const log = await a.recentLog();
    assert.deepEqual(log.map(l => [l.action, l.target]), [
        ['unblock', IID], ['block', 'fJCicjuEcwuyAOpz6hBddp'], ['block', IID],
    ]);
    assert.equal(log[2].reason, '連打');
});

test('removing a question takes it out of the bank for good, and restoring puts it back as before', async () => {
    const archive = { q: '3+4は？', c: ['7', '6', '8', '9'], a: 0, e: '足し算', subject: '算数', grade: 1,
        difficulty: '簡単', status: 'good', bad_ever: false, evaluation_reason: 'claude: pass', original_src: 'GEMINI' };
    const db = fakeDatabase({
        quiz_bank: { v1: { items: { [QID]: { ...archive, src: 'OFFLINE_FIREBASE', changed_at: 1 } }, meta: { revision: 5 } } },
        quiz_archive: { v1: { items: { [QID]: archive } } },
    });
    const changes = [];
    const a = actions(db, { onBankChange: c => changes.push(c.type) });

    await a.removeQuestion({ id: QID, reason: '答えが二つある' });
    assert.equal(db.root.quiz_bank.v1.items[QID], undefined);
    assert.equal(db.root.quiz_bank.v1.removed[QID], NOW.getTime());
    assert.equal(db.root.quiz_bank.v1.meta.revision, 6);
    const removed = db.root.quiz_archive.v1.items[QID];
    assert.equal(removed.status, 'bad');
    assert.equal(removed.bad_ever, true);
    assert.equal(removed.ops_removed.reason, '答えが二つある');
    assert.equal(removed.ops_removed.prev_status, 'good');
    await assert.rejects(a.removeQuestion({ id: QID }), { status: 404 });

    await a.restoreQuestion({ id: QID });
    const restored = db.root.quiz_archive.v1.items[QID];
    assert.equal(restored.status, 'good');
    assert.equal(restored.bad_ever, false);
    assert.equal(restored.evaluation_reason, 'claude: pass');
    assert.equal(restored.ops_removed, undefined);
    assert.equal(db.root.quiz_bank.v1.items[QID].q, '3+4は？');
    assert.equal(db.root.quiz_bank.v1.items[QID].changed_at, NOW.getTime());
    assert.equal(db.root.quiz_bank.v1.removed[QID], undefined);
    assert.equal(db.root.quiz_bank.v1.meta.revision, 7);
    assert.deepEqual(changes, ['removed', 'restored']);
    // 管理ソフトで外していない問題は戻せない
    await assert.rejects(a.restoreQuestion({ id: QID }), { status: 404 });
    await assert.rejects(a.removeQuestion({ id: 'bad/id' }), { status: 400 });
});

test('running a job calls the Cloud Run run API only for known jobs', async () => {
    const db = fakeDatabase();
    const calls = [];
    const a = actions(db, {
        gcpRequest: async (url, options) => {
            calls.push([url, options.method]);
            return { name: 'operations/x', metadata: { name: 'projects/p/locations/l/jobs/quiz-bank-builder/executions/quiz-bank-builder-abc' } };
        },
    });
    const result = await a.runJob({ name: 'quiz-bank-builder' });
    assert.deepEqual(result, { name: 'quiz-bank-builder', execution: 'quiz-bank-builder-abc' });
    assert.deepEqual(calls, [['https://run/jobs/quiz-bank-builder:run', 'POST']]);
    await assert.rejects(a.runJob({ name: 'other' }), { status: 400 });
    assert.equal((await a.recentLog())[0].execution, 'quiz-bank-builder-abc');
});
