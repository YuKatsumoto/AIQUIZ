const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { DeviceAuth, leadingZeroBits } = require('../device-auth');

const IID = '0123456789abcdef0123456789abcdef';

function solve(challenge, iid, bits) {
    for (let counter = 0; ; counter++) {
        const digest = crypto.createHash('sha256').update(`${challenge}:${iid}:${counter}`).digest();
        if (leadingZeroBits(digest) >= bits) return String(counter);
    }
}

function auth(overrides = {}) {
    return new DeviceAuth({ key: 'test-key', powBits: 8, ...overrides });
}

test('leading zero bits are counted across bytes', () => {
    assert.equal(leadingZeroBits(Buffer.from([0x00, 0x00, 0x80])), 16);
    assert.equal(leadingZeroBits(Buffer.from([0x00, 0x0f])), 12);
    assert.equal(leadingZeroBits(Buffer.from([0xff])), 0);
});

test('a solved challenge gives a token that verifies', () => {
    const a = auth();
    const { challenge, bits } = a.issueChallenge();
    assert.equal(bits, 8);
    const { token, expires_at } = a.redeem(IID, challenge, solve(challenge, IID, bits));
    const device = a.verify(token);
    assert.equal(device.iid, IID);
    assert.ok(expires_at > device.issuedSec);
});

test('wrong answers, other ids and tampered or expired challenges are refused', () => {
    const a = auth({ powBits: 12 });
    const { challenge } = a.issueChallenge();
    const counter = solve(challenge, IID, 12);
    const otherIid = 'ffffffffffffffffffffffffffffffff';
    assert.throws(() => a.redeem(IID, challenge, String(Number(counter) + 1)), /pow_failed/);
    // the answer is tied to the device id it was computed for
    assert.throws(() => a.redeem(otherIid, challenge, counter), /pow_failed/);
    assert.throws(() => a.redeem('not-hex', challenge, counter), /invalid_iid/);
    assert.throws(() => a.redeem(IID, challenge.replace('c1.', 'c1.x'), counter), /invalid_challenge/);
    assert.throws(() => auth({ key: 'other-key', powBits: 12 }).redeem(IID, challenge, counter), /invalid_challenge/);
    let now = Date.now();
    const timed = auth({ now: () => now });
    const old = timed.issueChallenge().challenge;
    now += 11 * 60 * 1000;
    assert.throws(() => timed.redeem(IID, old, solve(old, IID, 8)), /challenge_expired/);
});

test('tampered, foreign, future and expired tokens do not verify', () => {
    let now = Date.now();
    const a = auth({ now: () => now });
    const { token } = a.issueToken(IID);
    assert.ok(a.verify(token));
    assert.equal(a.verify(token.replace(IID, 'ffffffffffffffffffffffffffffffff')), null);
    assert.equal(auth({ key: 'other-key' }).verify(token), null);
    assert.equal(a.verify(''), null);
    assert.equal(a.verify(undefined), null);
    const future = auth({ now: () => now + 3600 * 1000 }).issueToken(IID).token;
    assert.equal(a.verify(future), null);
    now += 31 * 24 * 3600 * 1000;
    assert.equal(a.verify(token), null);
});

test('IP keys are stable per key and do not contain the address', () => {
    const a = auth();
    assert.equal(a.ipKey('203.0.113.7'), a.ipKey('203.0.113.7'));
    assert.notEqual(a.ipKey('203.0.113.7'), a.ipKey('203.0.113.8'));
    assert.ok(!a.ipKey('203.0.113.7').includes('203'));
    assert.match(a.ipKey('203.0.113.7'), /^[A-Za-z0-9_-]{22}$/);
});
