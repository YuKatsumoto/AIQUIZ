const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { createFirebaseDatabase, createQuizBankRouter } = require('./quiz-bank-service');
const { GuardError, sanitizeGeminiRequest } = require('./gemini-guard');
const { UsageBudget } = require('./usage-budget');
const { DeviceAuth } = require('./device-auth');
const { DeviceLimits } = require('./device-limits');
const { newCountFor } = require('./round-plan');

const app = express();
// Cloud Run terminates TLS one hop in front of the container. Trust exactly that
// proxy so per-IP rate limiting uses the real client address.
app.set('trust proxy', 1);
app.use(cors());
// すべてのリクエストボディをテキストとして受け取る。ゲームのプロンプトは最大でも十数KB。
app.use(express.text({ type: '*/*', limit: '64kb' }));

// ========================================
// Layer 1: APP_SECRET トークン認証
// ========================================
const APP_SECRET = process.env.APP_SECRET || '';

function authMiddleware(req, res, next) {
    if (!APP_SECRET) {
        // サーバー側にAPP_SECRETが未設定の場合はスキップ（開発用）
        return next();
    }
    const clientSecret = req.headers['x-app-secret'] || '';
    if (clientSecret !== APP_SECRET) {
        return res.status(403).json({ error: 'Forbidden: Invalid app secret' });
    }
    next();
}

// ========================================
// Layer 2: レート制限（IPごと）
// ========================================
// Gemini と共有バンクで枠を分ける。共有バンクのページ取得が Gemini の枠を食わないように。
function limiter(max) {
    return rateLimit({
        windowMs: 60 * 1000,
        max,
        standardHeaders: true,
        legacyHeaders: false,
        // Cloud Run also provides the standardized Forwarded header. req.ip is
        // intentionally derived from X-Forwarded-For via trust proxy above.
        validate: { forwardedHeader: false },
        message: { error: 'Too many requests. Please wait a moment.' },
        handler: (req, res, next, options) => {
            deviceLimits.recordDenial('rate_limited');
            res.status(options.statusCode).send(options.message);
        },
    });
}
const geminiLimiter = limiter(30);
const bankLimiter = limiter(120);
// 許可証の発行。学校の教室（1 つの IP から数十台）でも足りるよう 1 時間 200 回まで。
const sessionLimiter = rateLimit({
    windowMs: 60 * 60 * 1000,
    max: Number(process.env.SESSION_PER_IP_PER_HOUR || 200),
    standardHeaders: true,
    legacyHeaders: false,
    validate: { forwardedHeader: false },
    message: { error: 'Too many sessions from this network. Please wait a moment.' },
    handler: (req, res, next, options) => {
        deviceLimits.recordDenial('session_rate_limited');
        res.status(options.statusCode).send(options.message);
    },
});

// ========================================
// Layer 3: モデル・本文の制限（gemini-guard.js）
// ========================================
function guardGemini(req, res, next) {
    const model = String(req.query.model || '');
    try {
        req.geminiModel = model;
        req.geminiBody = sanitizeGeminiRequest(model, req.body);
    } catch (error) {
        if (error instanceof GuardError) {
            return res.status(400).json({ error: `Bad Request: ${error.message}` });
        }
        throw error;
    }
    next();
}

// ========================================
// Layer 4: 日・月の予算（usage-budget.js）
// ========================================
const budget = UsageBudget.fromEnv(process.env, process.env.FIREBASE_DB_URL ? createFirebaseDatabase : null);

async function budgetGate(req, res, next) {
    let verdict;
    try {
        verdict = await budget.check();
    } catch (error) {
        return res.status(500).json({ error: `Budget check failed: ${error.message}` });
    }
    if (!verdict.ok) {
        console.warn(JSON.stringify({ type: 'gemini_budget_block', reason: verdict.reason,
            daily_usd: verdict.dailyUsd, monthly_usd: verdict.monthlyUsd }));
        deviceLimits.recordDenial(verdict.reason);
        res.setHeader('Retry-After', String(verdict.retryAfterSec));
        return res.status(503).json({ error: verdict.reason, retry_after_sec: verdict.retryAfterSec });
    }
    next();
}

// ========================================
// Layer 5: 端末ごとの許可証と上限（device-auth.js / device-limits.js）
// ========================================
// DEVICE_TOKEN_KEY が無いとき（手元の開発）は許可証を確かめない。
// DEVICE_TOKEN_REQUIRED=0 にすると、許可証が無いリクエストも通す（付いていれば数える）。
const firebaseFactory = process.env.FIREBASE_DB_URL ? createFirebaseDatabase : null;
const deviceAuth = DeviceAuth.fromEnv(process.env);
const deviceRequired = deviceAuth !== null && process.env.DEVICE_TOKEN_REQUIRED !== '0';
const deviceLimits = DeviceLimits.fromEnv(process.env, firebaseFactory);
if (!deviceAuth) {
    console.warn('[device] DEVICE_TOKEN_KEY is not set: device tokens are disabled');
}

