const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createApp } = require('../server');
const { ActionError } = require('../lib/actions');

function request(port, path, { host = `127.0.0.1:${port}`, method = 'GET', headers = {}, body = null } = {}) {
    return new Promise((resolve, reject) => {
        const req = http.request({ host: '127.0.0.1', port, path, method, headers: { host, ...headers } }, res => {
            let text = '';
            res.on('data', chunk => { text += chunk; });
            res.on('end', () => resolve({ status: res.statusCode, body: text }));
        });
        req.on('error', reject);
        if (body !== null) req.write(body);
        req.end();
    });
}

async function withServer(sources, actions, fn) {
    const server = createApp(sources, actions).listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    try {
        await fn(server.address().port);
    } finally {
        server.close();
    }
}

test('serves the summaries, passes refresh through, and only answers to localhost', async () => {
    const calls = [];
    const sources = {
        overview: async () => ({ revision: 'r1' }),
        money: async () => ({ day: '2026-10-18' }),
        players: async () => { throw new Error('db down'); },
        bank: async opts => { calls.push(opts); return { totals: {} }; },
        jobs: async () => [],
        searchQuestions: async opts => { calls.push(opts); return { total: 0, items: [] }; },
    };
    await withServer(sources, {}, async port => {
        assert.equal(JSON.parse((await request(port, '/api/money')).body).day, '2026-10-18');
        await request(port, '/api/bank?refresh=1');
        await request(port, '/api/bank');
        await request(port, `/api/questions?text=${encodeURIComponent('分数')}&removed=1`);
        assert.deepEqual(calls.slice(0, 2), [{ refresh: true }, { refresh: false }]);
        assert.equal(calls[2].text, '分数');
        assert.equal(calls[2].removed, true);

        const failed = await request(port, '/api/players');
        assert.equal(failed.status, 500);
        assert.equal(JSON.parse(failed.body).error, 'db down');

        const page = await request(port, '/', { host: `localhost:${port}` });
        assert.equal(page.status, 200);
        assert.match(page.body, /AIQUIZ 運用/);

        // 別の名前で届いたもの（DNS リバインディングなど）は断る
        assert.equal((await request(port, '/api/money', { host: 'evil.example:80' })).status, 403);
    });
});

test('operations need the page header, a local origin and JSON; errors keep their status', async () => {
    const done = [];
    const actions = {
        block: async body => { done.push(body); return { ok: true }; },
        unblock: async () => { throw new ActionError('ブロックしていません', 404); },
    };
    await withServer({}, actions, async port => {
        const json = { 'Content-Type': 'application/json' };
        const body = JSON.stringify({ kind: 'device', key: 'k' });
        const post = (path, headers) => request(port, path, { method: 'POST', headers, body });

        assert.equal((await post('/api/actions/block', json)).status, 403);
        assert.equal((await post('/api/actions/block', { ...json, 'X-Ops-Request': '1', Origin: 'https://evil.example' })).status, 403);
        assert.equal(done.length, 0);

        const ok = await post('/api/actions/block', { ...json, 'X-Ops-Request': '1', Origin: `http://localhost:${port}` });
        assert.equal(ok.status, 200);
        assert.deepEqual(done, [{ kind: 'device', key: 'k' }]);

        const missing = await post('/api/actions/unblock', { ...json, 'X-Ops-Request': '1' });
        assert.equal(missing.status, 404);
        assert.equal(JSON.parse(missing.body).error, 'ブロックしていません');

        // 書き換えは GET では受け付けない
        assert.equal((await request(port, '/api/actions/block')).status, 404);
    });
});
