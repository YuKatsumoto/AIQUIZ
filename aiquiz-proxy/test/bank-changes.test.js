const test = require('node:test');
const assert = require('node:assert/strict');
const { FirebaseQuizBankService, putBankItem, removeBankItem } = require('../quiz-bank-service');

// Realtime Database のうち、差分同期で使う並べ替えと範囲指定だけを真似る
function fakeDatabase() {
    const root = {};
    const get = path => path.split('/').reduce((n, k) => (n == null ? undefined : n[k]), root);
    const set = (path, value) => {
        const keys = path.split('/');
        let n = root;
        for (const k of keys.slice(0, -1)) n = n[k] = n[k] || {};
        if (value === null) delete n[keys[keys.length - 1]];
        else n[keys[keys.length - 1]] = JSON.parse(JSON.stringify(value));
    };
    function snapshotOf(entries) {
        return {
            val: () => (entries.length ? Object.fromEntries(entries) : null),
            forEach(fn) { entries.forEach(([key, value]) => fn({ key, val: () => value })); },
        };
    }
    function query(path, by) {
        const state = { start: null, startKey: null, limit: Infinity };
        const q = {
            startAt(value, key) { state.start = value; state.startKey = key ?? null; return q; },
            limitToFirst(n) { state.limit = n; return q; },
            async once() {
                const all = Object.entries(get(path) || {});
                const sortValue = ([, v]) => (by === '.value' ? v : (v || {})[by]);
                let rows = all.filter(row => sortValue(row) != null)
                    .sort((a, b) => (sortValue(a) - sortValue(b)) || a[0].localeCompare(b[0]));
                if (state.start != null) {
                    rows = rows.filter(row => sortValue(row) > state.start
                        || (sortValue(row) === state.start && (state.startKey == null || row[0] >= state.startKey)));
                }
                return snapshotOf(rows.slice(0, state.limit));
            },
        };
        return q;
    }
    return {
        root,
        ref(path) {
            return {
                async set(value) { set(path, value); },
                async remove() { set(path, null); },
                async once() { return snapshotOf(Object.entries(get(path) || {})); },
                orderByChild(child) { return query(path, child); },
                orderByValue() { return query(path, '.value'); },
            };
        },
    };
}

function archive(q) {
    return { q, c: ['1', '2', '3', '4'], a: 0, e: '', subject: '算数', grade: 3, difficulty: '普通', last_evaluated: 1 };
}

test('changes return items written after the given time, in pages, plus removed ids', async () => {
    const db = fakeDatabase();
    const service = new FirebaseQuizBankService(() => db);
    for (let i = 0; i < 5; i++) await putBankItem(db, `id${i}`, archive(`問題${i}`), 1000 + i * 10);
    // two items share the same time: paging must not drop or repeat either
    await putBankItem(db, 'idA', archive('問題A'), 1030);
    await removeBankItem(db, 'id1', 1100);

    const page1 = await service.changes({ since: 1015, limit: 2 });
    assert.deepEqual(page1.items.map(i => i.id), ['id2', 'id3']);
    assert.deepEqual(page1.removed, ['id1']);
    assert.deepEqual(page1.next, { since: 1030, after_key: 'id3' });
    assert.equal(page1.sync_since, null);

    const page2 = await service.changes({ since: page1.next.since, afterKey: page1.next.after_key, limit: 2 });
    assert.deepEqual(page2.items.map(i => i.id), ['idA', 'id4']);
    assert.deepEqual(page2.removed, []);
    assert.equal(page2.next, null);
    assert.ok(page2.sync_since > 0 && page2.sync_since <= Date.now());
    assert.equal(page2.items[0].changed_at, 1030);
    assert.equal(page2.items[0].src, 'OFFLINE_FIREBASE');
});

test('putting an item back clears its removal and removing records the time', async () => {
    const db = fakeDatabase();
    const service = new FirebaseQuizBankService(() => db);
    await removeBankItem(db, 'x', 500);
    assert.equal(db.root.quiz_bank.v1.removed.x, 500);
    await putBankItem(db, 'x', archive('問題X'), 600);
    assert.equal(db.root.quiz_bank.v1.removed.x, undefined);
    const all = await service.changes({ since: 0 });
    assert.deepEqual(all.items.map(i => i.id), ['x']);
    assert.deepEqual(all.removed, []);
});