async function deviceGate(req, res, next) {
    if (!deviceAuth) return next();
    const device = deviceAuth.verify(req.headers['x-device-token']);
    if (!device) {
        if (deviceRequired) {
            deviceLimits.recordDenial('device_token');
            return res.status(401).json({ error: 'device_token' });
        }
        return next();
    }
    req.device = { ...device, ipKey: deviceAuth.ipKey(req.ip) };
    let verdict;
    try {
        verdict = await deviceLimits.check(req.device);
    } catch (error) {
        return res.status(500).json({ error: `Device check failed: ${error.message}` });
    }
    if (!verdict.ok) {
        console.warn(JSON.stringify({ type: 'device_limit_block', reason: verdict.reason, iid: device.iid }));
        deviceLimits.recordDenial(verdict.reason);
        if (verdict.retryAfterSec) res.setHeader('Retry-After', String(verdict.retryAfterSec));
        return res.status(verdict.status).json({ error: verdict.reason, retry_after_sec: verdict.retryAfterSec });
    }
    next();
}

function extractUsageMetadata(payload) {
    if (!payload || typeof payload !== 'object') {
        return null;
    }
    const usage = payload.usageMetadata || payload.usage_metadata;
    if (!usage || typeof usage !== 'object') {
        return null;
    }
    return {
        promptTokenCount: Number(usage.promptTokenCount || usage.prompt_token_count || 0),
        candidatesTokenCount: Number(usage.candidatesTokenCount || usage.candidates_token_count || 0),
        thoughtsTokenCount: Number(usage.thoughtsTokenCount || usage.thoughts_token_count || 0),
        totalTokenCount: Number(usage.totalTokenCount || usage.total_token_count || 0),
        cachedContentTokenCount: Number(usage.cachedContentTokenCount || usage.cached_content_token_count || 0)
    };
}

function logGeminiUsage(kind, model, usage, extra, device) {
    if (!usage) {
        return;
    }
    const usd = budget.record(model, usage);
    if (device) deviceLimits.record(device, usd);
    console.log(JSON.stringify({
        type: 'gemini_usage',
        kind: kind,
        model: model,
        promptTokenCount: usage.promptTokenCount,
        candidatesTokenCount: usage.candidatesTokenCount,
        thoughtsTokenCount: usage.thoughtsTokenCount,
        totalTokenCount: usage.totalTokenCount,
        cachedContentTokenCount: usage.cachedContentTokenCount,
        usd: Number(usd.toFixed(6)),
        ts: new Date().toISOString(),
        ...(extra || {})
    }));
}

function extractUsageFromSseChunk(chunk, lastUsage) {
    let usage = lastUsage;
    const lines = String(chunk).split(/\r?\n/);
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith('data:')) {
            if (trimmed.startsWith('{')) {
                try {
                    const parsed = JSON.parse(trimmed);
                    const found = extractUsageMetadata(parsed);
                    if (found) {
                        usage = found;
                    }
                } catch (_ignored) {}
            }
            continue;
        }
        const jsonText = trimmed.slice(5).trim();
        if (!jsonText || jsonText === '[DONE]') {
            continue;
        }
        try {
            const parsed = JSON.parse(jsonText);
            const found = extractUsageMetadata(parsed);
            if (found) {
                usage = found;
            }
        } catch (_e) {
            // 途中チャンクは不完全なことがあるので無視
        }
    }
    return usage;
}

function geminiUrl(model, method) {
    const base = process.env.GEMINI_API_BASE || 'https://generativelanguage.googleapis.com';
    const sse = method === 'streamGenerateContent' ? 'alt=sse&' : '';
    return `${base}/v1beta/models/${model}:${method}?${sse}key=${process.env.GEMINI_API_KEY}`;
}

const geminiChain = [authMiddleware, geminiLimiter, guardGemini, deviceGate, budgetGate];

// ========================================
// エンドポイント
// ========================================
app.post('/gemini', ...geminiChain, async (req, res) => {
    try {
        const model = req.geminiModel;
        const response = await fetch(geminiUrl(model, 'generateContent'), {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: req.geminiBody
        });
        const data = await response.text();
        try {
            const parsed = JSON.parse(data);
            logGeminiUsage('generate', model, extractUsageMetadata(parsed), {
                status: response.status
            }, req.device);
        } catch (_e) {
            // 非JSONエラー応答は計測対象外
        }
        res.status(response.status).send(data);
    } catch (err) {
        res.status(500).send("Proxy Error: " + err.message);
    }
});

