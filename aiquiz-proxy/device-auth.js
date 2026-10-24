// 端末ごとの許可証（フェーズ B1）。
//
// APP_SECRET はゲームから取り出せるので、それだけでは「誰が」使っているか分からない。
// ゲームは初回起動時にランダムな端末 ID を作り、/session で許可証をもらう。
//   1. GET  /session/challenge          … 署名つきの課題 {challenge, bits}
//   2. ゲームが sha256(challenge:iid:counter) の先頭 bits ビットが 0 になる counter を探す
//   3. POST /session {iid, challenge, counter} … 署名つきの許可証 {token, expires_at}
// 以後 Gemini へのリクエストには X-Device-Token を付ける。サーバーは状態を持たずに検証できる。
// 計算の課題は、許可証を大量に作ってすり抜けるのを手間にするためのもの（普通の端末は 30 日に 1 回）。
//
// 形式（どちらも base64url の HMAC-SHA256 署名つき）:
//   課題:   c1.<nonce>.<expiresSec>.<sig>
//   許可証: d1.<iid>.<issuedSec>.<sig>

const crypto = require('crypto');

const IID_PATTERN = /^[0-9a-f]{32}$/;

function b64url(buffer) {
    return buffer.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function sign(key, text) {
    return b64url(crypto.createHmac('sha256', key).update(text, 'utf8').digest());
}

function safeEqual(a, b) {
    const x = Buffer.from(String(a));
    const y = Buffer.from(String(b));
    return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function leadingZeroBits(buffer) {
    let bits = 0;
    for (const byte of buffer) {
        if (byte === 0) {
            bits += 8;
            continue;
        }
        return bits + Math.clz32(byte) - 24;
    }
    return bits;
}

class DeviceAuth {
    constructor({
        key,
        powBits = 18,
        tokenTtlSec = 30 * 24 * 3600,
        challengeTtlSec = 10 * 60,
        now = () => Date.now(),
    }) {
        if (!key) throw new Error('DeviceAuth needs a signing key');
        this.key = key;
        this.powBits = powBits;
        this.tokenTtlSec = tokenTtlSec;
        this.challengeTtlSec = challengeTtlSec;
        this.now = now;
    }

    static fromEnv(env = process.env) {
        if (!env.DEVICE_TOKEN_KEY) return null;
        return new DeviceAuth({
            key: env.DEVICE_TOKEN_KEY,
            powBits: Number(env.DEVICE_POW_BITS || 18),
        });
    }

    nowSec() {
        return Math.floor(this.now() / 1000);
    }

    issueChallenge() {
        const nonce = b64url(crypto.randomBytes(12));
        const expires = this.nowSec() + this.challengeTtlSec;
        const body = `c1.${nonce}.${expires}`;
        return { challenge: `${body}.${sign(this.key, body)}`, bits: this.powBits, expires_at: expires };
    }

    // 課題の答えを確かめて許可証を出す。失敗は Error（message が理由）
    redeem(iid, challenge, counter) {
        iid = String(iid || '');
        challenge = String(challenge || '');
        counter = String(counter ?? '');
        if (!IID_PATTERN.test(iid)) throw new Error('invalid_iid');
        if (!/^\d{1,12}$/.test(counter)) throw new Error('invalid_counter');
        const parts = challenge.split('.');
        if (parts.length !== 4 || parts[0] !== 'c1') throw new Error('invalid_challenge');
        const body = parts.slice(0, 3).join('.');
        if (!safeEqual(parts[3], sign(this.key, body))) throw new Error('invalid_challenge');
        if (Number(parts[2]) < this.nowSec()) throw new Error('challenge_expired');
        const digest = crypto.createHash('sha256').update(`${challenge}:${iid}:${counter}`, 'utf8').digest();
        if (leadingZeroBits(digest) < this.powBits) throw new Error('pow_failed');
        return this.issueToken(iid);
    }

    issueToken(iid) {
        const issued = this.nowSec();
        const body = `d1.${iid}.${issued}`;
        return { token: `${body}.${sign(this.key, body)}`, expires_at: issued + this.tokenTtlSec };
    }

    // 許可証を確かめて {iid, issuedSec} を返す。だめなら null
    verify(token) {
        const parts = String(token || '').split('.');
        if (parts.length !== 4 || parts[0] !== 'd1' || !IID_PATTERN.test(parts[1])) return null;
        const body = parts.slice(0, 3).join('.');
        if (!safeEqual(parts[3], sign(this.key, body))) return null;
        const issued = Number(parts[2]);
        const now = this.nowSec();
        // 未来の発行時刻（時計ずれを 5 分まで許す）と期限切れは拒否
        if (!Number.isInteger(issued) || issued > now + 300 || issued + this.tokenTtlSec < now) return null;
        return { iid: parts[1], issuedSec: issued };
    }

    // IP をそのまま保存しないための鍵つきハッシュ
    ipKey(ip) {
        return sign(this.key, `ip:${ip}`).slice(0, 22);
    }
}

module.exports = { DeviceAuth, leadingZeroBits };
