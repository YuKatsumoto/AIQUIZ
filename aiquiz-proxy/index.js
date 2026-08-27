const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');

const app = express();
app.use(cors());
// すべてのリクエストボディをテキストとして受け取る
app.use(express.text({ type: '*/*' }));

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
// Layer 2: レート制限 (1分あたり30リクエスト/IP)
// ========================================
const apiLimiter = rateLimit({
    windowMs: 60 * 1000, // 1分
    max: 30,             // 最大30リクエスト
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many requests. Please wait a moment.' }
});

// ========================================
// Layer 3: リクエスト形状バリデーション
// ========================================
function validateGeminiBody(req, res, next) {
    try {
        const body = JSON.parse(req.body);
        if (!body.contents || !Array.isArray(body.contents)) {
            return res.status(400).json({ error: 'Bad Request: Missing contents array' });
        }
    } catch (e) {
        return res.status(400).json({ error: 'Bad Request: Invalid JSON' });
    }
    next();
}

function validateOpenAIBody(req, res, next) {
    try {
        const body = JSON.parse(req.body);
        if (!body.messages || !Array.isArray(body.messages)) {
            return res.status(400).json({ error: 'Bad Request: Missing messages array' });
        }
    } catch (e) {
        return res.status(400).json({ error: 'Bad Request: Invalid JSON' });
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

function logGeminiUsage(kind, model, usage, extra) {
    if (!usage) {
        return;
    }
    console.log(JSON.stringify({
        type: 'gemini_usage',
        kind: kind,
        model: model,
        promptTokenCount: usage.promptTokenCount,
        candidatesTokenCount: usage.candidatesTokenCount,
        thoughtsTokenCount: usage.thoughtsTokenCount,
        totalTokenCount: usage.totalTokenCount,
        cachedContentTokenCount: usage.cachedContentTokenCount,
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

// ========================================
// エンドポイント
// ========================================
app.post('/openai', authMiddleware, apiLimiter, validateOpenAIBody, async (req, res) => {
    try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
            },
            body: req.body
        });
        const data = await response.text();
        res.status(response.status).send(data);
    } catch (err) {
        res.status(500).send("Proxy Error: " + err.message);
    }
});

app.post('/gemini', authMiddleware, apiLimiter, validateGeminiBody, async (req, res) => {
    try {
        const model = req.query.model || 'gemini-2.5-flash';
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${process.env.GEMINI_API_KEY}`;
        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: req.body
        });
        const data = await response.text();
        try {
            const parsed = JSON.parse(data);
            logGeminiUsage('generate', model, extractUsageMetadata(parsed), {
                status: response.status
            });
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
app.post('/gemini-stream', authMiddleware, apiLimiter, validateGeminiBody, async (req, res) => {
    try {
        const model = req.query.model || 'gemini-2.5-flash';
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse&key=${process.env.GEMINI_API_KEY}`;
        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: req.body
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
            logGeminiUsage('stream', model, lastUsage, { status: response.status });
            res.end();
        }
    } catch (err) {
        res.status(500).send("Proxy Stream Error: " + err.message);
    }
});

app.get('/', (req, res) => {
    res.send('AIQUIZ Proxy Server is running! (Secured v3)');
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
    console.log(`Proxy listening on port ${PORT} (secured)`);
});
