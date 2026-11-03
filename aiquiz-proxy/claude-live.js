// 試合中の問題づくりを Claude に頼む（/claude と /claude-stream）。
//
// ゲームはモデルを指定せず、用途（task）とプロンプトだけを送る。モデル・考える深さ・出力の上限は
// ここのタスク表で決める（CLAUDE_TASK_MODELS_JSON で用途ごとに差し替えられる）。
// 利用者は小学生なので、どの用途でも system の先頭に子ども向けの安全指示を必ず付ける。
// これはゲームからは外せない（Anthropic の未成年向けの利用条件に合わせるため）。
//
// 2026-11-03 の比較（AIQUIZ-Godot/docs/evals/2026-11-03_quiz_generation_gemini_vs_claude.md）:
//   Sonnet 5.5（effort low）は今の Gemini 3.6 Flash と正しさ・一対比較で同等、最初の 1 問まで約 2 秒。
//   Haiku 5.5 は思考ありだと最初の 1 問まで約 17 秒（ゲームの 20 秒の無通信タイムアウトに近い）、
//   思考なしだと合格率が 70% に下がったので使わない。

const CHILD_SAFETY = 'このサービスの利用者は日本の小学生です。暴力・性的な表現・差別・危険な行為・自傷・'
    + '個人情報の質問・特定の商品や企業の宣伝など、子どもに不適切な内容は出力しないでください。'
    + '事実に自信のない内容は出題しないでください。';

// structured outputs の根は object にし、配列は items に入れる。ゲームへは items の配列だけを返す。
function itemsSchema(properties, required) {
    return {
        type: 'object',
        properties: {
            items: {
                type: 'array',
                items: { type: 'object', properties, required, additionalProperties: false },
            },
        },
        required: ['items'],
        additionalProperties: false,
    };
}

const SCHEMAS = {
    // online_fetch.gd の fetch_explanations_batch
    explain: itemsSchema({ id: { type: 'integer' }, e: { type: 'string' } }, ['id', 'e']),
    // quiz_validator.gd の validate_answers_llm
    validate: itemsSchema({
        id: { type: 'integer' },
        correct_answer: { type: 'integer' },
        claimed_ok: { type: 'boolean' },
        grade_ok: { type: 'boolean' },
        issue: { type: 'string' },
    }, ['id', 'correct_answer', 'claimed_ok', 'grade_ok', 'issue']),
    // quiz_optimizer.gd の _fetch_evaluation
    evaluate: itemsSchema({
        id: { type: 'integer' },
        rating: { type: 'string', enum: ['good', 'bad'] },
        reason: { type: 'string' },
    }, ['id', 'rating', 'reason']),
};

const DEFAULT_TASKS = {
    generate: { model: 'claude-sonnet-5-5', effort: 'low', maxTokens: 8000 },
    explain: { model: 'claude-sonnet-5-5', effort: 'low', maxTokens: 4000 },
    validate: { model: 'claude-sonnet-5-5', effort: 'low', maxTokens: 8000 },
    evaluate: { model: 'claude-sonnet-5-5', effort: 'low', maxTokens: 4000 },
};

// サーバー側のフォールバック（拒否されたら別のモデルでやり直す）が使えるモデル。Haiku 5.5 には無い。
const FALLBACK_MODELS = new Set(['claude-sonnet-5-5', 'claude-opus-5-5']);
const FALLBACK_BETA = 'server-side-fallback-2026-07-01';

// 100万トークンあたりの標準料金（USD）。cacheRead はキャッシュ読み込み、書き込みは input の 1.25 倍。
// claude-sonnet-5 / claude-opus-4-8 はフォールバック先として返ってくることがある。
const PRICES = {
    'claude-opus-5-5': { input: 4.0, output: 20.0, cacheRead: 0.20 },
    'claude-sonnet-5-5': { input: 2.0, output: 10.0, cacheRead: 0.20 },
    'claude-sonnet-5': { input: 2.0, output: 10.0, cacheRead: 0.20 },
    'claude-opus-4-8': { input: 5.0, output: 25.0, cacheRead: 0.50 },
    'claude-haiku-5-5': { input: 0.10, output: 0.50, cacheRead: 0.01 },
};

const MAX_PROMPT_CHARS = 24000;
const MAX_SYSTEM_CHARS = 8000;

