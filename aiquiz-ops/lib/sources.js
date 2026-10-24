// 本番のデータを読む部分（読むだけ。書き込みはしない）。
//   Firebase Realtime Database … プロキシと夜のジョブの記録
//   Cloud Run / Cloud Scheduler … 予算などの設定値、夜のジョブの実行履歴と次回予定
// PC の gcloud のログイン（Application Default Credentials）で読む。
const {
    BLOCKLIST_PATH, BUILDER_PATH, DeviceLimits, USAGE_PATH, UsageBudget,
    builderConfigFromEnv, jstKeys, loadPrompts, reviewConfigFromEnv,
} = require('./proxy-shared');
const { bankSummary, claudeSummary, jobsSummary, moneySummary, playersSummary } = require('./summaries');

const REVIEW_PATH = 'quiz_review/v1';
const BANK_ITEMS_PATH = 'quiz_bank/v1/items';
const ARCHIVE_ITEMS_PATH = 'quiz_archive/v1/items';
const LEVELS = ['green', 'yellow', 'orange', 'red', 'stop'];

const DEFAULT_CONFIG = {
    gcpProject: 'gen-lang-client-0828350684',
    region: 'asia-northeast1',
    service: 'aiquiz-proxy',
    jobs: [
        { name: 'quiz-bank-builder', label: '夜の補充（Claude Haiku）' },
        { name: 'quiz-claude-review', label: '判定（Claude Opus）' },
    ],
    jpyPerUsd: 150,
    // 共有バンクの全件（約 5MB）は重いので、この間は前回の結果を使う
    heavyCacheMs: 10 * 60 * 1000,
    settingsCacheMs: 5 * 60 * 1000,
};

// Cloud Run の env 一覧から、値が直接書いてあるものだけを取り出す（Secret Manager 参照は読まない）
function plainEnv(container) {
    const env = {};
    for (const entry of (container && container.env) || []) {
        if (entry && entry.value !== undefined) env[entry.name] = entry.value;
    }
    return env;
}

class OpsSources {
    constructor({ db, gcpRequest, config = {}, now = () => new Date(), log = console }) {
        this.db = db;
        this.gcpRequest = gcpRequest;
        this.config = { ...DEFAULT_CONFIG, ...config };
        this.now = now;
        this.log = log;
        this.cache = new Map();
        this.prompts = null;
    }

    async _cached(key, ttlMs, load, refresh = false) {
        const hit = this.cache.get(key);
        if (!refresh && hit && Date.now() - hit.at < ttlMs) return hit;
        // 同時に来た読み込みは 1 回にまとめる
        if (hit && hit.loading) return hit.loading;
        const loading = (async () => {
            const value = await load();
            const entry = { at: Date.now(), value };
            this.cache.set(key, entry);
            return entry;
        })();
        this.cache.set(key, { ...(hit || {}), loading });
        try {
            return await loading;
        } catch (error) {
            if (hit && hit.value !== undefined) this.cache.set(key, { at: hit.at, value: hit.value });
            else this.cache.delete(key);
            throw error;
        }
    }

    async _val(path, query = ref => ref) {
        return (await query(this.db.ref(path)).once('value')).val();
    }

    runUrl(path) {
        const c = this.config;
        return `https://run.googleapis.com/v2/projects/${c.gcpProject}/locations/${c.region}/${path}`;
    }

    // プロキシと夜のジョブの設定値（予算・上限）
    async settings() {
        const entry = await this._cached('settings', this.config.settingsCacheMs, async () => {
            const service = await this.gcpRequest(this.runUrl(`services/${this.config.service}`));
            const proxyEnv = plainEnv(((service.template || {}).containers || [])[0]);
            const jobEnv = {};
            for (const job of this.config.jobs) {
                try {
                    const data = await this.gcpRequest(this.runUrl(`jobs/${job.name}`));
                    jobEnv[job.name] = plainEnv(((((data.template || {}).template) || {}).containers || [])[0]);
                } catch (error) {
                    this.log.warn(`[ops] ${job.name} の設定を読めません: ${error.message}`);
                    jobEnv[job.name] = {};
                }
            }
            const limits = DeviceLimits.fromEnv(proxyEnv);
            return {
                revision: String(service.latestReadyRevision || '').split('/').pop(),
                proxyEnv,
                budgets: {
                    dailyUsd: Number(proxyEnv.GEMINI_DAILY_BUDGET_USD || 10),
                    monthlyUsd: Number(proxyEnv.GEMINI_MONTHLY_BUDGET_USD || 100),
                },
                forcedLevel: LEVELS.includes(proxyEnv.ROUND_PLAN_FORCE_LEVEL) ? proxyEnv.ROUND_PLAN_FORCE_LEVEL : null,
                caps: {
                    deviceUsd: limits.deviceDailyUsd,
                    newDeviceUsd: limits.newDeviceDailyUsd,
                    ipUsd: limits.ipDailyUsd,
                },
                builderConfig: builderConfigFromEnv(jobEnv['quiz-bank-builder'] || {}),
                reviewConfig: reviewConfigFromEnv(jobEnv['quiz-claude-review'] || {}),
            };
        });
        return entry.value;
    }

