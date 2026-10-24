const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

process.env.APP_SECRET = 'test-app-secret';
delete process.env.FIREBASE_DB_URL;
const { app, budget } = require('../index');

const HEADERS = { 'Content-Type': 'application/json', 'X-App-Secret': 'test-app-secret' };
const USAGE = { promptTokenCount: 2000, candidatesTokenCount: 300, thoughtsTokenCount: 100 };

// 偽の Gemini。受け取った本文を記録して usageMetadata 付きで返す。
async function withServers(callback) {
    const received = [];
    const gemini = http.createServer((req, res) => {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            received.push({ url: req.url, body: JSON.parse(body) });
            const payload = { candidates: [{ content: { parts: [{ text: '[]' }] } }], usageMetadata: USAGE };
            if (req.url.includes('streamGenerateContent')) {
                res.writeHead(200, { 'Content-Type': 'text/event-stream' });
                res.end(`data: ${JSON.stringify(payload)}\n\n`);
            } else {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(payload));
            }
        });
    });
    await new Promise(resolve => gemini.listen(0, '127.0.0.1', resolve));
    process.env.GEMINI_API_BASE = `http://127.0.0.1:${gemini.address().port}`;
    const proxy = app.listen(0, '127.0.0.1');
    await new Promise(resolve => proxy.once('listening', resolve));
    try {
        await callback(`http://127.0.0.1:${proxy.address().port}`, received);
    } finally {
        await new Promise(resolve => proxy.close(resolve));
        await new Promise(resolve => gemini.close(resolve));
    }
}

const gameBody = JSON.stringify({
    systemInstruction: { parts: [{ text: 'sys' }] },
    contents: [{ parts: [{ text: 'prompt' }] }],
    generationConfig: { responseMimeType: 'application/json', thinkingConfig: { thinkingLevel: 'low' } },
});

test('allowed requests reach Gemini with the output cap applied, and their cost is counted', async () => {
    await withServers(async (base, received) => {
        const before = budget.totals().dailyUsd;
        for (const path of ['gemini', 'gemini-stream']) {
            const response = await fetch(`${base}/${path}?model=gemini-3.6-flash`, {
                method: 'POST', headers: HEADERS, body: gameBody });
            assert.equal(response.status, 200, path);
            await response.text();
        }
        assert.equal(received.length, 2);
        assert.match(received[0].url, /gemini-3\.6-flash:generateContent/);
        assert.match(received[1].url, /gemini-3\.6-flash:streamGenerateContent\?alt=sse/);
        assert.equal(received[0].body.generationConfig.maxOutputTokens, 4096);
        assert.ok(budget.totals().dailyUsd > before);
    });
});

test('other models and request shapes never reach Gemini', async () => {
    await withServers(async (base, received) => {
        const bad = [
            ['gemini-4-argon', gameBody],
            ['gemini-3.6-flash', JSON.stringify({ contents: [{ parts: [{ text: 'x' }] }], tools: [{ googleSearch: {} }] })],
        ];
        for (const [model, body] of bad) {
            const response = await fetch(`${base}/gemini?model=${model}`, { method: 'POST', headers: HEADERS, body });
            assert.equal(response.status, 400, model);
        }
        const tooLarge = await fetch(`${base}/gemini?model=gemini-3.6-flash`, {
            method: 'POST', headers: HEADERS, body: 'x'.repeat(70 * 1024) });
        assert.equal(tooLarge.status, 413);
        const noSecret = await fetch(`${base}/gemini?model=gemini-3.6-flash`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: gameBody });
        assert.equal(noSecret.status, 403);
        assert.equal(received.length, 0);
    });
});

test('the removed OpenAI relay is gone and /health answers without calling Gemini', async () => {
    await withServers(async (base, received) => {
        const openai = await fetch(`${base}/openai`, { method: 'POST', headers: HEADERS,
            body: JSON.stringify({ messages: [] }) });
        assert.equal(openai.status, 404);
        const health = await fetch(`${base}/health`, { headers: HEADERS });
        assert.equal(health.status, 200);
        const json = await health.json();
        assert.equal(json.ok, true);
        assert.equal(typeof json.budget.daily_budget_usd, 'number');
        assert.equal((await fetch(`${base}/health`)).status, 403);
        assert.equal(received.length, 0);
    });
});

test('over the daily budget the proxy answers 503 daily_budget and does not call Gemini', async () => {
    await withServers(async (base, received) => {
        const saved = budget.dailyBudgetUsd;
        budget.record('gemini-3.6-flash', USAGE);
        budget.dailyBudgetUsd = budget.totals().dailyUsd; // 使った分で上限に達した状態
        try {
            for (const path of ['gemini', 'gemini-stream']) {
                const response = await fetch(`${base}/${path}?model=gemini-3.6-flash`, {
                    method: 'POST', headers: HEADERS, body: gameBody });
                assert.equal(response.status, 503, path);
                assert.equal((await response.json()).error, 'daily_budget');
                assert.ok(Number(response.headers.get('retry-after')) >= 60);
            }
            assert.equal(received.length, 0);
        } finally {
            budget.dailyBudgetUsd = saved;
        }
    });
});
