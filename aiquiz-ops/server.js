// AIQUIZ 運用の管理ソフト。
//   段階1: 見るだけ（お金・共有バンク・プレイヤー）
//   段階2: 操作（端末・回線のブロック、問題を外す・戻す、毎週のジョブを今すぐ実行）と、その記録
//   npm start → http://localhost:3002
// この PC からだけ開けるように 127.0.0.1 で待ち受ける。データは gcloud のログインで読み書きする。
const path = require('path');
const express = require('express');
const { DEFAULT_CONFIG, OpsSources } = require('./lib/sources');
const { OpsActions } = require('./lib/actions');

const HOST = '127.0.0.1';
const PORT = Number(process.env.OPS_PORT || 3002);
const FIREBASE_DB_URL = process.env.FIREBASE_DB_URL
    || 'https://aiquiz-a12f6-default-rtdb.asia-southeast1.firebasedatabase.app';
const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'aiquiz-a12f6';
const LOCAL_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function createApp(sources, actions) {
    const app = express();
    app.disable('x-powered-by');

    // 別のサイトからこの PC の管理ソフトを読ませない（Host を localhost に限る）
    app.use((req, res, next) => {
        const host = String(req.headers.host || '').replace(/:\d+$/, '');
        if (!['localhost', '127.0.0.1'].includes(host)) return res.status(403).send('forbidden');
        next();
    });

    const route = (load) => async (req, res) => {
        try {
            res.set('Cache-Control', 'no-store');
            res.json(await load(req));
        } catch (error) {
            const status = error.status || 500;
            if (status >= 500) console.error(`[ops] ${req.path}: ${error.stack || error.message}`);
            res.status(status).json({ error: error.message });
        }
    };

    // 書き換える操作は、この画面からの JSON だけ受け付ける。
    // 独自ヘッダーが要るので、別のサイトのページからは（CORS の事前確認で）送れない。
    const operation = [
        express.json({ limit: '16kb' }),
        (req, res, next) => {
            const origin = req.headers.origin;
            if (req.headers['x-ops-request'] !== '1' || (origin && !LOCAL_ORIGIN.test(origin))) {
                return res.status(403).json({ error: 'forbidden' });
            }
            next();
        },
    ];

    app.get('/api/overview', route(() => sources.overview()));
    app.get('/api/money', route(() => sources.money()));
    app.get('/api/players', route(() => sources.players()));
    app.get('/api/bank', route(req => sources.bank({ refresh: req.query.refresh === '1' })));
    app.get('/api/jobs', route(() => sources.jobs()));
    app.get('/api/questions', route(req => sources.searchQuestions({
        text: req.query.text, id: req.query.id, subject: req.query.subject, grade: req.query.grade,
        difficulty: req.query.difficulty, removed: req.query.removed === '1', limit: req.query.limit,
    })));
    app.get('/api/log', route(() => actions.recentLog()));

    app.post('/api/actions/block', operation, route(req => actions.block(req.body)));
    app.post('/api/actions/unblock', operation, route(req => actions.unblock(req.body)));
    app.post('/api/actions/remove-question', operation, route(req => actions.removeQuestion(req.body)));
    app.post('/api/actions/restore-question', operation, route(req => actions.restoreQuestion(req.body)));
    app.post('/api/actions/run-job', operation, route(req => actions.runJob(req.body)));

    // 画面のファイルを直したら、再読み込みだけで新しいものが出るように毎回確かめさせる
    app.use(express.static(path.join(__dirname, 'public'), { setHeaders: res => res.set('Cache-Control', 'no-cache') }));
    return app;
}

async function createServices() {
    const { applicationDefault, initializeApp } = require('firebase-admin/app');
    const { getDatabase } = require('firebase-admin/database');
    const { GoogleAuth } = require('google-auth-library');
    initializeApp({ credential: applicationDefault(), databaseURL: FIREBASE_DB_URL, projectId: FIREBASE_PROJECT_ID });
    const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
    const client = await auth.getClient();
    const gcpRequest = async (url, { method = 'GET', data } = {}) => (await client.request({ url, method, data })).data;
    const db = getDatabase();
    const sources = new OpsSources({
        db,
        gcpRequest,
        config: {
            gcpProject: process.env.GCP_PROJECT || DEFAULT_CONFIG.gcpProject,
            claudeSpendCapUsd: Number(process.env.CLAUDE_SPEND_CAP_USD || DEFAULT_CONFIG.claudeSpendCapUsd),
            jpyPerUsd: Number(process.env.JPY_PER_USD || DEFAULT_CONFIG.jpyPerUsd),
        },
    });
    const actions = new OpsActions({
        db,
        gcpRequest,
        jobs: sources.config.jobs,
        runUrl: p => sources.runUrl(p),
        onBankChange: change => sources.applyBankChange(change),
    });
    return { sources, actions };
}

if (require.main === module) {
    createServices()
        .then(({ sources, actions }) => {
            createApp(sources, actions).listen(PORT, HOST, () => {
                console.log(`AIQUIZ 運用: http://localhost:${PORT}`);
            });
        })
        .catch(error => {
            console.error(`起動できません: ${error.message}`);
            console.error('gcloud auth application-default login でログインしてから、もう一度起動してください。');
            process.exit(1);
        });
}

module.exports = { createApp };
