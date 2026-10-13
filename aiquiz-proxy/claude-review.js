// 共有バンクに入れる前の Claude 確認（案1）。
//
// 1日1回（Cloud Run Job + Cloud Scheduler）で runReviewCycle() を呼ぶ。
//   1. 前回までに出した Batch のうち終わったものを回収し、判定を共有アーカイブへ反映する。
//   2. 保留（pending）の問題を Batch API に出す。正解は伏せて Claude に解かせる。
// 合格（Claude の答え = 登録の正解、指摘なし、自信あり）だけを quiz_bank へ昇格し、
// 不一致や指摘ありは bad にする。費用は月の上限と1回あたりの件数上限で抑える。
//
// Firebase のレイアウト:
//   quiz_archive/v1/items/{id}.review  … {state, batch_id, verdict, answer, issues, note, ...}
//   quiz_review/v1/batches/{batchId}   … {state: submitted|collected, ids, model, ...}
//   quiz_review/v1/spend/{YYYY-MM}     … {usd, requests, input_tokens, output_tokens, ...}

const crypto = require('crypto');
const { reusableRecord } = require('./quiz-bank-service');

const ARCHIVE_PATH = 'quiz_archive/v1/items';
const BANK_PATH = 'quiz_bank/v1/items';
const REVIEW_PATH = 'quiz_review/v1';
const MAX_ATTEMPTS = 2;
const ISSUE_CODES = [
    'no_correct',
    'multiple_correct',
    'ambiguous',
    'factual_error',
    'out_of_grade',
    'inappropriate',
];

// 100万トークンあたりの標準料金（USD）。Batch はこの半額。
// cacheRead はキャッシュ読み込み、キャッシュ書き込みは input の 1.25 倍（5分）。
const PRICES = {
    'claude-opus-5-5': { input: 4.0, output: 20.0, cacheRead: 0.20 },
    'claude-sonnet-5-5': { input: 2.0, output: 10.0, cacheRead: 0.20 },
    'claude-haiku-5-5': { input: 0.10, output: 0.50, cacheRead: 0.01 },
};
const BATCH_DISCOUNT = 0.5;

const SYSTEM_PROMPT = `あなたは日本の小学校の教員で、子ども向けクイズ（2択または4択）の品質検査をしています。
各問題の正解は伏せてあります。次の手順で確認し、指定のJSONだけを返してください。

1. 問題を自分で解き、最も正しい選択肢の番号（0始まり）を answer に入れる。
2. 次に当てはまる問題点があれば issues に入れる。なければ空配列。
   - no_correct: 正しい選択肢が1つもない
   - multiple_correct: 正しい選択肢が2つ以上ある、または解釈しだいで正解が変わる
   - ambiguous: 問題文があいまい・条件不足で、1つに決められない
   - factual_error: 問題文や選択肢の前提に事実の誤りがある
   - out_of_grade: その学年の子どもがまだ習っていない知識がないと解けない
   - inappropriate: 子ども向けとして不適切な内容
3. confidence に自分の答えへの自信を high / medium / low で入れる。
4. note に判断の根拠を日本語50文字以内で書く。

判断の目安:
- 学年の範囲は小学校学習指導要領に照らす。少し発展的な程度なら out_of_grade にしない。
- 英語の問題は、英語の正しさと、その学年の英語の学習内容で判断する。
- 言い回しが少し硬い・面白みがない、といった好みの問題は指摘しない。正しさと公平さだけを見る。`;

const OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
        answer: { type: 'integer' },
        issues: { type: 'array', items: { type: 'string', enum: ISSUE_CODES } },
        confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        note: { type: 'string' },
    },
    required: ['answer', 'issues', 'confidence', 'note'],
    additionalProperties: false,
};

function configFromEnv(env = process.env) {
    return {
        model: env.CLAUDE_REVIEW_MODEL || 'claude-opus-5-5',
        effort: env.CLAUDE_REVIEW_EFFORT || 'medium',
        maxPerRun: Math.max(0, Number(env.CLAUDE_REVIEW_MAX_PER_RUN || 300)),
        monthlyBudgetUsd: Math.max(0, Number(env.CLAUDE_REVIEW_MONTHLY_BUDGET_USD || 25)),
        // 回収前の Batch の費用見込み（1問あたり）。2026-10 の50問お試しの実費は $0.004/問
        // （Opus 5.5・effort medium）。少し余裕を持たせて $0.005。
        estimatedUsdPerItem: Math.max(0.0001, Number(env.CLAUDE_REVIEW_EST_USD_PER_ITEM || 0.005)),
        // 1: これまでクライアントの good だけで共有バンクに入った問題も確認し直す
        includeUnreviewedGood: env.CLAUDE_REVIEW_INCLUDE_GOOD === '1',
        dryRun: env.CLAUDE_REVIEW_DRY_RUN === '1',
    };
}

