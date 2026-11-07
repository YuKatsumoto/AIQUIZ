// 品質の比較: 今の並び（old）と新しい並び（new、共通部分を system に入れてキャッシュ）で問題をつくり、採点する。
// プロキシと同じ buildParams（claude-live.js）と、毎週の判定と同じ採点（claude-review.js）を使う。
//
//   node run_ab.js gen      … 15 区分 × 2 並び × 6 本を生成して gen.json に書く（再実行すると済んだ分は飛ばす）
//   node run_ab.js judge    … accepted.json（Godot でゲームの採用判定をした結果）を Batch API で採点に出す
//   node run_ab.js collect  … Batch の結果を回収して judged.json に書く
//
// ANTHROPIC_API_KEY が要る。費用の上限は MAX_USD（超えそうなら止める）。
const fs = require('fs');
const path = require('path');
const PROXY = 'G:/AIQUIZ-Main/aiquiz-proxy/';
const Anthropic = require(PROXY + 'node_modules/@anthropic-ai/sdk');
const live = require(PROXY + 'claude-live.js');
const review = require(PROXY + 'claude-review.js');

const DIR = __dirname;
const MAX_USD = Number(process.env.AB_MAX_USD || 6);
const STAGGER_MS = 350;           // 今のゲーム（TEN_BATCH_STAGGER_SEC）
const FANOUT_WAIT_MS = 2000;      // 新しいゲーム（FANOUT_WAIT_MAX_SEC）
const JUDGE = { model: 'claude-opus-5-5', effort: 'medium' };

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY, maxRetries: 3 });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const readJson = (f, d) => (fs.existsSync(path.join(DIR, f)) ? JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8')) : d);
const writeJson = (f, v) => fs.writeFileSync(path.join(DIR, f), JSON.stringify(v, null, 1));

const TASKS = {
    old: live.tasksFromEnv({ CLAUDE_TASK_MODELS_JSON: '{"generate":{"cacheSystem":false}}' }), // 今の本番
    new: live.tasksFromEnv({}),                                                               // cacheSystem: true
};

function spent(gen) {
    return gen.reduce((s, r) => s + (r.usd || 0), 0);
}

// 1 本をストリーミングで呼ぶ（プロキシの /claude-stream と同じ）。t0 からの時刻を記録する。
async function callOne(body, arm, t0, onStarted) {
    const params = live.buildParams({ task: 'generate', prompt: body.prompt, system: body.system }, TASKS[arm]);
    const rec = { sent_ms: Date.now() - t0 };
    for (let attempt = 0; attempt < 3; attempt++) {
        try {
            const stream = client.beta.messages.stream(params);
            let text = '';
            for await (const event of stream) {
                if (rec.started_ms === undefined) {
                    rec.started_ms = Date.now() - t0;
                    if (onStarted) onStarted();
                }
                if (event.type === 'content_block_delta' && event.delta && event.delta.type === 'text_delta') {
                    text += event.delta.text;
                    if (rec.first_obj_ms === undefined && /\{[^{}]*"q"[^{}]*\}/.test(text)) rec.first_obj_ms = Date.now() - t0;
                }
            }
            const message = await stream.finalMessage();
            rec.done_ms = Date.now() - t0;
            rec.text = text;
            rec.model = message.model;
            rec.stop_reason = message.stop_reason;
            rec.usage = message.usage;
            rec.usd = live.costUsd(message.model, message.usage);
            return rec;
        } catch (error) {
            rec.error = `${error.status || ''} ${error.message}`.slice(0, 200);
            if (onStarted) onStarted();
            await sleep(3000 * (attempt + 1));
        }
    }
    rec.usd = 0;
    return rec;
}

async function runRound(bodies, arm) {
    const t0 = Date.now();
    if (arm === 'old') {
        // 今のゲーム: 0.35 秒ずつずらして 6 本
        return Promise.all(bodies.map((b, i) => sleep(i * STAGGER_MS).then(() => callOne(b, arm, t0))));
    }
    // 新しいゲーム: 1 本目の返事が流れ始めたら（最長 2 秒）残りを送る
    let release;
    const started = new Promise(r => { release = r; });
    const first = callOne(bodies[0], arm, t0, () => release());
    await Promise.race([started, sleep(FANOUT_WAIT_MS)]);
    const rest = bodies.slice(1).map(b => callOne(b, arm, t0));
    return Promise.all([first, ...rest]);
}

async function gen() {
    const prompts = readJson('prompts.json');
    const out = readJson('gen.json', []);
    const done = new Set(out.map(r => `${r.bucket}:${r.arm}`));
    for (let bi = 0; bi < prompts.buckets.length; bi++) {
        const b = prompts.buckets[bi];
        // 並びの順番の影響を消すため、区分ごとに old/new の順を入れ替える
        const arms = bi % 2 === 0 ? ['old', 'new'] : ['new', 'old'];
        for (const arm of arms) {
            if (done.has(`${bi}:${arm}`)) continue;
            if (spent(out) > MAX_USD * 0.45) throw new Error(`生成の費用が上限に近い: $${spent(out).toFixed(3)}`);
            const recs = await runRound(b.batches.map(r => r[arm]), arm);
            recs.forEach((rec, i) => out.push({ bucket: bi, arm, batch: i, ...rec }));
            writeJson('gen.json', out);
            const u = recs.map(r => r.usage || {});
            console.log(`${b.subject}${b.grade}${b.difficulty} ${arm}: $${recs.reduce((s, r) => s + r.usd, 0).toFixed(4)}`
                + ` cache_write=${u.map(x => x.cache_creation_input_tokens || 0).join(',')}`
                + ` cache_read=${u.map(x => x.cache_read_input_tokens || 0).join(',')}`
                + ` errors=${recs.filter(r => r.error && !r.text).length}`);
        }
    }
    console.log(`生成の合計 $${spent(out).toFixed(3)}`);
}

// ── 採点 ──
const PAIR_SYSTEM = `あなたは日本の小学校の教員です。同じ条件（教科・学年・難易度・担当単元）で AI が作った 2 組のクイズ（4択、各組4問程度）を比べ、
小学生向けの3Dランナーゲームで出す問題として、どちらの組が良いかを判断してください。

見ること（大事な順）:
1. 正しさ: 正解が1つに決まり、事実の誤りやあいまいさがない
2. 学年と難易度に合っている: その学年で習う内容で、指定の難易度（簡単・普通・難しい）に合う
3. 担当単元に沿っている
4. 誤答の選択肢がもっともらしく、問題どうしが重ならず変化がある
5. 問題文が短く読みやすい

問題の数の違いは評価しない（1問あたりの質で比べる）。はっきりした差がなければ tie にする。
reason は日本語80文字以内。`;

const PAIR_SCHEMA = {
    type: 'object',
    properties: { winner: { type: 'string', enum: ['A', 'B', 'tie'] }, reason: { type: 'string' } },
    required: ['winner', 'reason'],
    additionalProperties: false,
};

function pairRequest(id, meta, setA, setB) {
    const show = set => set.map(it => ({ question: it.q, choices: it.c, answer_index: it.a }));
    const payload = {
        subject: meta.subject, grade: `小学${meta.grade}年生`, difficulty: meta.difficulty,
        units: meta.units, A: show(setA), B: show(setB),
    };
    return {
        custom_id: id,
        params: {
            model: JUDGE.model,
            max_tokens: 4096,
            system: [{ type: 'text', text: PAIR_SYSTEM, cache_control: { type: 'ephemeral' } }],
            messages: [{ role: 'user', content: JSON.stringify(payload, null, 2) }],
            output_config: { effort: JUDGE.effort, format: { type: 'json_schema', schema: PAIR_SCHEMA } },
        },
    };
}

async function judge() {
    const prompts = readJson('prompts.json');
    const acc = readJson('accepted.json');
    const requests = [];
    const index = {};
    // 正解を伏せた解き直し（毎週の判定と同じ）: ゲームが採用した問題だけ
    for (const row of acc.rows) {
        const b = prompts.buckets[row.bucket];
        row.accepted.forEach((it, k) => {
            const id = `s-${row.arm}-${row.bucket}-${row.batch}-${k}`;
            const item = { subject: b.subject, grade: b.grade, difficulty: b.difficulty, genre: it.g, q: it.q, c: it.c, a: it.a };
            index[id] = item;
            requests.push(review.buildRequest(id, item, JUDGE));
        });
    }
    // 一対比較: 同じ区分・同じ単元の old と new（正規化までした問題。A/B の位置は交互）
    const byKey = {};
    for (const row of acc.rows) byKey[`${row.arm}-${row.bucket}-${row.batch}`] = row;
    for (let bi = 0; bi < prompts.buckets.length; bi++) {
        for (let i = 0; i < 6; i++) {
            const o = byKey[`old-${bi}-${i}`];
            const n = byKey[`new-${bi}-${i}`];
            if (!o || !n || !o.normalized.length || !n.normalized.length) continue;
            const b = prompts.buckets[bi];
            const flip = (bi + i) % 2 === 1;
            const meta = { subject: b.subject, grade: b.grade, difficulty: b.difficulty, units: b.batches[i].units };
            const id = `p-${bi}-${i}-${flip ? 'NO' : 'ON'}`;  // ON: A=old, NO: A=new
            requests.push(pairRequest(id, meta, flip ? n.normalized : o.normalized, flip ? o.normalized : n.normalized));
        }
    }
    writeJson('judge_index.json', index);
    console.log(`採点の依頼: ${requests.length} 件（解き直し ${Object.keys(index).length}、一対比較 ${requests.length - Object.keys(index).length}）`);
    const batch = await client.messages.batches.create({ requests });
    writeJson('judge_batch.json', { id: batch.id, count: requests.length });
    console.log(`batch ${batch.id} ${batch.processing_status}`);
}

async function collect() {
    const { id } = readJson('judge_batch.json');
    const batch = await client.messages.batches.retrieve(id);
    console.log(`batch ${id} ${batch.processing_status} ${JSON.stringify(batch.request_counts)}`);
    if (batch.processing_status !== 'ended') return;
    const index = readJson('judge_index.json');
    const out = { solve: {}, pair: {}, usd: 0, errors: 0 };
    for await (const result of await client.messages.batches.results(id)) {
        if (result.result.type !== 'succeeded') { out.errors++; continue; }
        const message = result.result.message;
        out.usd += review.costUsd(message.model, message.usage);
        const cid = result.custom_id;
        if (cid.startsWith('s-')) {
            out.solve[cid] = review.parseVerdict(message, index[cid]);
        } else {
            const block = (message.content || []).find(b => b.type === 'text');
            try { out.pair[cid] = JSON.parse(block.text); } catch (_e) { out.pair[cid] = null; }
        }
    }
    writeJson('judged.json', out);
    console.log(`回収: 解き直し ${Object.keys(out.solve).length}、一対比較 ${Object.keys(out.pair).length}、失敗 ${out.errors}、採点の費用 $${out.usd.toFixed(3)}`);
}

const cmd = process.argv[2];
({ gen, judge, collect })[cmd]().catch(error => { console.error(error); process.exit(1); });
