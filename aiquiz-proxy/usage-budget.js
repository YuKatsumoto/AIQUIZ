// 試合中の AI の利用額を日・月で積み上げ、予算を超えたら生成を止める。
// Claude の系統（/claude）は fromClaudeEnv で作り、別の場所（proxy_usage_claude/v1）に積む。
//
// 各インスタンスは返ってきた usageMetadata から費用を計算し、手元に貯めてから
// FLUSH 間隔ごとに Realtime Database へ加算する（リクエストごとの書き込みはしない）。
// 合計は REFRESH 間隔ごとに読み直す。止まるまでの行き過ぎは「間隔 × 流量」程度。
//
// Firebase のレイアウト（日付・月は日本時間）:
//   proxy_usage/v1/daily/{YYYY-MM-DD}   … {usd, requests, prompt_tokens, output_tokens, models/{model}/{usd,requests}}
//   proxy_usage/v1/monthly/{YYYY-MM}    … {usd, requests}
// FIREBASE_DB_URL が無い（手元の開発）ときはインスタンス内の集計だけで判定する。

const { ServerValue } = require('firebase-admin/database');

const USAGE_PATH = 'proxy_usage/v1';
const CLAUDE_USAGE_PATH = 'proxy_usage_claude/v1';

// 100万トークンあたりの標準料金（USD）。出力は思考トークンを含む。
// 料金改定（3.6 Flash は 2027-01-01 から 2 倍）は GEMINI_PRICES_JSON で差し替える。
const DEFAULT_PRICES = {
    'gemini-3.6-flash': { input: 0.75, output: 3.75 },
    'gemini-3.1-flash-lite': { input: 0.25, output: 1.50 },
    'gemini-3.5-flash-lite': { input: 0.30, output: 2.50 },
};

function pricesFromEnv(env = process.env) {
    if (!env.GEMINI_PRICES_JSON) return DEFAULT_PRICES;
    return { ...DEFAULT_PRICES, ...JSON.parse(env.GEMINI_PRICES_JSON) };
}

function costUsd(prices, model, usage) {
    const price = prices[model];
    if (!price || !usage) return 0;
    const output = Number(usage.candidatesTokenCount || 0) + Number(usage.thoughtsTokenCount || 0);
    return (Number(usage.promptTokenCount || 0) * price.input + output * price.output) / 1e6;
}

// 日本時間の YYYY-MM-DD と YYYY-MM
function jstKeys(date) {
    const day = new Date(date.getTime() + 9 * 3600 * 1000).toISOString().slice(0, 10);
    return { day, month: day.slice(0, 7) };
}

function secondsUntilNextJstDay(date) {
    const jst = new Date(date.getTime() + 9 * 3600 * 1000);
    const next = Date.UTC(jst.getUTCFullYear(), jst.getUTCMonth(), jst.getUTCDate() + 1);
    return Math.max(60, Math.ceil((next - jst.getTime()) / 1000));
}

