const test = require('node:test');
const assert = require('node:assert/strict');
const {
    CHILD_SAFETY, ClaudeGuardError, buildParams, costUsd, gameText, sanitizeClaudeRequest, tasksFromEnv,
} = require('../claude-live');

const tasks = tasksFromEnv({});

test('only {task, prompt, system} with a known task and bounded lengths is accepted', () => {
    const ok = sanitizeClaudeRequest(JSON.stringify({ task: 'generate', prompt: 'p', system: 's' }), tasks);
    assert.deepEqual(ok, { task: 'generate', prompt: 'p', system: 's' });
    const bad = [
        'not json',
        JSON.stringify([]),
        JSON.stringify({ task: 'chat', prompt: 'p' }),
        JSON.stringify({ task: 'generate', prompt: '' }),
        JSON.stringify({ task: 'generate', prompt: 'p', model: 'claude-opus-5-5' }),
        JSON.stringify({ task: 'generate', prompt: 'p', system: 1 }),
        JSON.stringify({ task: 'generate', prompt: 'x'.repeat(24001) }),
        JSON.stringify({ task: 'generate', prompt: 'p', system: 'x'.repeat(8001) }),
    ];
    for (const body of bad) {
        assert.throws(() => sanitizeClaudeRequest(body, tasks), ClaudeGuardError, body.slice(0, 40));
    }
});

// system は文字列か、text ブロックの配列（キャッシュの印つき）
function systemText(params) {
    return typeof params.system === 'string' ? params.system : params.system.map(block => block.text).join('');
}

test('every request starts its system prompt with the child-safety instruction', () => {
    for (const task of Object.keys(tasks)) {
        const withSystem = buildParams({ task, prompt: 'p', system: 'ゲームの指示' }, tasks);
        assert.ok(systemText(withSystem).startsWith(CHILD_SAFETY), task);
        assert.ok(systemText(withSystem).endsWith('ゲームの指示'), task);
        assert.equal(systemText(buildParams({ task, prompt: 'p', system: '' }, tasks)), CHILD_SAFETY);
    }
});

test('generate marks the whole system prompt for caching; the one-off tasks do not', () => {
    const params = buildParams({ task: 'generate', prompt: 'このバッチの単元', system: '6本で同じルール' }, tasks);
    assert.deepEqual(params.system, [{
        type: 'text', text: `${CHILD_SAFETY}\n\n6本で同じルール`, cache_control: { type: 'ephemeral' },
    }]);
    assert.deepEqual(params.messages, [{ role: 'user', content: 'このバッチの単元' }]);
    for (const task of ['validate', 'explain', 'evaluate']) {
        assert.equal(typeof buildParams({ task, prompt: 'p', system: 's' }, tasks).system, 'string', task);
    }
    // 運用のスイッチ: CLAUDE_TASK_MODELS_JSON で外せる
    const off = tasksFromEnv({ CLAUDE_TASK_MODELS_JSON: '{"generate":{"cacheSystem":false}}' });
    assert.equal(typeof buildParams({ task: 'generate', prompt: 'p', system: 's' }, off).system, 'string');
});

test('the server picks the model; Sonnet 5.5 at effort low, with the default fallback and no sampling knobs', () => {
    const params = buildParams({ task: 'generate', prompt: 'p', system: '' }, tasks);
    assert.equal(params.model, 'claude-sonnet-5-5');
    assert.equal(params.output_config.effort, 'low');
    assert.equal(params.output_config.format, undefined);
    assert.deepEqual(params.betas, ['server-side-fallback-2026-07-01']);
    assert.equal(params.fallbacks, 'default');
    assert.equal(params.temperature, undefined);
    assert.equal(params.thinking, undefined);
    assert.deepEqual(params.messages, [{ role: 'user', content: 'p' }]);
});

test('validate, explain and evaluate use a JSON schema whose items the game reads as a plain array', () => {
    for (const task of ['validate', 'explain', 'evaluate']) {
        const format = buildParams({ task, prompt: 'p', system: '' }, tasks).output_config.format;
        assert.equal(format.type, 'json_schema', task);
        assert.equal(format.schema.properties.items.type, 'array', task);
    }
    assert.equal(gameText('validate', '{"items":[{"id":0}]}'), '[{"id":0}]');
    assert.equal(gameText('validate', 'broken'), 'broken');
    assert.equal(gameText('generate', '[{"q":"x"}]'), '[{"q":"x"}]');
});

test('CLAUDE_TASK_MODELS_JSON changes one task without touching the others', () => {
    const custom = tasksFromEnv({ CLAUDE_TASK_MODELS_JSON: '{"explain":{"model":"claude-haiku-5-5"}}' });
    assert.equal(custom.explain.model, 'claude-haiku-5-5');
    assert.equal(custom.explain.effort, 'low');
    assert.equal(custom.generate.model, 'claude-sonnet-5-5');
    // Haiku 5.5 にはサーバー側のフォールバックが無いので付けない
    const params = buildParams({ task: 'explain', prompt: 'p', system: '' }, custom);
    assert.equal(params.fallbacks, undefined);
    assert.equal(params.betas, undefined);
});

test('cost counts cache writes at 1.25x and reads at the cache rate', () => {
    const usd = costUsd('claude-sonnet-5-5', {
        input_tokens: 1000, output_tokens: 500, cache_creation_input_tokens: 1000, cache_read_input_tokens: 1000,
    });
    assert.ok(Math.abs(usd - (1000 * 2 + 1000 * 2.5 + 1000 * 0.2 + 500 * 10) / 1e6) < 1e-12);
    assert.equal(costUsd('unknown-model', { input_tokens: 10 }), 0);
});
