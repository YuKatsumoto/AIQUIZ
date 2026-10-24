// 共有バンクの補充（フェーズ C2）。
//
// 1 日 1 回（Cloud Run Job + Cloud Scheduler）で runBuildCycle() を呼ぶ。
//   1. 前回までに出した Batch のうち終わったものを回収し、問題を共有アーカイブに「確認待ち（pending）」で入れる。
//   2. 区分（教科×学年×難易度）ごとに、共有バンク＋確認待ちの数を目標と比べ、足りない区分から順に
//      Claude Haiku に問題を作らせる Batch を出す。
// アーカイブに入った問題は、Claude の確認ジョブ（claude-review.js）が合格させたものだけ共有バンクへ入る。
// プロンプトはゲームの 10 問モードと同じもの（data/bank-prompts.json.gz、tools/export_bank_prompts.gd で書き出す）。
//
// Firebase のレイアウト:
//   bank_builder/v1/batches/{batchId}  … {state: submitted|collected, requests, model, ...}
//   bank_builder/v1/spend/{YYYY-MM}    … {usd, requests, input_tokens, output_tokens, questions, ...}

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { canonicalizeQuiz, mergeCandidate } = require('./quiz-bank-service');
const { PRICES, monthKey } = require('./claude-review');

const BUILDER_PATH = 'bank_builder/v1';
const ARCHIVE_PATH = 'quiz_archive/v1/items';
const BANK_PATH = 'quiz_bank/v1/items';
const SOURCE = 'CLAUDE_HAIKU';
const AVOID_LIST_SIZE = 25;
const BATCH_DISCOUNT = 0.5;
const OUTPUT_FORMAT = '\n\n【出力形式】JSON配列のみ出力せよ。マークダウンや説明文は一切不要。'
    + '例: [{"q":"...","c":["A","B","C","D"],"a":0,"e":"...","g":"単元名","t":4.0}]';

function configFromEnv(env = process.env) {
    return {
        model: env.BANK_BUILDER_MODEL || 'claude-haiku-5-5',
        effort: env.BANK_BUILDER_EFFORT || 'medium',
        monthlyBudgetUsd: Math.max(0, Number(env.BANK_BUILDER_MONTHLY_BUDGET_USD || 15)),
        maxCallsPerRun: Math.max(0, Number(env.BANK_BUILDER_MAX_CALLS_PER_RUN || 300)),
        maxCallsPerBucket: Math.max(1, Number(env.BANK_BUILDER_MAX_CALLS_PER_BUCKET || 12)),
        targetPerBucket: Math.max(0, Number(env.BANK_BUILDER_TARGET_PER_BUCKET || 400)),
        // 回収前の Batch の見込み（1 回あたり）。2026-10 の試験では Haiku 5.5 medium 1 回 $0.0025（通常料金）
        estimatedUsdPerCall: Math.max(0.0001, Number(env.BANK_BUILDER_EST_USD_PER_CALL || 0.002)),
        dryRun: env.BANK_BUILDER_DRY_RUN === '1',
    };
}

function loadPrompts(file = path.join(__dirname, 'data', 'bank-prompts.json.gz')) {
    return JSON.parse(zlib.gunzipSync(fs.readFileSync(file)).toString('utf8'));
}

function bucketKey(subject, grade, difficulty) {
    return `${subject}|${grade}|${difficulty}`;
}

function costUsd(model, usage) {
    const price = PRICES[model];
    if (!price || !usage) return 0;
    return (Number(usage.input_tokens || 0) * price.input
        + Number(usage.cache_read_input_tokens || 0) * price.cacheRead
        + Number(usage.cache_creation_input_tokens || 0) * price.input * 1.25
        + Number(usage.output_tokens || 0) * price.output) / 1e6 * BATCH_DISCOUNT;
}

// 返答の文字列から問題の配列を取り出す（```json で囲まれていても読む）
function parseQuestions(text) {
    const trimmed = String(text || '').trim().replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '').trim();
    try {
        const value = JSON.parse(trimmed);
        if (Array.isArray(value)) return value;
        if (value && Array.isArray(value.quizzes)) return value.quizzes;
    } catch (_e) { /* fall through */ }
    const start = trimmed.indexOf('[');
    const end = trimmed.lastIndexOf(']');
    if (start >= 0 && end > start) {
        try {
            const value = JSON.parse(trimmed.slice(start, end + 1));
            if (Array.isArray(value)) return value;
        } catch (_e) { /* not parseable */ }
    }
    return [];
}

function avoidSection(questions) {
    if (!questions.length) return '';
    return '\n\n【すでにある問題（同じ問題・言い換え・数字だけを変えた問題は作らないこと）】\n'
        + questions.map(q => `- ${q}`).join('\n');
}