function modelKey(model) {
    return String(model).replace(/[.#$/[\]]/g, '_');
}

class UsageBudget {
    constructor({
        databaseFactory = null,
        dailyBudgetUsd = 10,
        monthlyBudgetUsd = 100,
        prices = DEFAULT_PRICES,
        usagePath = USAGE_PATH,
        flushMs = 10000,
        refreshMs = 30000,
        now = () => new Date(),
        log = console,
    } = {}) {
        this.databaseFactory = databaseFactory;
        this.dailyBudgetUsd = dailyBudgetUsd;
        this.monthlyBudgetUsd = monthlyBudgetUsd;
        this.prices = prices;
        this.usagePath = usagePath;
        this.flushMs = flushMs;
        this.refreshMs = refreshMs;
        this.now = now;
        this.log = log;
        this.pending = null;          // まだ DB に書いていない分
        this.stored = { day: '', month: '', dailyUsd: 0, monthlyUsd: 0 }; // DB から読んだ合計
        this.lastRefresh = 0;
        this.timer = null;
    }

    static fromEnv(env = process.env, databaseFactory = null) {
        return new UsageBudget({
            databaseFactory,
            dailyBudgetUsd: Number(env.GEMINI_DAILY_BUDGET_USD || 10),
            monthlyBudgetUsd: Number(env.GEMINI_MONTHLY_BUDGET_USD || 100),
            prices: pricesFromEnv(env),
        });
    }

    // Claude の系統。月 40 ドル・1 日 3 ドルが既定（月 100 ドル未満の全体予算のうち、試合中の生成の分）。
    // 費用は claude-live.js が計算して record() の usd に渡す。
    static fromClaudeEnv(env = process.env, databaseFactory = null) {
        return new UsageBudget({
            databaseFactory,
            dailyBudgetUsd: Number(env.CLAUDE_DAILY_BUDGET_USD || 3),
            monthlyBudgetUsd: Number(env.CLAUDE_MONTHLY_BUDGET_USD || 40),
            prices: {},
            usagePath: CLAUDE_USAGE_PATH,
        });
    }

    _db() {
        if (!this.databaseFactory) return null;
        try {
            return this.databaseFactory();
        } catch (error) {
            this.log.warn(`[budget] Firebase unavailable, counting in memory only: ${error.message}`);
            this.databaseFactory = null;
            return null;
        }
    }

    _pendingFor(keys) {
        if (!this.pending || this.pending.day !== keys.day) {
            // 日をまたいだら前日分は書き出し済み扱いにして新しい日を始める
            if (this.pending && this.pending.requests) this._flushNow(this.pending);
            this.pending = { day: keys.day, month: keys.month, usd: 0, requests: 0,
                prompt_tokens: 0, output_tokens: 0, models: {} };
        }
        return this.pending;
    }

    // 応答 1 回分を記録し、その費用（USD）を返す。usd を渡さなければ prices から計算する。
    record(model, usage, usd = costUsd(this.prices, model, usage)) {
        const p = this._pendingFor(jstKeys(this.now()));
        p.usd += usd;
        p.requests += 1;
        p.prompt_tokens += Number((usage && usage.promptTokenCount) || 0);
        p.output_tokens += Number((usage && usage.candidatesTokenCount) || 0)
            + Number((usage && usage.thoughtsTokenCount) || 0);
        const m = p.models[modelKey(model)] || { usd: 0, requests: 0 };
        m.usd += usd;
        m.requests += 1;
        p.models[modelKey(model)] = m;
        this._schedule();
        return usd;
    }

    _schedule() {
        if (this.timer || !this.databaseFactory) return;
        this.timer = setTimeout(() => {
            this.timer = null;
            this.flush().catch(error => this.log.error(`[budget] flush failed: ${error.message}`));
        }, this.flushMs);
        if (this.timer.unref) this.timer.unref();
    }

    async flush() {
        const p = this.pending;
        if (!p || !p.requests) return;
        this.pending = null;
        await this._flushNow(p);
    }

    async _flushNow(p) {
        const db = this._db();
        if (!db) {
            // 書けないときは手元の合計に足しておく（判定にだけ使う）
            this._addStored(p);
            return;
        }
        const daily = {
            usd: ServerValue.increment(p.usd),
            requests: ServerValue.increment(p.requests),
            prompt_tokens: ServerValue.increment(p.prompt_tokens),
            output_tokens: ServerValue.increment(p.output_tokens),
        };
        for (const [key, m] of Object.entries(p.models)) {
            daily[`models/${key}/usd`] = ServerValue.increment(m.usd);
            daily[`models/${key}/requests`] = ServerValue.increment(m.requests);
        }
        try {
            await db.ref(`${this.usagePath}/daily/${p.day}`).update(daily);
            await db.ref(`${this.usagePath}/monthly/${p.month}`).update({
                usd: ServerValue.increment(p.usd),
                requests: ServerValue.increment(p.requests),
            });
        } catch (error) {
            this.log.error(`[budget] write failed, keeping the amount in memory: ${error.message}`);
        }
        this._addStored(p);
    }

    _addStored(p) {
        if (this.stored.day === p.day) this.stored.dailyUsd += p.usd;
        if (this.stored.month === p.month) this.stored.monthlyUsd += p.usd;
    }

    async refresh(force = false) {
        const nowMs = this.now().getTime();
        if (!force && nowMs - this.lastRefresh < this.refreshMs) return;
        this.lastRefresh = nowMs;
        const keys = jstKeys(this.now());
        const db = this._db();
        if (!db) {
            if (this.stored.day !== keys.day) this.stored = { ...this.stored, day: keys.day, dailyUsd: 0 };
            if (this.stored.month !== keys.month) this.stored = { ...this.stored, month: keys.month, monthlyUsd: 0 };
            return;
        }
        try {
            const [daily, monthly] = await Promise.all([
                db.ref(`${this.usagePath}/daily/${keys.day}/usd`).once('value'),
                db.ref(`${this.usagePath}/monthly/${keys.month}/usd`).once('value'),
            ]);
            this.stored = { day: keys.day, month: keys.month,
                dailyUsd: Number(daily.val() || 0), monthlyUsd: Number(monthly.val() || 0) };
        } catch (error) {
            // 読めないときは前回の値で判定を続ける
            this.log.error(`[budget] read failed: ${error.message}`);
        }
    }

    // 今の合計（DB の値 + まだ書いていない分）
    totals() {
        const keys = jstKeys(this.now());
        const pending = this.pending && this.pending.day === keys.day ? this.pending.usd : 0;
        const dailyUsd = (this.stored.day === keys.day ? this.stored.dailyUsd : 0) + pending;
        const monthlyUsd = (this.stored.month === keys.month ? this.stored.monthlyUsd : 0) + pending;
        return { day: keys.day, month: keys.month, dailyUsd, monthlyUsd };
    }

    // 生成してよいか。止めるときは {ok:false, reason, retryAfterSec}
    async check() {
        await this.refresh();
        const t = this.totals();
        if (this.monthlyBudgetUsd > 0 && t.monthlyUsd >= this.monthlyBudgetUsd) {
            return { ok: false, reason: 'monthly_budget', retryAfterSec: 3600, ...t };
        }
        if (this.dailyBudgetUsd > 0 && t.dailyUsd >= this.dailyBudgetUsd) {
            return { ok: false, reason: 'daily_budget', retryAfterSec: secondsUntilNextJstDay(this.now()), ...t };
        }
        return { ok: true, ...t };
    }

    // 月の上限を残り日数で割った「今日使ってよい額」に対する、今日の使用ペース。
    //   green  … 時刻に対して予定どおりか余裕あり
    //   yellow … 少し速い / orange … 速い / red … 今日の目安を使い切った
    // 日・月の上限そのものの判定は check() が行う。
    async paceLevel() {
        await this.refresh();
        const t = this.totals();
        const now = this.now();
        const jst = new Date(now.getTime() + 9 * 3600 * 1000);
        const daysInMonth = new Date(Date.UTC(jst.getUTCFullYear(), jst.getUTCMonth() + 1, 0)).getUTCDate();
        const daysLeft = daysInMonth - jst.getUTCDate() + 1;
        const spentBeforeToday = Math.max(0, t.monthlyUsd - t.dailyUsd);
        let target = this.monthlyBudgetUsd > 0
            ? Math.max(0, this.monthlyBudgetUsd - spentBeforeToday) / daysLeft
            : this.dailyBudgetUsd;
        if (this.dailyBudgetUsd > 0) target = Math.min(target, this.dailyBudgetUsd);
        const secondsToday = jst.getUTCHours() * 3600 + jst.getUTCMinutes() * 60 + jst.getUTCSeconds();
        const timeFrac = secondsToday / 86400;
        const spentFrac = target > 0 ? t.dailyUsd / target : 1;
        let level = 'orange';
        if (spentFrac >= 1) level = 'red';
        else if (spentFrac <= timeFrac + 0.1) level = 'green';
        else if (spentFrac <= timeFrac + 0.3) level = 'yellow';
        return { level, targetUsd: target, dailyUsd: t.dailyUsd, timeFrac };
    }

    status() {
        const t = this.totals();
        return {
            day: t.day,
            daily_usd: Number(t.dailyUsd.toFixed(4)),
            daily_budget_usd: this.dailyBudgetUsd,
            month: t.month,
            monthly_usd: Number(t.monthlyUsd.toFixed(4)),
            monthly_budget_usd: this.monthlyBudgetUsd,
        };
    }
}

module.exports = {
    CLAUDE_USAGE_PATH, DEFAULT_PRICES, USAGE_PATH, UsageBudget, costUsd, jstKeys, pricesFromEnv, secondsUntilNextJstDay,
};
