const test = require('node:test');
const assert = require('node:assert/strict');
const { GuardError, MODEL_LIMITS, sanitizeGeminiRequest } = require('../gemini-guard');

// ゲームの生成リクエストと同じ形（online_fetch.gd _fetch_gemini_streaming）
function gameBody(overrides = {}) {
    return {
        systemInstruction: { parts: [{ text: 'あなたは小学校の教員です。' }] },
        contents: [{ parts: [{ text: '問題を4問作ってください。' }] }],
        generationConfig: {
            temperature: 0.8,
            responseMimeType: 'application/json',
            thinkingConfig: { thinkingLevel: 'low' },
        },
        ...overrides,
    };
}

function sanitize(model, body) {
    return JSON.parse(sanitizeGeminiRequest(model, JSON.stringify(body)));
}

test('the game request shapes pass and get the model output cap', () => {
    const out = sanitize('gemini-3.6-flash', gameBody());
    assert.equal(out.generationConfig.maxOutputTokens, MODEL_LIMITS['gemini-3.6-flash'].maxOutputTokens);
    assert.equal(out.generationConfig.thinkingConfig.thinkingLevel, 'low');
    assert.equal(out.contents[0].parts[0].text, '問題を4問作ってください。');
    // validator / explanation style: no systemInstruction, responseSchema, minimal thinking
    const explain = sanitize('gemini-3.5-flash-lite', {
        contents: [{ parts: [{ text: 'x' }] }],
        generationConfig: { temperature: 0.1, responseMimeType: 'application/json',
            responseSchema: { type: 'ARRAY' }, thinkingConfig: { thinkingLevel: 'minimal' } },
    });
    assert.equal(explain.generationConfig.maxOutputTokens, 2048);
});

test('a smaller client maxOutputTokens is kept, a larger one is capped', () => {
    const small = sanitize('gemini-3.1-flash-lite', gameBody({
        generationConfig: { maxOutputTokens: 5 } }));
    assert.equal(small.generationConfig.maxOutputTokens, 5);
    const big = sanitize('gemini-3.1-flash-lite', gameBody({
        generationConfig: { maxOutputTokens: 65536 } }));
    assert.equal(big.generationConfig.maxOutputTokens, 6144);
});

test('models outside the allowlist are refused', () => {
    for (const model of ['gemini-4-argon', 'gemini-3.1-pro-preview', 'gemini-3-flash-preview', '', '../x']) {
        assert.throws(() => sanitize(model, gameBody()), GuardError, model);
    }
});

test('tools, attachments, caching and other extras are refused', () => {
    const cases = [
        gameBody({ tools: [{ googleSearch: {} }] }),
        gameBody({ cachedContent: 'cachedContents/abc' }),
        gameBody({ safetySettings: [] }),
        gameBody({ contents: [{ parts: [{ inlineData: { mimeType: 'image/png', data: 'AAAA' } }] }] }),
        gameBody({ contents: [{ parts: [{ fileData: { fileUri: 'gs://x' } }] }] }),
        gameBody({ contents: [{ role: 'model', parts: [{ text: 'prefill' }] }] }),
        gameBody({ contents: [] }),
        gameBody({ contents: Array.from({ length: 5 }, () => ({ parts: [{ text: 'x' }] })) }),
        gameBody({ systemInstruction: { parts: [{ text: 'x' }], role: 'system' } }),
        gameBody({ generationConfig: { candidateCount: 8 } }),
        gameBody({ generationConfig: { thinkingConfig: { thinkingLevel: 'high' } } }),
        gameBody({ generationConfig: { thinkingConfig: { thinkingBudget: 24576 } } }),
    ];
    for (const body of cases) {
        assert.throws(() => sanitize('gemini-3.6-flash', body), GuardError, JSON.stringify(body).slice(0, 80));
    }
    assert.throws(() => sanitizeGeminiRequest('gemini-3.6-flash', 'not json'), GuardError);
});
