const test = require('node:test');
const assert = require('node:assert/strict');
const { DeviceLimits } = require('../device-limits');

const IID = '0123456789abcdef0123456789abcdef';
const quiet = { warn() {}, error() {} };
const NOW = new Date('2026-10-18T03:00:00Z');
const nowSec = Math.floor(NOW.getTime() / 1000);
const OLD_DEVICE = { iid: IID, issuedSec: nowSec - 3 * 24 * 3600, ipKey: 'ipA' };
const NEW_DEVICE = { iid: IID, issuedSec: nowSec - 3600, ipKey: 'ipA' };

function limits(overrides = {}) {
    return new DeviceLimits({ now: () => NOW, log: quiet, ...overrides });
}

test('a device stops at its daily amount and resumes the next day', async () => {
    let now = NOW;
    const l = limits({ now: () => now });
    for (let i = 0; i < 9; i++) l.record(OLD_DEVICE, 0.03);
    assert.equal((await l.check(OLD_DEVICE)).ok, true);
    l.record(OLD_DEVICE, 0.03);
    const verdict = await l.check(OLD_DEVICE);
    assert.equal(verdict.ok, false);
    assert.equal(verdict.status, 503);
    assert.equal(verdict.reason, 'device_daily_budget');
    assert.ok(verdict.retryAfterSec > 0);
    now = new Date('2026-10-18T15:30:00Z'); // 翌日の 0:30（日本時間）
    assert.equal((await l.check(OLD_DEVICE)).ok, true);
});

test('a token younger than a day has the lower first-day amount', async () => {
    const l = limits();
    for (let i = 0; i < 4; i++) l.record(NEW_DEVICE, 0.03);
    assert.equal((await l.check(NEW_DEVICE)).reason, 'device_daily_budget');
    // the same spend is fine for a device that has had its token for days
    assert.equal((await l.check({ ...OLD_DEVICE, iid: 'ffffffffffffffffffffffffffffffff' })).ok, true);
});

test('many devices on one network stop at the IP amount', async () => {
    const l = limits({ ipDailyUsd: 1 });
    for (let i = 0; i < 40; i++) {
        const iid = i.toString(16).padStart(32, '0');
        l.record({ iid, ipKey: 'school' }, 0.03);
    }
    const verdict = await l.check({ ...OLD_DEVICE, iid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', ipKey: 'school' });
    assert.equal(verdict.reason, 'ip_daily_budget');
    assert.equal((await l.check({ ...OLD_DEVICE, ipKey: 'home' })).ok, true);
});

function fakeDatabase(initial = {}) {
    const data = { ...initial };
    const valueOf = v => (v && v['.sv'] && v['.sv'].increment) ?? v;
    return {
        data,
        ref(path) {
            return {
                async update(fields) {
                    for (const [key, value] of Object.entries(fields)) {
                        data[`${path}/${key}`] = Number(data[`${path}/${key}`] || 0) + Number(valueOf(value));
                    }
                },
                async once() {
                    if (path === 'device_blocklist/v1') return { val: () => data.blocklist || null };
                    return { val: () => data[path] ?? null };
                },
            };
        },
    };
}

test('spend is shared through Firebase and the blocklist is honoured', async () => {
    const db = fakeDatabase({ blocklist: {
        ffffffffffffffffffffffffffffffff: true,
        badNet: { kind: 'ip', reason: 'test', at: 1 },
    } });
    const a = limits({ databaseFactory: () => db });
    const b = limits({ databaseFactory: () => db });
    for (let i = 0; i < 10; i++) a.record(OLD_DEVICE, 0.03);
    await a.flush();
    assert.ok(Math.abs(db.data[`proxy_usage/v1/devices/2026-10-18/${IID}/usd`] - 0.30) < 1e-9);
    assert.equal(db.data['proxy_usage/v1/ips/2026-10-18/ipA/requests'], 10);
    assert.equal((await b.check(OLD_DEVICE)).reason, 'device_daily_budget');
    const blocked = await b.check({ ...OLD_DEVICE, iid: 'ffffffffffffffffffffffffffffffff' });
    // ゲームが休むように 503（1 時間後）で返す
    assert.equal(blocked.status, 503);
    assert.equal(blocked.reason, 'device_blocked');
    assert.equal(blocked.retryAfterSec, 3600);
    const ipBlocked = await b.check({ ...OLD_DEVICE, iid: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', ipKey: 'badNet' });
    assert.equal(ipBlocked.reason, 'ip_blocked');
    assert.equal(ipBlocked.status, 503);
});

test('denials are counted per reason and day', async () => {
    const db = fakeDatabase();
    const l = limits({ databaseFactory: () => db });
    l.recordDenial('daily_budget');
    l.recordDenial('daily_budget');
    l.recordDenial('device_blocked');
    l.recordDenial('bad/key');  // DB のキーに使えないものは数えない
    await l.flush();
    assert.equal(db.data['proxy_usage/v1/denials/2026-10-18/daily_budget/count'], 2);
    assert.equal(db.data['proxy_usage/v1/denials/2026-10-18/device_blocked/count'], 1);
    assert.equal(Object.keys(db.data).filter(k => k.includes('bad')).length, 0);
});