    async _batches(refresh = false) {
        const entry = await this._cached('batches', this.config.heavyCacheMs, async () => {
            const [builder, review] = await Promise.all([
                this._val(`${BUILDER_PATH}/batches`),
                this._val(`${REVIEW_PATH}/batches`),
            ]);
            return { builder: builder || {}, review: review || {} };
        }, refresh);
        return entry.value;
    }

    async money() {
        const now = this.now();
        const settings = await this.settings();
        const { month } = jstKeys(now);
        // 段階はプロキシの /round-plan と同じ計算（上限を超えていれば stop、指定があればそれ）
        const budget = new UsageBudget({
            databaseFactory: () => this.db,
            dailyBudgetUsd: settings.budgets.dailyUsd,
            monthlyBudgetUsd: settings.budgets.monthlyUsd,
            refreshMs: 5000,
            now: () => now,
            log: this.log,
        });
        const [check, pace, daily, monthly, builderSpend, reviewSpend, batches] = await Promise.all([
            budget.check(),
            budget.paceLevel(),
            this._val(`${USAGE_PATH}/daily`, ref => ref.orderByKey().limitToLast(62)),
            this._val(`${USAGE_PATH}/monthly`, ref => ref.orderByKey().limitToLast(3)),
            this._val(`${BUILDER_PATH}/spend`, ref => ref.orderByKey().limitToLast(3)),
            this._val(`${REVIEW_PATH}/spend`, ref => ref.orderByKey().limitToLast(3)),
            this._batches(),
        ]);
        let level = 'stop';
        if (check.ok) level = settings.forcedLevel || pace.level;
        return moneySummary({
            now,
            budgets: settings.budgets,
            level,
            pace,
            forcedLevel: settings.forcedLevel,
            stopReason: check.ok ? null : check.reason,
            daily: daily || {},
            monthly: monthly || {},
            jpyPerUsd: this.config.jpyPerUsd,
            claude: claudeSummary({
                month,
                builderSpend,
                builderBatches: batches.builder,
                builderConfig: settings.builderConfig,
                reviewSpend,
                reviewBatches: batches.review,
                reviewConfig: settings.reviewConfig,
            }),
        });
    }

    async players() {
        const now = this.now();
        const settings = await this.settings();
        const { day } = jstKeys(now);
        const [devices, ips, roundsHistory, blocked, todayUsd, denials] = await Promise.all([
            this._val(`${USAGE_PATH}/devices/${day}`),
            this._val(`${USAGE_PATH}/ips/${day}`),
            this._val(`${USAGE_PATH}/rounds`, ref => ref.orderByKey().limitToLast(14)),
            this._val(BLOCKLIST_PATH),
            this._val(`${USAGE_PATH}/daily/${day}/usd`),
            this._val(`${USAGE_PATH}/denials/${day}`),
        ]);
        const history = roundsHistory || {};
        return playersSummary({
            now,
            devices: devices || {},
            ips: ips || {},
            rounds: history[day] || {},
            roundsHistory: history,
            blocked: blocked || {},
            denials: denials || {},
            caps: settings.caps,
            geminiTodayUsd: Number(todayUsd || 0),
        });
    }

    async bank({ refresh = false } = {}) {
        if (!this.prompts) this.prompts = loadPrompts();
        const settings = await this.settings();
        const entry = await this._cached('bank', this.config.heavyCacheMs, async () => {
            const [bank, archive] = await Promise.all([
                this._val(BANK_ITEMS_PATH),
                this._val(ARCHIVE_ITEMS_PATH),
            ]);
            return { bank: bank || {}, archive: archive || {} };
        }, refresh);
        const batches = await this._batches(refresh);
        return {
            fetchedAt: new Date(entry.at).toISOString(),
            ...bankSummary({
                now: this.now(),
                prompts: this.prompts,
                bank: entry.value.bank,
                archive: entry.value.archive,
                builderBatches: batches.builder,
                reviewBatches: batches.review,
                target: settings.builderConfig.targetPerBucket,
            }),
        };
    }

