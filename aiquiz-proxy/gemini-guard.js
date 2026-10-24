// Gemini リクエストの関所。プロキシはゲーム以外からも叩ける前提で、
// クライアントが送ったモデル名・本文をそのまま Gemini へ流さない。
//   - モデルは許可リストのものだけ
//   - 本文は systemInstruction / contents / generationConfig のテキストだけ
//     （tools・画像やファイルの添付・cachedContent などは断る）
//   - 思考は low / minimal だけ、出力トークンはモデルごとの上限に上書き
// 上限値は 2026-09〜10 の実測（出力＋思考の最大）の 1.5〜2 倍。

const MODEL_LIMITS = {
    // 10問モード・サドンデスの生成、正解チェック
    'gemini-3.6-flash': { maxOutputTokens: 4096 },
    // エンドレスの生成（思考が多めに出る）
    'gemini-3.1-flash-lite': { maxOutputTokens: 6144 },
    // 解説・評価
    'gemini-3.5-flash-lite': { maxOutputTokens: 2048 },
};

const TOP_LEVEL_KEYS = new Set(['systemInstruction', 'contents', 'generationConfig']);
const GENERATION_KEYS = new Set([
    'temperature', 'responseMimeType', 'responseSchema', 'thinkingConfig', 'maxOutputTokens',
]);
const THINKING_LEVELS = new Set(['low', 'minimal']);
const MAX_CONTENTS = 4;
const MAX_PARTS = 4;

class GuardError extends Error {}

function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function checkTextParts(parts, where) {
    if (!Array.isArray(parts) || parts.length < 1 || parts.length > MAX_PARTS) {
        throw new GuardError(`${where}.parts must contain 1-${MAX_PARTS} items`);
    }
    for (const part of parts) {
        if (!isPlainObject(part) || Object.keys(part).length !== 1 || typeof part.text !== 'string') {
            throw new GuardError(`${where}.parts accepts text only`);
        }
    }
}

// 許可した形だけを通し、Gemini へ送る本文（文字列）を返す。問題があれば GuardError。
function sanitizeGeminiRequest(model, rawBody) {
    const limits = MODEL_LIMITS[model];
    if (!limits) throw new GuardError('Model not allowed');

    let body;
    try {
        body = JSON.parse(rawBody);
    } catch (_e) {
        throw new GuardError('Invalid JSON');
    }
    if (!isPlainObject(body)) throw new GuardError('Body must be an object');
    for (const key of Object.keys(body)) {
        if (!TOP_LEVEL_KEYS.has(key)) throw new GuardError(`Field not allowed: ${key}`);
    }

    if (!Array.isArray(body.contents) || body.contents.length < 1 || body.contents.length > MAX_CONTENTS) {
        throw new GuardError(`contents must contain 1-${MAX_CONTENTS} items`);
    }
    body.contents.forEach((content, i) => {
        if (!isPlainObject(content)) throw new GuardError('contents items must be objects');
        for (const key of Object.keys(content)) {
            if (key !== 'parts' && key !== 'role') throw new GuardError(`Field not allowed: contents.${key}`);
        }
        if (content.role !== undefined && content.role !== 'user') {
            throw new GuardError('contents.role must be user');
        }
        checkTextParts(content.parts, `contents[${i}]`);
    });

    if (body.systemInstruction !== undefined) {
        if (!isPlainObject(body.systemInstruction)
            || Object.keys(body.systemInstruction).some(key => key !== 'parts')) {
            throw new GuardError('systemInstruction accepts parts only');
        }
        checkTextParts(body.systemInstruction.parts, 'systemInstruction');
    }

    const config = body.generationConfig === undefined ? {} : body.generationConfig;
    if (!isPlainObject(config)) throw new GuardError('generationConfig must be an object');
    for (const key of Object.keys(config)) {
        if (!GENERATION_KEYS.has(key)) throw new GuardError(`Field not allowed: generationConfig.${key}`);
    }
    if (config.thinkingConfig !== undefined) {
        const thinking = config.thinkingConfig;
        if (!isPlainObject(thinking) || Object.keys(thinking).some(key => key !== 'thinkingLevel')
            || !THINKING_LEVELS.has(thinking.thinkingLevel)) {
            throw new GuardError('thinkingConfig accepts thinkingLevel low or minimal only');
        }
    }
    const requested = Number(config.maxOutputTokens);
    config.maxOutputTokens = Number.isInteger(requested) && requested > 0
        ? Math.min(requested, limits.maxOutputTokens)
        : limits.maxOutputTokens;
    body.generationConfig = config;
    return JSON.stringify(body);
}

module.exports = { GuardError, MODEL_LIMITS, sanitizeGeminiRequest };