function monthKey(date = new Date()) {
    return date.toISOString().slice(0, 7);
}

function contentHash(item) {
    return crypto.createHash('sha256')
        .update(JSON.stringify([item.q, item.c, item.a, item.e || '']))
        .digest('hex')
        .slice(0, 16);
}

function costUsd(model, usage) {
    const price = PRICES[model];
    if (!price || !usage) return 0;
    const perToken = rate => rate / 1e6 * BATCH_DISCOUNT;
    return Number(usage.input_tokens || 0) * perToken(price.input)
        + Number(usage.cache_creation_input_tokens || 0) * perToken(price.input * 1.25)
        + Number(usage.cache_read_input_tokens || 0) * perToken(price.cacheRead)
        + Number(usage.output_tokens || 0) * perToken(price.output);
}

function buildRequest(id, item, config) {
    const choices = (item.c || []).map((text, index) => ({ index, text }));
    const payload = {
        subject: item.subject,
        grade: `小学${item.grade}年生`,
        difficulty: item.difficulty,
        unit: item.genre || '',
        question: item.q,
        choices,
    };
    return {
        custom_id: id,
        params: {
            model: config.model,
            max_tokens: 4096,
            system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
            messages: [{ role: 'user', content: JSON.stringify(payload, null, 2) }],
            output_config: {
                effort: config.effort,
                format: { type: 'json_schema', schema: OUTPUT_SCHEMA },
            },
        },
    };
}

// Claude の返答（文字列 JSON）を判定にする。読めなければ null。
function parseVerdict(message, item) {
    if (!message || message.stop_reason !== 'end_turn') return null;
    const block = (message.content || []).find(b => b.type === 'text');
    if (!block) return null;
    let out;
    try {
        out = JSON.parse(block.text);
    } catch (_error) {
        return null;
    }
    const choiceCount = (item.c || []).length;
    if (!Number.isInteger(out.answer) || out.answer < 0 || out.answer >= choiceCount) return null;
    if (!Array.isArray(out.issues)) return null;
    const issues = out.issues.filter(code => ISSUE_CODES.includes(code));
    const note = String(out.note || '').slice(0, 200);
    const confidence = ['high', 'medium', 'low'].includes(out.confidence) ? out.confidence : 'low';
    let verdict = 'pass';
    if (out.answer !== Number(item.a) || issues.length > 0) {
        verdict = 'fail';
    } else if (confidence === 'low') {
        verdict = 'unsure';
    }
    return { verdict, answer: out.answer, issues, confidence, note };
}

function failReason(result) {
    const parts = [];
    if (result.issues.length) parts.push(result.issues.join(','));
    if (result.verdict === 'fail' && !result.issues.length) parts.push(`answer=${result.answer}`);
    if (result.note) parts.push(result.note);
    return `claude: ${parts.join(' / ')}`.slice(0, 500);
}

class ClaudeReviewJob {
    constructor({ db, anthropic, config = configFromEnv(), now = () => new Date(), log = console.log }) {
        this.db = db;
        this.anthropic = anthropic;
        this.config = config;
        this.now = now;
        this.log = log;
    }

    async run() {
        const collected = await this.collect();
        const submitted = await this.submit();
        return { collected, submitted };
    }

    // ---- 回収 ----