    // 共有バンクの問題を探す（共有バンクのタブと同じ読み込み結果から）。removed=true なら管理ソフトで外した問題
    async searchQuestions({ text = '', id = '', subject = '', grade = '', difficulty = '', removed = false, limit = 50 } = {}) {
        if (!this.cache.get('bank') || !this.cache.get('bank').value) await this.bank();
        const { bank, archive } = this.cache.get('bank').value;
        const words = String(text).trim().toLowerCase().split(/\s+/).filter(Boolean);
        const wantId = String(id).trim();
        const source = removed
            ? Object.entries(archive).filter(([, a]) => a && a.ops_removed)
            : Object.entries(bank);
        const matches = [];
        for (const [key, item] of source) {
            if (!item) continue;
            if (wantId && key !== wantId) continue;
            if (subject && item.subject !== subject) continue;
            if (grade && Number(item.grade) !== Number(grade)) continue;
            if (difficulty && item.difficulty !== difficulty) continue;
            if (words.length) {
                const hay = [item.q, ...(item.c || []), item.e].join(' ').toLowerCase();
                if (!words.every(w => hay.includes(w))) continue;
            }
            matches.push([key, item]);
        }
        if (removed) matches.sort((a, b) => Number(b[1].ops_removed.at || 0) - Number(a[1].ops_removed.at || 0));
        const max = Math.min(200, Math.max(1, Number(limit) || 50));
        return {
            total: matches.length,
            items: matches.slice(0, max).map(([key, item]) => {
                const a = archive[key] || {};
                const review = a.review || {};
                return {
                    id: key,
                    q: item.q,
                    c: item.c || [],
                    a: item.a,
                    e: item.e || '',
                    subject: item.subject,
                    grade: item.grade,
                    difficulty: item.difficulty,
                    origin: a.original_src || '',
                    seenCount: Number(a.seen_count || 0),
                    review: review.state === 'done' ? { verdict: review.verdict, note: review.note || '' } : null,
                    removed: a.ops_removed || null,
                };
            }),
        };
    }

    // 管理ソフトから問題を外した・戻したとき、読み込み済みの結果も合わせる（5MB を読み直さないように）
    applyBankChange({ type, id, archive }) {
        const entry = this.cache.get('bank');
        if (!entry || !entry.value) return;
        const { bank, archive: archived } = entry.value;
        if (type === 'removed') {
            delete bank[id];
            if (archived[id]) archived[id] = { ...archived[id], status: 'bad', ops_removed: { at: Math.floor(Date.now() / 1000) } };
        } else if (type === 'restored' && archive) {
            bank[id] = archive;
            archived[id] = archive;
        }
    }

    async jobs() {
        const c = this.config;
        const executions = {};
        await Promise.all(c.jobs.map(async job => {
            const data = await this.gcpRequest(this.runUrl(`jobs/${job.name}/executions?pageSize=5`));
            executions[job.name] = data.executions || [];
        }));
        let schedulers = [];
        try {
            const data = await this.gcpRequest(
                `https://cloudscheduler.googleapis.com/v1/projects/${c.gcpProject}/locations/${c.region}/jobs`);
            schedulers = data.jobs || [];
        } catch (error) {
            this.log.warn(`[ops] Cloud Scheduler を読めません: ${error.message}`);
        }
        return jobsSummary({ jobs: c.jobs, executions, schedulers });
    }

    async overview() {
        const settings = await this.settings();
        return {
            gcpProject: this.config.gcpProject,
            service: this.config.service,
            revision: settings.revision,
            budgets: settings.budgets,
            caps: settings.caps,
            forcedLevel: settings.forcedLevel,
            builder: {
                model: settings.builderConfig.model,
                monthlyBudgetUsd: settings.builderConfig.monthlyBudgetUsd,
                maxCallsPerRun: settings.builderConfig.maxCallsPerRun,
                targetPerBucket: settings.builderConfig.targetPerBucket,
            },
            review: {
                model: settings.reviewConfig.model,
                monthlyBudgetUsd: settings.reviewConfig.monthlyBudgetUsd,
                maxPerRun: settings.reviewConfig.maxPerRun,
            },
        };
    }
}

module.exports = { DEFAULT_CONFIG, OpsSources, plainEnv };