// ========================================
// SSE ストリーミング（Gemini streamGenerateContent パススルー）
// ========================================
app.post('/gemini-stream', ...geminiChain, async (req, res) => {
    try {
        const model = req.geminiModel;
        const response = await fetch(geminiUrl(model, 'streamGenerateContent'), {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: req.geminiBody
        });

        if (!response.ok) {
            const errText = await response.text();
            return res.status(response.status).send(errText);
        }

        // SSEヘッダーを設定してストリームをパイプする
        res.setHeader('Content-Type', 'text/event-stream');
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');
        res.setHeader('X-Accel-Buffering', 'no'); // nginx/Cloud Run バッファリング無効化

        // レスポンスボディをそのまま転送
        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        let lastUsage = null;
        try {
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                const chunk = decoder.decode(value, { stream: true });
                lastUsage = extractUsageFromSseChunk(chunk, lastUsage);
                res.write(chunk);
            }
        } catch (streamErr) {
            console.error('Stream pipe error:', streamErr.message);
        } finally {
            logGeminiUsage('stream', model, lastUsage, { status: response.status }, req.device);
            res.end();
        }
    } catch (err) {
        res.status(500).send("Proxy Stream Error: " + err.message);
    }
});

// ========================================
// Firebase shared quiz bank
// ========================================
// Reads and writes stay behind the existing proxy authentication. The game never
// receives Firebase Admin credentials and can keep using its last local snapshot
// when this service is unreachable.
app.use('/quiz-bank', authMiddleware, bankLimiter, createQuizBankRouter());

// ========================================
// 端末の許可証（device-auth.js）
// ========================================
function parseJsonBody(req) {
    try {
        return JSON.parse(req.body || '{}');
    } catch (_e) {
        return null;
    }
}

app.get('/session/challenge', authMiddleware, sessionLimiter, (req, res) => {
    if (!deviceAuth) return res.status(503).json({ error: 'device_tokens_disabled' });
    res.json(deviceAuth.issueChallenge());
});

app.post('/session', authMiddleware, sessionLimiter, (req, res) => {
    if (!deviceAuth) return res.status(503).json({ error: 'device_tokens_disabled' });
    const body = parseJsonBody(req);
    if (!body) return res.status(400).json({ error: 'invalid_json' });
    try {
        const issued = deviceAuth.redeem(body.iid, body.challenge, body.counter);
        console.log(JSON.stringify({ type: 'device_session', iid: body.iid }));
        res.json(issued);
    } catch (error) {
        res.status(400).json({ error: error.message });
    }
});

// ========================================
// ラウンドの作り方（round-plan.js）
// ========================================
// ゲームはラウンド開始時に呼び、10 問のうち何問を Gemini で新しく作るかを受け取る。
// 残りは共有バンクなどで埋める。Gemini は呼ばない。
app.post('/round-plan', authMiddleware, bankLimiter, async (req, res) => {
    let device = null;
    if (deviceAuth) {
        device = deviceAuth.verify(req.headers['x-device-token']);
        if (!device && deviceRequired) return res.status(401).json({ error: 'device_token' });
    }
    const body = parseJsonBody(req) || {};
    const mode = ['ten', 'endless', 'sudden_death'].includes(body.mode) ? body.mode : 'ten';
    try {
        let level = 'stop';
        if ((await budget.check()).ok) {
            level = (await budget.paceLevel()).level;
            // 運用のスイッチ: 予算が残っていても全員を指定の段階にする（例: stop で全員バンクだけ）
            const forced = process.env.ROUND_PLAN_FORCE_LEVEL;
            if (['green', 'yellow', 'orange', 'red', 'stop'].includes(forced)) level = forced;
        }
        let roundIndex = 1;
        if (device) {
            const ipKey = deviceAuth.ipKey(req.ip);
            if (!(await deviceLimits.check({ ...device, ipKey })).ok) level = 'stop';
            roundIndex = await deviceLimits.nextRoundIndex(device.iid);
        }
        const newCount = newCountFor(level, roundIndex);
        // 新作 0 問の試合（予算・端末の上限・ブロック）を数える
        if (newCount === 0) deviceLimits.recordDenial('round_no_new');
        console.log(JSON.stringify({ type: 'round_plan', mode, level, round_index: roundIndex, new_count: newCount }));
        res.json({ level, round_index: roundIndex, new_count: newCount, endless_new_ratio: newCount / 10 });
    } catch (error) {
        res.status(500).json({ error: `Round plan failed: ${error.message}` });
    }
});

// 接続確認。Gemini は呼ばない。APP_SECRET が正しいかもここで分かる。
app.get('/health', authMiddleware, bankLimiter, async (req, res) => {
    // 起動直後のインスタンスでも DB の合計を見せる（30 秒ごとの読み直しと同じ間隔で）
    await budget.refresh();
    res.json({ ok: true, budget: budget.status() });
});

app.get('/', (req, res) => {
    res.send('AIQUIZ Proxy Server is running! (Secured v5 + Quiz Bank)');
});

const PORT = process.env.PORT || 8080;
if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`Proxy listening on port ${PORT} (secured)`);
    });
}

module.exports = { app, authMiddleware, budget, deviceAuth, deviceLimits };