class ClaudeGuardError extends Error {}

function tasksFromEnv(env = process.env) {
    const tasks = {};
    for (const [name, config] of Object.entries(DEFAULT_TASKS)) tasks[name] = { ...config };
    if (env.CLAUDE_TASK_MODELS_JSON) {
        for (const [name, override] of Object.entries(JSON.parse(env.CLAUDE_TASK_MODELS_JSON))) {
            if (tasks[name]) Object.assign(tasks[name], override);
        }
    }
    return tasks;
}

// ゲームの本文を確かめる。受け付けるのは {task, prompt, system?} だけ。
function sanitizeClaudeRequest(rawBody, tasks) {
    let body;
    try {
        body = typeof rawBody === 'string' ? JSON.parse(rawBody) : rawBody;
    } catch (_error) {
        throw new ClaudeGuardError('invalid_json');
    }
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new ClaudeGuardError('invalid_body');
    for (const key of Object.keys(body)) {
        if (!['task', 'prompt', 'system'].includes(key)) throw new ClaudeGuardError(`unknown_field:${key}`);
    }
    if (!Object.prototype.hasOwnProperty.call(tasks, body.task)) throw new ClaudeGuardError('unknown_task');
    if (typeof body.prompt !== 'string' || !body.prompt.trim()) throw new ClaudeGuardError('prompt_required');
    if (body.prompt.length > MAX_PROMPT_CHARS) throw new ClaudeGuardError('prompt_too_long');
    const system = body.system === undefined ? '' : body.system;
    if (typeof system !== 'string') throw new ClaudeGuardError('system_not_string');
    if (system.length > MAX_SYSTEM_CHARS) throw new ClaudeGuardError('system_too_long');
    return { task: body.task, prompt: body.prompt, system };
}

function buildParams(request, tasks) {
    const config = tasks[request.task];
    const outputConfig = { effort: config.effort };
    if (SCHEMAS[request.task]) {
        outputConfig.format = { type: 'json_schema', schema: SCHEMAS[request.task] };
    }
    const params = {
        model: config.model,
        max_tokens: config.maxTokens,
        system: request.system ? `${CHILD_SAFETY}\n\n${request.system}` : CHILD_SAFETY,
        messages: [{ role: 'user', content: request.prompt }],
        output_config: outputConfig,
    };
    if (FALLBACK_MODELS.has(config.model)) {
        params.betas = [FALLBACK_BETA];
        params.fallbacks = 'default';
    }
    return params;
}

function costUsd(model, usage) {
    const price = PRICES[model];
    if (!price || !usage) return 0;
    return (Number(usage.input_tokens || 0) * price.input
        + Number(usage.cache_creation_input_tokens || 0) * price.input * 1.25
        + Number(usage.cache_read_input_tokens || 0) * price.cacheRead
        + Number(usage.output_tokens || 0) * price.output) / 1e6;
}

// usage-budget.js の記録の形（Gemini の usageMetadata と同じ名前）にそろえる
function budgetUsage(usage) {
    return {
        promptTokenCount: Number(usage.input_tokens || 0) + Number(usage.cache_creation_input_tokens || 0)
            + Number(usage.cache_read_input_tokens || 0),
        candidatesTokenCount: Number(usage.output_tokens || 0),
        thoughtsTokenCount: 0,
    };
}

function messageText(message) {
    return (message.content || []).filter(block => block.type === 'text').map(block => block.text).join('');
}

// structured outputs の {items:[...]} を、ゲームが読む配列の JSON にする
function gameText(task, text) {
    if (!SCHEMAS[task]) return text;
    try {
        const parsed = JSON.parse(text);
        if (parsed && Array.isArray(parsed.items)) return JSON.stringify(parsed.items);
    } catch (_error) {
        // 読めないときはそのまま返し、ゲーム側の読み取りに任せる
    }
    return text;
}

// Anthropic の失敗を、ゲームがすでに扱える状態に変える（429 は待つ、503 は共有バンクで続ける）
function errorStatus(error) {
    const status = Number(error && error.status);
    if (status === 429) return 429;
    if (status === 529 || status >= 500 || !status) return 503;
    return 502;
}