class BankBuilderJob {
    constructor({ db, anthropic, config = configFromEnv(), prompts = loadPrompts(),
        now = () => new Date(), random = Math.random, log = console.log }) {
        this.db = db;
        this.anthropic = anthropic;
        this.config = config;
        this.prompts = prompts;
        this.now = now;
        this.random = random;
        this.log = log;
    }

    async run() {
        const collected = await this.collect();
        const submitted = await this.submit();
        return { collected, submitted };
    }

    // ---- 回収 ----

    async collect() {
        const summary = { batches: 0, requests: 0, questions: 0, archived: 0, duplicates: 0, invalid: 0,
            errored: 0, usd: 0 };
        const batches = (await this.db.ref(`${BUILDER_PATH}/batches`).once('value')).val() || {};
        for (const [batchId, record] of Object.entries(batches)) {
            if (!record || record.state !== 'submitted') continue;
            const batch = await this.anthropic.messages.batches.retrieve(batchId);
            if (batch.processing_status !== 'ended') continue;
            const usage = { usd: 0, requests: 0, input_tokens: 0, output_tokens: 0, questions: 0 };
            for await (const entry of await this.anthropic.messages.batches.results(batchId)) {
                const request = (record.requests || {})[entry.custom_id];
                if (entry.result.type !== 'succeeded' || !request) {
                    summary.errored += 1;
                    continue;
                }
                const message = entry.result.message;
                usage.requests += 1;
                usage.input_tokens += Number((message.usage || {}).input_tokens || 0);
                usage.output_tokens += Number((message.usage || {}).output_tokens || 0);
                usage.usd += costUsd(record.model, message.usage);
                const text = (message.content || []).filter(b => b.type === 'text').map(b => b.text).join('');
                const outcome = await this._archive(parseQuestions(text), request);
                usage.questions += outcome.archived;
                summary.questions += outcome.total;
                summary.archived += outcome.archived;
                summary.duplicates += outcome.duplicates;
                summary.invalid += outcome.invalid;
            }
            await this._addSpend(usage);
            await this.db.ref(`${BUILDER_PATH}/batches/${batchId}`).update({
                state: 'collected',
                collected_at: Math.floor(this.now().getTime() / 1000),
                usd: Number(usage.usd.toFixed(6)),
                questions: usage.questions,
            });
            summary.batches += 1;
            summary.requests += usage.requests;
            summary.usd += usage.usd;
        }
        summary.usd = Number(summary.usd.toFixed(4));
        return summary;
    }

    async _archive(raws, request) {
        const outcome = { total: raws.length, archived: 0, duplicates: 0, invalid: 0 };
        const nowSeconds = Math.floor(this.now().getTime() / 1000);
        for (const raw of raws) {
            let quiz;
            try {
                if (!raw || typeof raw !== 'object' || !Array.isArray(raw.c) || raw.c.length !== 4) {
                    throw new Error('need 4 choices');
                }
                quiz = canonicalizeQuiz({ ...raw, subject: request.subject, grade: request.grade,
                    difficulty: request.difficulty, src: SOURCE });
            } catch (_e) {
                outcome.invalid += 1;
                continue;
            }
            // 既にある問題（プレイヤーが出会ったもの・前に作ったもの）は上書きしない。
            // undefined を返すとトランザクションは取りやめになり committed が false になる。
            const result = await this.db.ref(`${ARCHIVE_PATH}/${quiz.id}`).transaction(
                current => (current ? undefined : mergeCandidate(null, quiz, nowSeconds)),
            );
            if (result && result.committed) outcome.archived += 1;
            else outcome.duplicates += 1;
        }
        return outcome;
    }

    async _addSpend(usage) {
        if (!usage.requests && !usage.usd) return;
        await this.db.ref(`${BUILDER_PATH}/spend/${monthKey(this.now())}`).transaction(current => {
            const next = { ...(current || {}) };
            for (const [key, value] of Object.entries(usage)) next[key] = Number(next[key] || 0) + value;
            next.usd = Number(Number(next.usd).toFixed(6));
            return next;
        });
    }

    // ---- 送信 ----

    async budgetRemainingUsd() {
        const spent = Number((await this.db.ref(`${BUILDER_PATH}/spend/${monthKey(this.now())}/usd`)
            .once('value')).val() || 0);
        const batches = (await this.db.ref(`${BUILDER_PATH}/batches`).once('value')).val() || {};
        let inFlight = 0;
        for (const record of Object.values(batches)) {
            if (record && record.state === 'submitted') {
                inFlight += Number(record.count || 0) * this.config.estimatedUsdPerCall;
            }
        }
        return this.config.monthlyBudgetUsd - spent - inFlight;
    }