    async collect() {
        const summary = { batches: 0, pass: 0, fail: 0, unsure: 0, error: 0, usd: 0 };
        const batches = (await this.db.ref(`${REVIEW_PATH}/batches`).once('value')).val() || {};
        let bankChanged = false;
        for (const [batchId, record] of Object.entries(batches)) {
            if (!record || record.state !== 'submitted') continue;
            const batch = await this.anthropic.messages.batches.retrieve(batchId);
            if (batch.processing_status !== 'ended') continue;

            const seen = new Set();
            const usage = { usd: 0, requests: 0, input_tokens: 0, output_tokens: 0,
                cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
            for await (const entry of await this.anthropic.messages.batches.results(batchId)) {
                seen.add(entry.custom_id);
                if (entry.result.type === 'succeeded') {
                    const message = entry.result.message;
                    const u = message.usage || {};
                    usage.requests += 1;
                    for (const key of ['input_tokens', 'output_tokens',
                        'cache_read_input_tokens', 'cache_creation_input_tokens']) {
                        usage[key] += Number(u[key] || 0);
                    }
                    usage.usd += costUsd(record.model, u);
                    const outcome = await this._applyResult(entry.custom_id, batchId, message, record);
                    summary[outcome] += 1;
                    if (outcome === 'pass' || outcome === 'fail') bankChanged = true;
                } else {
                    await this._markError(entry.custom_id, batchId, entry.result.type);
                    summary.error += 1;
                }
            }
            for (const id of Object.keys(record.ids || {})) {
                if (!seen.has(id)) {
                    await this._markError(id, batchId, 'missing');
                    summary.error += 1;
                }
            }
            await this._addSpend(usage);
            await this.db.ref(`${REVIEW_PATH}/batches/${batchId}`).update({
                state: 'collected',
                collected_at: Math.floor(this.now().getTime() / 1000),
                usd: Number(usage.usd.toFixed(6)),
            });
            summary.batches += 1;
            summary.usd += usage.usd;
        }
        if (bankChanged) {
            await this.db.ref('quiz_bank/v1/meta/revision').transaction(current => Number(current || 0) + 1);
        }
        summary.usd = Number(summary.usd.toFixed(4));
        return summary;
    }

    async _applyResult(id, batchId, message, record) {
        const archiveRef = this.db.ref(`${ARCHIVE_PATH}/${id}`);
        const current = (await archiveRef.once('value')).val();
        if (!current) return 'error';
        const reviewedHash = record.hashes ? record.hashes[id] : current.review && current.review.content_hash;
        if (reviewedHash && reviewedHash !== contentHash(current)) {
            // 確認に出した後で内容が変わっていた（送信と凍結の間の競合）。次回もう一度出す。
            await this._markError(id, batchId, 'content_changed');
            return 'error';
        }
        const result = parseVerdict(message, current);
        if (!result) {
            await this._markError(id, batchId, message ? `unparsed:${message.stop_reason}` : 'unparsed');
            return 'error';
        }
        const nowSeconds = Math.floor(this.now().getTime() / 1000);
        const review = {
            state: 'done',
            batch_id: batchId,
            model: record.model,
            effort: record.effort,
            verdict: result.verdict,
            answer: result.answer,
            issues: result.issues,
            confidence: result.confidence,
            note: result.note,
            content_hash: contentHash(current),
            attempts: Number((current.review && current.review.attempts) || 0) + 1,
            reviewed_at: nowSeconds,
        };
        const transaction = await archiveRef.transaction(item => {
            if (!item) return item;
            const next = { ...item, review };
            if (result.verdict === 'pass' && !item.bad_ever) {
                next.status = 'good';
                next.last_evaluated = nowSeconds;
                next.evaluation_reason = 'claude: pass';
            } else if (result.verdict === 'fail') {
                next.status = 'bad';
                next.bad_ever = true;
                next.last_evaluated = nowSeconds;
                next.evaluation_reason = failReason(result);
            }
            return next;
        });
        const archive = transaction.snapshot.val();
        const bankRef = this.db.ref(`${BANK_PATH}/${id}`);
        if (archive.status === 'good' && result.verdict === 'pass') {
            await bankRef.set(reusableRecord(archive));
        } else if (archive.status === 'bad') {
            await bankRef.remove();
        }
        return result.verdict;
    }

    async _markError(id, batchId, reason) {
        await this.db.ref(`${ARCHIVE_PATH}/${id}`).transaction(item => {
            if (!item) return item;
            const prior = item.review || {};
            return {
                ...item,
                review: {
                    ...prior,
                    state: 'error',
                    batch_id: batchId,
                    error: String(reason).slice(0, 100),
                    attempts: Number(prior.attempts || 0) + 1,
                },
            };
        });
    }

    async _addSpend(usage) {
        if (!usage.requests && !usage.usd) return;
        await this.db.ref(`${REVIEW_PATH}/spend/${monthKey(this.now())}`).transaction(current => {
            const next = { ...(current || {}) };
            for (const [key, value] of Object.entries(usage)) {
                next[key] = Number(next[key] || 0) + value;
            }
            next.usd = Number(Number(next.usd).toFixed(6));
            return next;
        });
    }

    // ---- 送信 ----

    async budgetRemainingUsd() {
        const spent = Number((await this.db.ref(`${REVIEW_PATH}/spend/${monthKey(this.now())}/usd`)
            .once('value')).val() || 0);
        const batches = (await this.db.ref(`${REVIEW_PATH}/batches`).once('value')).val() || {};
        let inFlight = 0;
        for (const record of Object.values(batches)) {
            if (record && record.state === 'submitted') {
                inFlight += Number(record.count || 0) * this.config.estimatedUsdPerItem;
            }
        }
        return this.config.monthlyBudgetUsd - spent - inFlight;
    }

    async selectCandidates(limit) {
        const statuses = this.config.includeUnreviewedGood ? ['pending', 'good'] : ['pending'];
        const picked = [];
        for (const status of statuses) {
            const snapshot = await this.db.ref(ARCHIVE_PATH)
                .orderByChild('status').equalTo(status)
                .limitToFirst(Math.max(limit * 4, 50))
                .once('value');
            const items = snapshot.val() || {};
            for (const [id, item] of Object.entries(items)) {
                if (!item || item.bad_ever) continue;
                const review = item.review || {};
                if (review.state === 'submitted' || review.state === 'done') continue;
                if (review.state === 'error' && Number(review.attempts || 0) >= MAX_ATTEMPTS) continue;
                if (!Array.isArray(item.c) || !Number.isInteger(Number(item.a))) continue;
                picked.push([id, item]);
            }
        }
        // プレイヤーの good 票が多い問題、よく生成される問題を優先する
        picked.sort(([, a], [, b]) =>
            Number(b.good_votes || 0) - Number(a.good_votes || 0)
            || Number(b.seen_count || 0) - Number(a.seen_count || 0));
        return picked.slice(0, limit);
    }

    async submit() {
        const remaining = await this.budgetRemainingUsd();
        const affordable = Math.floor(Math.max(0, remaining) / this.config.estimatedUsdPerItem);
        const limit = Math.min(this.config.maxPerRun, affordable);
        const summary = { count: 0, batch_id: '', budget_remaining_usd: Number(remaining.toFixed(4)) };
        if (limit < 1) {
            summary.skipped = 'budget';
            return summary;
        }
        const candidates = await this.selectCandidates(limit);
        if (!candidates.length) {
            summary.skipped = 'no_candidates';
            return summary;
        }
        if (this.config.dryRun) {
            summary.count = candidates.length;
            summary.dry_run = true;
            summary.sample = candidates.slice(0, 3).map(([id, item]) => buildRequest(id, item, this.config));
            return summary;
        }

        const hashes = {};
        for (const [id, item] of candidates) hashes[id] = contentHash(item);
        const batch = await this.anthropic.messages.batches.create({
            requests: candidates.map(([id, item]) => buildRequest(id, item, this.config)),
        });
        const nowSeconds = Math.floor(this.now().getTime() / 1000);
        const ids = Object.fromEntries(candidates.map(([id]) => [id, true]));
        await this.db.ref(`${REVIEW_PATH}/batches/${batch.id}`).set({
            state: 'submitted',
            submitted_at: nowSeconds,
            model: this.config.model,
            effort: this.config.effort,
            count: candidates.length,
            ids,
            hashes,
        });
        for (const [id] of candidates) {
            await this.db.ref(`${ARCHIVE_PATH}/${id}`).transaction(current => {
                if (!current) return current;
                const prior = current.review || {};
                return {
                    ...current,
                    review: {
                        attempts: Number(prior.attempts || 0),
                        state: 'submitted',
                        batch_id: batch.id,
                        content_hash: hashes[id],
                        submitted_at: nowSeconds,
                    },
                };
            });
        }
        summary.count = candidates.length;
        summary.batch_id = batch.id;
        return summary;
    }
}

module.exports = {
    ClaudeReviewJob,
    ISSUE_CODES,
    OUTPUT_SCHEMA,
    PRICES,
    SYSTEM_PROMPT,
    buildRequest,
    configFromEnv,
    contentHash,
    costUsd,
    monthKey,
    parseVerdict,
};
