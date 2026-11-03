const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');

process.env.APP_SECRET = 'test-app-secret';
process.env.DEVICE_TOKEN_KEY = 'test-device-key';
process.env.DEVICE_POW_BITS = '8';
delete process.env.DEVICE_TOKEN_REQUIRED;
delete process.env.FIREBASE_DB_URL;
const { app, deviceLimits, useAnthropicClient } = require('../index');
const { leadingZeroBits } = require('../device-auth');
const { fakeAnthropic } = require('./fake-anthropic');

const HEADERS = { 'Content-Type': 'application/json', 'X-App-Secret': 'test-app-secret' };
const IID = 'abcdefabcdefabcdefabcdefabcdef01';
const gameBody = JSON.stringify({ task: 'generate', prompt: 'prompt' });

async function withServers(callback) {
    const client = fakeAnthropic();
    useAnthropicClient(client);
    const proxy = app.listen(0, '127.0.0.1');
    await new Promise(resolve => proxy.once('listening', resolve));
    try {
        await callback(`http://127.0.0.1:${proxy.address().port}`, client.calls);
    } finally {
        await new Promise(resolve => proxy.close(resolve));
    }
}

async function getToken(base, iid = IID) {
    const challenge = await (await fetch(`${base}/session/challenge`, { headers: HEADERS })).json();
    let counter = 0;
    while (leadingZeroBits(crypto.createHash('sha256')
        .update(`${challenge.challenge}:${iid}:${counter}`).digest()) < challenge.bits) counter++;
    const response = await fetch(`${base}/session`, { method: 'POST', headers: HEADERS,
        body: JSON.stringify({ iid, challenge: challenge.challenge, counter: String(counter) }) });
    assert.equal(response.status, 200);
    return (await response.json()).token;
}

test('the session flow issues a token that unlocks Claude; no or bad tokens get 401', async () => {
    await withServers(async (base, received) => {
        const token = await getToken(base);
        const ok = await fetch(`${base}/claude`, { method: 'POST',
            headers: { ...HEADERS, 'X-Device-Token': token }, body: gameBody });
        assert.equal(ok.status, 200);
        await ok.text();
        for (const headers of [HEADERS, { ...HEADERS, 'X-Device-Token': token.slice(0, -2) + 'xx' }]) {
            const refused = await fetch(`${base}/claude`, { method: 'POST', headers, body: gameBody });
            assert.equal(refused.status, 401);
            assert.equal((await refused.json()).error, 'device_token');
        }
        assert.equal(received.length, 1);
        assert.ok(deviceLimits.denials.pending.get('device_token').usd >= 2);
    });
});

test('a wrong proof of work and a missing app secret are refused', async () => {
    await withServers(async base => {
        const challenge = await (await fetch(`${base}/session/challenge`, { headers: HEADERS })).json();
        const bad = await fetch(`${base}/session`, { method: 'POST', headers: HEADERS,
            body: JSON.stringify({ iid: IID, challenge: challenge.challenge, counter: '0'.repeat(1) + 'x' }) });
        assert.equal(bad.status, 400);
        assert.equal((await fetch(`${base}/session/challenge`)).status, 403);
    });
});

test('a device over its daily amount gets 503 and Claude is not called', async () => {
    await withServers(async (base, received) => {
        const iid = 'abcdefabcdefabcdefabcdefabcdef02';
        const token = await getToken(base, iid);
        deviceLimits.record({ iid, ipKey: '' }, 1.0);
        const response = await fetch(`${base}/claude-stream`, { method: 'POST',
            headers: { ...HEADERS, 'X-Device-Token': token }, body: gameBody });
        assert.equal(response.status, 503);
        assert.equal((await response.json()).error, 'device_daily_budget');
        assert.ok(Number(response.headers.get('retry-after')) > 0);
        assert.equal(received.length, 0);
        // 管理ソフトの「止めた回数」に入る
        assert.ok(deviceLimits.denials.pending.get('device_daily_budget').usd >= 1);
    });
});

test('Claude usage is counted against the device that made the request', async () => {
    await withServers(async base => {
        const iid = 'abcdefabcdefabcdefabcdefabcdef03';
        const token = await getToken(base, iid);
        const before = await deviceLimits.devices.spent(iid);
        const response = await fetch(`${base}/claude`, { method: 'POST',
            headers: { ...HEADERS, 'X-Device-Token': token }, body: gameBody });
        await response.text();
        assert.ok(await deviceLimits.devices.spent(iid) > before);
    });
});
