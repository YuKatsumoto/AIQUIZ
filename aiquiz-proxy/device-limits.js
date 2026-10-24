// 端末ごと・IP ごとの 1 日の利用額の上限（フェーズ B1）。
//
// - 端末: 1 日 $0.30（10 問モード約 10 試合分）。許可証をもらってから 24 時間は $0.10。
//   許可証を作り直して上限をすり抜けても得をしないように。
// - IP: 1 日 $30。学校の教室（40 人 × 2〜3 クラス）でも引っかからない程度。IP は鍵つきハッシュで保存する。
// - ブロックリスト: device_blocklist/v1/{iid または ipKey} に値がある端末・回線は止める。
//   管理ソフト（aiquiz-ops）から書く。値は {kind, reason, at, by}（古い true もそのまま有効）。
// 超えたら・止めたら 503 を返し、ゲームはしばらく生成を休んで共有バンクの問題で続ける（フェーズ A の仕組み）。
//
// Firebase のレイアウト（日付は日本時間）:
//   proxy_usage/v1/devices/{YYYY-MM-DD}/{iid}    … {usd, requests}
//   proxy_usage/v1/ips/{YYYY-MM-DD}/{ipKey}      … {usd, requests}
//   proxy_usage/v1/denials/{YYYY-MM-DD}/{reason} … {count, requests}  止めた回数（理由ごと）

const { ServerValue } = require('firebase-admin/database');
const { USAGE_PATH, jstKeys, secondsUntilNextJstDay } = require('./usage-budget');

const BLOCKLIST_PATH = 'device_blocklist/v1';
const MAX_CACHED_KEYS = 50000;
const BLOCKED_RETRY_SEC = 3600;

// キーごとの今日の利用額。書き込みはまとめて、読み込みはキーごとに間隔をあけて。
class KeyedDailySpend {
    constructor({ databaseFactory = null, path, field = 'usd', flushMs = 10000, refreshMs = 30000,
        now = () => new Date(), log = console }) {
        this.databaseFactory = databaseFactory;
        this.path = path;
        this.field = field;
        this.flushMs = flushMs;
        this.refreshMs = refreshMs;
        this.now = now;
        this.log = log;
        this.pending = new Map();  // key -> {day, usd, requests}
        this.stored = new Map();   // key -> {day, usd, readAt}
        this.timer = null;
    }

    _db() {
        if (!this.databaseFactory) return null;
        try {
            return this.databaseFactory();
        } catch (error) {
            this.log.warn(`[limits] Firebase unavailable, counting in memory only: ${error.message}`);
            this.databaseFactory = null;
            return null;
        }
    }

    record(key, usd) {
        const day = jstKeys(this.now()).day;
        let p = this.pending.get(key);
        if (p && p.day !== day) {
            this._flushEntries([[key, p]]);
            p = null;
        }
        p = p || { day, usd: 0, requests: 0 };
        p.usd += usd;
        p.requests += 1;
        this.pending.set(key, p);
        if (!this.timer && this.databaseFactory) {
            this.timer = setTimeout(() => {
                this.timer = null;
                this.flush().catch(error => this.log.error(`[limits] flush failed: ${error.message}`));
            }, this.flushMs);
            if (this.timer.unref) this.timer.unref();
        }
    }

    async flush() {
        const entries = [...this.pending.entries()];
        this.pending.clear();
        await this._flushEntries(entries);
    }

    async _flushEntries(entries) {
        if (!entries.length) return;
        const db = this._db();
        const byDay = new Map();
        for (const [key, p] of entries) {
            // 手元の合計にも足しておく（次に読み直すまでの判定用）
            const s = this.stored.get(key);
            if (s && s.day === p.day) s.usd += p.usd;
            else if (!db) this.stored.set(key, { day: p.day, usd: p.usd, readAt: Date.now() });
            if (!byDay.has(p.day)) byDay.set(p.day, {});
            const update = byDay.get(p.day);
            update[`${key}/${this.field}`] = ServerValue.increment(p.usd);
            update[`${key}/requests`] = ServerValue.increment(p.requests);
        }
        if (!db) return;
        for (const [day, update] of byDay) {
            try {
                await db.ref(`${this.path}/${day}`).update(update);
            } catch (error) {
                this.log.error(`[limits] write failed: ${error.message}`);
            }
        }
    }

    async spent(key) {
        const day = jstKeys(this.now()).day;
        let s = this.stored.get(key);
        const db = this._db();
        if (!s || s.day !== day || (db && Date.now() - s.readAt >= this.refreshMs)) {
            let usd = s && s.day === day ? s.usd : 0;
            if (db) {
                try {
                    usd = Number((await db.ref(`${this.path}/${day}/${key}/${this.field}`).once('value')).val() || 0);
                } catch (error) {
                    this.log.error(`[limits] read failed: ${error.message}`);
                }
            }
            if (this.stored.size >= MAX_CACHED_KEYS) this.stored.clear();
            s = { day, usd, readAt: Date.now() };
            this.stored.set(key, s);
        }
        const p = this.pending.get(key);
        return s.usd + (p && p.day === day ? p.usd : 0);
    }
}