// recordUsage(model, usage) は費用（USD）を記録し、その額を返す
function createClaudeHandlers({ client, tasks = tasksFromEnv(), recordUsage, log = console, keepAliveMs = 5000 }) {
    function guard(req, res, next) {
        try {
            req.claudeRequest = sanitizeClaudeRequest(req.body, tasks);
        } catch (error) {
            if (error instanceof ClaudeGuardError) {
                return res.status(400).json({ error: `Bad Request: ${error.message}` });
            }
            throw error;
        }
        next();
    }

    function record(kind, request, message, req, extra) {
        if (!message || !message.usage) return;
        const model = message.model || tasks[request.task].model;
        const usd = recordUsage(model, message.usage, req);
        log.log(JSON.stringify({
            type: 'claude_usage', kind, task: request.task, model,
            input_tokens: message.usage.input_tokens, output_tokens: message.usage.output_tokens,
            cache_read_input_tokens: message.usage.cache_read_input_tokens,
            stop_reason: message.stop_reason, usd: Number(usd.toFixed(6)),
            ts: new Date().toISOString(), ...(extra || {}),
        }));
    }

    async function generate(req, res) {
        const request = req.claudeRequest;
        let message;
        try {
            message = await client.beta.messages.create(buildParams(request, tasks));
        } catch (error) {
            const status = errorStatus(error);
            log.error(JSON.stringify({ type: 'claude_error', task: request.task, status: error.status, error: error.message }));
            return res.status(status).json({ error: 'claude_unavailable' });
        }
        record('generate', request, message, req);
        if (message.stop_reason === 'refusal') {
            return res.status(422).json({ error: 'refusal', model: message.model });
        }
        res.json({
            text: gameText(request.task, messageText(message)),
            stop_reason: message.stop_reason,
            model: message.model,
        });
    }

    async function stream(req, res) {
        const request = req.claudeRequest;
        const send = payload => res.write(`data: ${JSON.stringify(payload)}\n\n`);
        let started = false;
        let keepAlive = null;
        const startSse = () => {
            if (started) return;
            started = true;
            res.setHeader('Content-Type', 'text/event-stream');
            res.setHeader('Cache-Control', 'no-cache');
            res.setHeader('Connection', 'keep-alive');
            res.setHeader('X-Accel-Buffering', 'no');
            res.flushHeaders();
        };
        let closed = false;
        res.on('close', () => { closed = true; });
        let messageStream = null;
        try {
            messageStream = client.beta.messages.stream(buildParams(request, tasks));
            // 考えているあいだ文字が来なくても、ゲームの 20 秒の無通信タイムアウトで切れないようにする
            keepAlive = setInterval(() => {
                if (started && !closed) res.write(': keep-alive\n\n');
            }, keepAliveMs);
            if (keepAlive.unref) keepAlive.unref();
            for await (const event of messageStream) {
                if (closed) {
                    messageStream.abort();
                    break;
                }
                startSse();
                if (event.type === 'content_block_delta' && event.delta && event.delta.type === 'text_delta') {
                    send({ type: 'text', text: event.delta.text });
                }
            }
            if (closed) {
                return;
            }
            const message = await messageStream.finalMessage();
            record('stream', request, message, req);
            startSse();
            if (message.stop_reason === 'refusal') {
                send({ type: 'error', error: 'refusal' });
            } else {
                send({ type: 'done', stop_reason: message.stop_reason });
            }
            res.end();
        } catch (error) {
            if (messageStream) {
                // 途中で止まった分も、届いていれば費用に数える
                const partial = messageStream.currentMessage;
                if (partial && partial.usage) record('stream_partial', request, partial, req, { error: error.message });
            }
            log.error(JSON.stringify({ type: 'claude_error', task: request.task, status: error.status, error: error.message }));
            if (!started) {
                if (!res.headersSent) res.status(errorStatus(error)).json({ error: 'claude_unavailable' });
                return;
            }
            if (!closed) {
                send({ type: 'error', error: 'claude_unavailable' });
                res.end();
            }
        } finally {
            if (keepAlive) clearInterval(keepAlive);
        }
    }

    return { guard, generate, stream };
}

module.exports = {
    CHILD_SAFETY, ClaudeGuardError, DEFAULT_TASKS, PRICES, SCHEMAS,
    budgetUsage, buildParams, costUsd, createClaudeHandlers, gameText, sanitizeClaudeRequest, tasksFromEnv,
};