    // 区分ごとの「共有バンク＋確認待ち」の数と、避けてほしい問題文の候補
    async bucketStock() {
        const stock = new Map();
        const add = (item) => {
            if (!item || !item.subject || !item.q) return;
            const key = bucketKey(item.subject, Number(item.grade), item.difficulty);
            const entry = stock.get(key) || { count: 0, questions: [] };
            entry.count += 1;
            entry.questions.push(String(item.q));
            stock.set(key, entry);
        };
        const bank = (await this.db.ref(BANK_PATH).once('value')).val() || {};
        Object.values(bank).forEach(add);
        const pending = (await this.db.ref(ARCHIVE_PATH).orderByChild('status').equalTo('pending')
            .once('value')).val() || {};
        Object.values(pending).forEach(item => {
            // 確認でつまずいた（error を重ねた）ものは数えない
            if (item && item.review && item.review.state === 'error') return;
            add(item);
        });
        return stock;
    }

    // 足りない区分から順に、何回ずつ作るかを決める
    plan(stock, maxCalls) {
        const perPrompt = Number(this.prompts.questions_per_prompt || 4);
        const byBucket = new Map();
        for (const prompt of this.prompts.prompts) {
            const key = bucketKey(prompt.subject, prompt.grade, prompt.difficulty);
            if (!byBucket.has(key)) byBucket.set(key, []);
            byBucket.get(key).push(prompt);
        }
        const needs = [];
        for (const [key, prompts] of byBucket) {
            const have = (stock.get(key) || { count: 0 }).count;
            const deficit = this.config.targetPerBucket - have;
            if (deficit <= 0) continue;
            needs.push({ key, prompts, have, calls: Math.min(this.config.maxCallsPerBucket, Math.ceil(deficit / perPrompt)) });
        }
        // いちばん少ない区分から。1 巡ずつ配って、1 つの区分に偏らないように
        needs.sort((a, b) => a.have - b.have);
        const picked = [];
        let round = 0;
        while (picked.length < maxCalls && needs.some(n => n.calls > round)) {
            for (const need of needs) {
                if (picked.length >= maxCalls) break;
                if (need.calls <= round) continue;
                picked.push({ key: need.key, prompt: need.prompts[round % need.prompts.length] });
            }
            round += 1;
        }
        return picked;
    }

    _sample(list, count) {
        const copy = list.slice();
        for (let i = copy.length - 1; i > 0; i--) {
            const j = Math.floor(this.random() * (i + 1));
            [copy[i], copy[j]] = [copy[j], copy[i]];
        }
        return copy.slice(0, count);
    }

    buildRequest(customId, prompt, avoid) {
        return {
            custom_id: customId,
            params: {
                model: this.config.model,
                max_tokens: 16000,
                system: [{ type: 'text', text: this.prompts.system, cache_control: { type: 'ephemeral' } }],
                messages: [{ role: 'user', content: prompt.prompt + avoidSection(avoid) + OUTPUT_FORMAT }],
                output_config: { effort: this.config.effort },
            },
        };
    }

    async submit() {
        const remaining = await this.budgetRemainingUsd();
        const affordable = Math.floor(Math.max(0, remaining) / this.config.estimatedUsdPerCall);
        const limit = Math.min(this.config.maxCallsPerRun, affordable);
        const summary = { count: 0, batch_id: '', budget_remaining_usd: Number(remaining.toFixed(4)) };
        if (limit < 1) {
            summary.skipped = 'budget';
            return summary;
        }
        const stock = await this.bucketStock();
        const picked = this.plan(stock, limit);
        if (!picked.length) {
            summary.skipped = 'targets_met';
            return summary;
        }
        const requests = [];
        const meta = {};
        picked.forEach((item, index) => {
            const customId = `r${index}`;
            const existing = (stock.get(item.key) || { questions: [] }).questions;
            requests.push(this.buildRequest(customId, item.prompt, this._sample(existing, AVOID_LIST_SIZE)));
            meta[customId] = { subject: item.prompt.subject, grade: item.prompt.grade,
                difficulty: item.prompt.difficulty };
        });
        const buckets = {};
        for (const item of picked) buckets[item.key] = (buckets[item.key] || 0) + 1;
        summary.buckets = Object.keys(buckets).length;
        if (this.config.dryRun) {
            summary.count = requests.length;
            summary.dry_run = true;
            summary.plan = Object.entries(buckets).slice(0, 10)
                .map(([key, calls]) => ({ bucket: key, have: (stock.get(key) || { count: 0 }).count, calls }));
            summary.sample = requests[0];
            return summary;
        }
        const batch = await this.anthropic.messages.batches.create({ requests });
        await this.db.ref(`${BUILDER_PATH}/batches/${batch.id}`).set({
            state: 'submitted',
            submitted_at: Math.floor(this.now().getTime() / 1000),
            model: this.config.model,
            effort: this.config.effort,
            count: requests.length,
            requests: meta,
        });
        summary.count = requests.length;
        summary.batch_id = batch.id;
        return summary;
    }
}

module.exports = { BUILDER_PATH, BankBuilderJob, SOURCE, configFromEnv, loadPrompts, parseQuestions };