class DeviceLimits {
    constructor({
        databaseFactory = null,
        deviceDailyUsd = 0.30,
        newDeviceDailyUsd = 0.10,
        newDeviceWindowSec = 24 * 3600,
        ipDailyUsd = 30,
        blocklistRefreshMs = 60000,
        now = () => new Date(),
        log = console,
    } = {}) {
        this.databaseFactory = databaseFactory;
        this.deviceDailyUsd = deviceDailyUsd;
        this.newDeviceDailyUsd = newDeviceDailyUsd;
        this.newDeviceWindowSec = newDeviceWindowSec;
        this.ipDailyUsd = ipDailyUsd;
        this.blocklistRefreshMs = blocklistRefreshMs;
        this.now = now;
        this.log = log;
        this.devices = new KeyedDailySpend({ databaseFactory, path: `${USAGE_PATH}/devices`, now, log });
        this.ips = new KeyedDailySpend({ databaseFactory, path: `${USAGE_PATH}/ips`, now, log });
        // 端末ごとの今日のラウンド数（フェーズ C1 の「その日の最初の試合」の判定用）
        this.rounds = new KeyedDailySpend({ databaseFactory, path: `${USAGE_PATH}/rounds`, field: 'rounds', now, log });
        // 止めた回数（理由ごと）。管理ソフトで「上限に当たった回数」として見る
        this.denials = new KeyedDailySpend({ databaseFactory, path: `${USAGE_PATH}/denials`, field: 'count', now, log });
        this.blocked = new Set();
        this.blocklistReadAt = 0;
    }

    static fromEnv(env = process.env, databaseFactory = null) {
        return new DeviceLimits({
            databaseFactory,
            deviceDailyUsd: Number(env.DEVICE_DAILY_BUDGET_USD || 0.30),
            newDeviceDailyUsd: Number(env.NEW_DEVICE_DAILY_BUDGET_USD || 0.10),
            ipDailyUsd: Number(env.IP_DAILY_BUDGET_USD || 30),
        });
    }

    async _refreshBlocklist() {
        if (!this.databaseFactory || Date.now() - this.blocklistReadAt < this.blocklistRefreshMs) return;
        this.blocklistReadAt = Date.now();
        try {
            const db = this.databaseFactory();
            const value = (await db.ref(BLOCKLIST_PATH).once('value')).val() || {};
            this.blocked = new Set(Object.keys(value).filter(key => value[key]));
        } catch (error) {
            this.log.error(`[limits] blocklist read failed: ${error.message}`);
        }
    }

    // その端末・IP で生成してよいか。止めるときは {ok:false, status, reason, retryAfterSec}
    async check({ iid, issuedSec, ipKey }) {
        await this._refreshBlocklist();
        // ブロックは 503（1 時間後にまた）。403 だとゲームは休まずに問題ごとに呼び直してしまう
        if (this.blocked.has(iid)) {
            return { ok: false, status: 503, reason: 'device_blocked', retryAfterSec: BLOCKED_RETRY_SEC };
        }
        if (ipKey && this.blocked.has(ipKey)) {
            return { ok: false, status: 503, reason: 'ip_blocked', retryAfterSec: BLOCKED_RETRY_SEC };
        }
        const retryAfterSec = secondsUntilNextJstDay(this.now());
        const isNew = Math.floor(this.now().getTime() / 1000) - issuedSec < this.newDeviceWindowSec;
        const deviceCap = isNew ? this.newDeviceDailyUsd : this.deviceDailyUsd;
        if (deviceCap > 0 && await this.devices.spent(iid) >= deviceCap) {
            return { ok: false, status: 503, reason: 'device_daily_budget', retryAfterSec };
        }
        if (this.ipDailyUsd > 0 && ipKey && await this.ips.spent(ipKey) >= this.ipDailyUsd) {
            return { ok: false, status: 503, reason: 'ip_daily_budget', retryAfterSec };
        }
        return { ok: true };
    }

    record({ iid, ipKey }, usd) {
        if (iid) this.devices.record(iid, usd);
        if (ipKey) this.ips.record(ipKey, usd);
    }

    // 止めた理由を 1 回数える（daily_budget, device_blocked, rate_limited など）
    recordDenial(reason) {
        if (/^[a-z_]{1,40}$/.test(String(reason))) this.denials.record(reason, 1);
    }

    // この端末の今日の何ラウンド目か（1 から）を返し、数を 1 つ進める
    async nextRoundIndex(iid) {
        const index = Math.floor(await this.rounds.spent(iid)) + 1;
        this.rounds.record(iid, 1);
        return index;
    }

    async flush() {
        await Promise.all([this.devices.flush(), this.ips.flush(), this.rounds.flush(), this.denials.flush()]);
    }
}

module.exports = { BLOCKED_RETRY_SEC, BLOCKLIST_PATH, DeviceLimits, KeyedDailySpend };
