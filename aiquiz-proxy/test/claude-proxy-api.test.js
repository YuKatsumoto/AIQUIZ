const test = require('node:test');
const assert = require('node:assert/strict');

process.env.APP_SECRET = 'test-app-secret';
delete process.env.FIREBASE_DB_URL;
delete process.env.DEVICE_TOKEN_KEY;
const { app, budget, useAnthropicClient } = require('../index');
const { apiError, fakeAnthropic } = require('./fake-anthropic');

const HEADERS = { 'Content-Type': 'application/json', 'X-App-Secret': 'test-app-secret' };
const generateBody = JSON.stringify({ task: 'generate', prompt: '問題をつくって', system: 'ベテラン教員' });

async function withProxy(reply, callback) {
    const client = fakeAnthropic(reply);
    useAnthropicClient(client);
    const proxy = app.listen(0, '127.0.0.1');
    await new Promise(resolve => proxy.once('listening', resolve));
    try {
        await callback(`http://127.0.0.1:${proxy.address().port}`, client);
    } finally {
        await new Promise(resolve => proxy.close(resolve));
    }
}

function sseEvents(text) {
    return text.split('\n').filter(line => line.startsWith('data: ')).map(line => JSON.parse(line.slice(6)));
}

test('/claude returns the text and counts the cost against the Claude budget', async () => {
    await withProxy({ text: '[{"q":"1+1は？"}]' }, async (base, client) => {
        const before = budget.totals().dailyUsd;
        const response = await fetch(`${base}/claude`, { method: 'POST', headers: HEADERS, body: generateBody });
        assert.equal(response.status, 200);
        const json = await response.json();
        assert.equal(json.text, '[{"q":"1+1は？"}]');
        assert.equal(json.stop_reason, 'end_turn');
        assert.equal(client.calls.length, 1);
        assert.equal(client.calls[0].params.model, 'claude-sonnet-5-5');
        assert.ok(budget.totals().dailyUsd > before);
    });
});

test('/claude unwraps structured output items for validate', async () => {
    await withProxy({ text: '{"items":[{"id":0,"correct_answer":1,"claimed_ok":true,"grade_ok":true,"issue":""}]}' },
        async base => {
            const response = await fetch(`${base}/claude`, { method: 'POST', headers: HEADERS,
                body: JSON.stringify({ task: 'validate', prompt: '検証して' }) });
            const json = await response.json();
            assert.deepEqual(JSON.parse(json.text), [{ id: 0, correct_answer: 1, claimed_ok: true, grade_ok: true, issue: '' }]);
        });
});

test('/claude-stream sends only text deltas, then done', async () => {
    await withProxy({ pieces: ['[{"q":', '"a"}]'], text: '[{"q":"a"}]' }, async (base, client) => {
        const response = await fetch(`${base}/claude-stream`, { method: 'POST', headers: HEADERS, body: generateBody });
        assert.equal(response.status, 200);
        assert.match(response.headers.get('content-type'), /text\/event-stream/);
        const events = sseEvents(await response.text());
        assert.deepEqual(events.map(e => e.type), ['text', 'text', 'done']);
        assert.equal(events.filter(e => e.type === 'text').map(e => e.text).join(''), '[{"q":"a"}]');
        assert.equal(client.calls[0].kind, 'stream');
    });
});

test('a refusal is 422 on /claude and an error event on /claude-stream', async () => {
    await withProxy({ stop_reason: 'refusal', text: '' }, async base => {
        const plain = await fetch(`${base}/claude`, { method: 'POST', headers: HEADERS, body: generateBody });
        assert.equal(plain.status, 422);
        const streamed = await fetch(`${base}/claude-stream`, { method: 'POST', headers: HEADERS, body: generateBody });
        const events = sseEvents(await streamed.text());
        assert.equal(events.at(-1).type, 'error');
    });
});

test('Anthropic 429 stays 429 and overload or 5xx becomes 503, before any stream starts', async () => {
    for (const [status, expected] of [[429, 429], [529, 503], [500, 503], [400, 502]]) {
        await withProxy({ error: apiError(status) }, async base => {
            for (const path of ['claude', 'claude-stream']) {
                const response = await fetch(`${base}/${path}`, { method: 'POST', headers: HEADERS, body: generateBody });
                assert.equal(response.status, expected, `${path} ${status}`);
                await response.text();
            }
        });
    }
});

test('a failure after text has started ends the stream with an error event', async () => {
    await withProxy({ pieces: ['[{"q":"a"}'], errorAfterText: apiError(529) }, async base => {
        const response = await fetch(`${base}/claude-stream`, { method: 'POST', headers: HEADERS, body: generateBody });
        assert.equal(response.status, 200);
        const events = sseEvents(await response.text());
        assert.deepEqual(events.map(e => e.type), ['text', 'error']);
    });
});

test('bad bodies, oversized bodies and missing secrets never reach Claude; the Gemini routes are gone', async () => {
    await withProxy({}, async (base, client) => {
        for (const body of [JSON.stringify({ task: 'chat', prompt: 'p' }), JSON.stringify({ task: 'generate', prompt: 'p', model: 'x' })]) {
            const response = await fetch(`${base}/claude`, { method: 'POST', headers: HEADERS, body });
            assert.equal(response.status, 400);
        }
        const tooLarge = await fetch(`${base}/claude`, { method: 'POST', headers: HEADERS, body: 'x'.repeat(70 * 1024) });
        assert.equal(tooLarge.status, 413);
        const noSecret = await fetch(`${base}/claude`, { method: 'POST',
            headers: { 'Content-Type': 'application/json' }, body: generateBody });
        assert.equal(noSecret.status, 403);
        for (const path of ['gemini?model=gemini-3.6-flash', 'gemini-stream?model=gemini-3.6-flash', 'openai']) {
            const gone = await fetch(`${base}/${path}`, { method: 'POST', headers: HEADERS, body: '{}' });
            assert.equal(gone.status, 404, path);
        }
        assert.equal(client.calls.length, 0);
    });
});

test('/health names the provider and over the daily budget the proxy answers 503 without calling Claude', async () => {
    await withProxy({}, async (base, client) => {
        const health = await (await fetch(`${base}/health`, { headers: HEADERS })).json();
        assert.equal(health.provider, 'claude');
        assert.equal(health.budget.monthly_budget_usd, 40);
        const saved = budget.dailyBudgetUsd;
        budget.record('claude-sonnet-5-5', {}, 0.01);
        budget.dailyBudgetUsd = budget.totals().dailyUsd;
        try {
            for (const path of ['claude', 'claude-stream']) {
                const response = await fetch(`${base}/${path}`, { method: 'POST', headers: HEADERS, body: generateBody });
                assert.equal(response.status, 503, path);
                assert.equal((await response.json()).error, 'daily_budget');
            }
            assert.equal(client.calls.length, 0);
        } finally {
            budget.dailyBudgetUsd = saved;
        }
    });
});
