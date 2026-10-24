// 画面に出す集計。DB や Cloud Run から読んだそのままのデータを受け取り、表示用の形にして返す。
// ここでは何も読み書きしない（テストで本番に触れずに確かめられるように）。
const { PRIORITY_ROUNDS, jstKeys, newCountFor } = require('./proxy-shared');

const DAY_MS = 24 * 3600 * 1000;
const DIFFICULTIES = ['簡単', '普通', '難しい'];

function num(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
}

function round(value, digits = 4) {
    return Number(num(value).toFixed(digits));
}

// DB のキーでは「.」が使えないので、プロキシはモデル名の「.」を「_」にして記録している
function modelName(key) {
    return String(key).replace(/_/g, '.');
}

// 今日を最後とする count 日分の日付（日本時間）
function lastDays(now, count) {
    const days = [];
    for (let i = count - 1; i >= 0; i--) days.push(jstKeys(new Date(now.getTime() - i * DAY_MS)).day);
    return days;
}

function monthProgress(now) {
    const jst = new Date(now.getTime() + 9 * 3600 * 1000);
    const daysInMonth = new Date(Date.UTC(jst.getUTCFullYear(), jst.getUTCMonth() + 1, 0)).getUTCDate();
    const secondsToday = jst.getUTCHours() * 3600 + jst.getUTCMinutes() * 60 + jst.getUTCSeconds();
    const elapsedDays = jst.getUTCDate() - 1 + secondsToday / 86400;
    return { daysInMonth, elapsedDays, frac: elapsedDays / daysInMonth };
}

function addModels(target, models) {
    for (const [key, value] of Object.entries(models || {})) {
        const name = modelName(key);
        const entry = target[name] || { model: name, usd: 0, requests: 0 };
        entry.usd += num(value && value.usd);
        entry.requests += num(value && value.requests);
        target[name] = entry;
    }
}

function sortedModels(byName) {
    return Object.values(byName)
        .map(m => ({ ...m, usd: round(m.usd) }))
        .sort((a, b) => b.usd - a.usd);
}

// 回収前の Batch の費用見込み。夜のジョブが予算の残りを計算するのと同じ考え方。
function inflight(batches, perItemUsd) {
    let count = 0;
    let n = 0;
    for (const record of Object.values(batches || {})) {
        if (record && record.state === 'submitted') {
            n += 1;
            count += num(record.count);
        }
    }
    return { batches: n, items: count, estUsd: round(count * perItemUsd) };
}

function claudeSummary({ month, builderSpend, builderBatches, builderConfig, reviewSpend, reviewBatches, reviewConfig }) {
    const part = (spend, batches, budgetUsd, perItemUsd, model) => {
        const s = (spend || {})[month] || {};
        return {
            model,
            usd: round(s.usd),
            requests: num(s.requests),
            budgetUsd,
            inflight: inflight(batches, perItemUsd),
        };
    };
    const builder = part(builderSpend, builderBatches, builderConfig.monthlyBudgetUsd,
        builderConfig.estimatedUsdPerCall, builderConfig.model);
    const review = part(reviewSpend, reviewBatches, reviewConfig.monthlyBudgetUsd,
        reviewConfig.estimatedUsdPerItem, reviewConfig.model);
    return {
        builder,
        review,
        totalUsd: round(builder.usd + review.usd),
        totalBudgetUsd: round(builder.budgetUsd + review.budgetUsd),
    };
}

// お金: Gemini（プロキシの記録）と Claude（夜のジョブの記録）
function moneySummary({ now, budgets, level, pace, forcedLevel = null, stopReason = null, daily = {}, monthly = {}, claude,
    jpyPerUsd = 150 }) {
    const { day, month } = jstKeys(now);
    const today = daily[day] || {};
    const thisMonth = monthly[month] || {};
    const monthUsd = num(thisMonth.usd);
    const progress = monthProgress(now);
    // 月の初日はまだ見込みを出さない（数時間分から1か月を伸ばすと大きくぶれる）
    const projectedUsd = progress.elapsedDays >= 1 ? round(monthUsd / progress.frac, 2) : null;

    const todayModels = {};
    addModels(todayModels, today.models);
    const monthModels = {};
    for (const [d, entry] of Object.entries(daily)) {
        if (d.startsWith(month)) addModels(monthModels, entry && entry.models);
    }

    const history = lastDays(now, 30).map(d => {
        const entry = daily[d] || {};
        const models = {};
        addModels(models, entry.models);
        return {
            day: d,
            usd: round(entry.usd),
            requests: num(entry.requests),
            models: Object.fromEntries(Object.values(models).map(m => [m.model, round(m.usd)])),
        };
    });

    return {
        day,
        month,
        jpyPerUsd,
        gemini: {
            level,
            forcedLevel,
            stopReason,
            timeFrac: round(pace.timeFrac, 3),
            newCount: {
                first: newCountFor(level, 1),
                later: newCountFor(level, PRIORITY_ROUNDS + 1),
                priorityRounds: PRIORITY_ROUNDS,
            },
            today: {
                usd: round(today.usd),
                requests: num(today.requests),
                budgetUsd: budgets.dailyUsd,
                targetUsd: round(pace.targetUsd),
            },
            month: {
                usd: round(monthUsd),
                requests: num(thisMonth.requests),
                budgetUsd: budgets.monthlyUsd,
                projectedUsd,
                daysInMonth: progress.daysInMonth,
                elapsedDays: round(progress.elapsedDays, 2),
            },
            modelsToday: sortedModels(todayModels),
            modelsMonth: sortedModels(monthModels),
            history,
        },
        claude,
    };
}

// プレイヤー: 端末・回線ごとの今日の使用額と試合数
function playersSummary({ now, devices = {}, ips = {}, rounds = {}, roundsHistory = {}, blocked = {}, denials = {},
    caps, geminiTodayUsd = 0, top = 15 }) {
    const ids = new Set([...Object.keys(devices), ...Object.keys(rounds)]);
    let totalRounds = 0;
    for (const value of Object.values(rounds)) totalRounds += num(value && value.rounds);

    const deviceRows = [...ids].map(id => {
        const spend = devices[id] || {};
        const usd = num(spend.usd);
        return {
            id,
            usd: round(usd),
            requests: num(spend.requests),
            rounds: num((rounds[id] || {}).rounds),
            capPct: caps.deviceUsd > 0 ? round(usd / caps.deviceUsd, 3) : null,
            blocked: Boolean(blocked[id]),
        };
    }).sort((a, b) => b.usd - a.usd || b.rounds - a.rounds);

    const ipRows = Object.entries(ips).map(([id, value]) => {
        const usd = num(value && value.usd);
        return {
            id,
            usd: round(usd),
            requests: num(value && value.requests),
            capPct: caps.ipUsd > 0 ? round(usd / caps.ipUsd, 3) : null,
            blocked: Boolean(blocked[id]),
        };
    }).sort((a, b) => b.usd - a.usd);

    const history = lastDays(now, 14).map(d => {
        const byDevice = roundsHistory[d] || {};
        let n = 0;
        for (const value of Object.values(byDevice)) n += num(value && value.rounds);
        return { day: d, rounds: n, devices: Object.keys(byDevice).length };
    });

    return {
        day: jstKeys(now).day,
        caps,
        today: {
            rounds: totalRounds,
            devices: ids.size,
            generatingDevices: deviceRows.filter(d => d.usd > 0).length,
            ips: ipRows.length,
            usdPerRound: totalRounds > 0 ? round(geminiTodayUsd / totalRounds) : null,
            nearCapDevices: deviceRows.filter(d => d.capPct !== null && d.capPct >= 0.8).length,
            atCapDevices: deviceRows.filter(d => d.capPct !== null && d.capPct >= 1).length,
            blockedCount: Object.values(blocked).filter(Boolean).length,
        },
        // 止めた回数（理由ごと・今日）。プロキシが proxy_usage/v1/denials に数えている
        denials: Object.entries(denials)
            .map(([reason, value]) => ({ reason, count: num(value && value.count) }))
            .filter(d => d.count > 0)
            .sort((a, b) => b.count - a.count),
        blockedList: Object.entries(blocked)
            .filter(([, value]) => value)
            .map(([key, value]) => {
                const entry = value && typeof value === 'object' ? value : {};
                return {
                    key,
                    kind: entry.kind || (/^[0-9a-f]{32}$/.test(key) ? 'device' : 'ip'),
                    reason: entry.reason || '',
                    at: num(entry.at) || null,
                    by: entry.by || '',
                };
            })
            .sort((a, b) => (b.at || 0) - (a.at || 0)),
        topDevices: deviceRows.slice(0, top),
        topIps: ipRows.slice(0, top),
        history,
    };
}

function bucketKey(subject, grade, difficulty) {
    return `${subject}|${grade}|${difficulty}`;
}

function batchRows(batches, extra = () => ({})) {
    return Object.entries(batches || {})
        .filter(([, record]) => record)
        .map(([id, record]) => ({
            id,
            state: record.state || '',
            submittedAt: num(record.submitted_at) || null,
            collectedAt: num(record.collected_at) || null,
            count: num(record.count),
            usd: record.usd === undefined ? null : round(record.usd),
            ...extra(id, record),
        }))
        .sort((a, b) => (b.submittedAt || 0) - (a.submittedAt || 0));
}

// 共有バンク: 区分ごとの在庫、確認待ち、Claude の判定結果、夜のジョブの Batch
function bankSummary({ now, prompts, bank = {}, archive = {}, builderBatches = {}, reviewBatches = {}, target }) {
    const subjects = [];
    const planned = new Set();
    for (const p of prompts.prompts || []) {
        if (!subjects.includes(p.subject)) subjects.push(p.subject);
        planned.add(bucketKey(p.subject, Number(p.grade), p.difficulty));
    }
    const grades = [1, 2, 3, 4, 5, 6];
    const cells = new Map();
    const cellFor = (subject, grade, difficulty) => {
        const key = bucketKey(subject, grade, difficulty);
        if (!cells.has(key)) {
            cells.set(key, { subject, grade, difficulty, bank: 0, pending: 0, planned: planned.has(key) });
        }
        return cells.get(key);
    };
    for (const subject of subjects) {
        for (const grade of grades) {
            for (const difficulty of DIFFICULTIES) cellFor(subject, grade, difficulty);
        }
    }

    const origins = { claude: 0, player: 0, unknown: 0 };
    let bankCount = 0;
    for (const [id, item] of Object.entries(bank)) {
        if (!item || !item.subject) continue;
        bankCount += 1;
        cellFor(item.subject, num(item.grade), item.difficulty).bank += 1;
        const src = (archive[id] || {}).original_src || '';
        if (src === 'CLAUDE_HAIKU') origins.claude += 1;
        else if (src) origins.player += 1;
        else origins.unknown += 1;
    }

    const pending = { waiting: 0, inReview: 0, unsure: 0, errored: 0 };
    const archiveStatus = { good: 0, bad: 0, pending: 0 };
    const verdicts = { pass: 0, fail: 0, unsure: 0 };
    const byBatch = {};
    const weekAgo = Math.floor(now.getTime() / 1000) - 7 * 86400;
    const week = { pass: 0, fail: 0 };
    for (const item of Object.values(archive)) {
        if (!item) continue;
        if (item.status in archiveStatus) archiveStatus[item.status] += 1;
        const review = item.review || null;
        if (review && review.batch_id) {
            const b = byBatch[review.batch_id] || (byBatch[review.batch_id] = { pass: 0, fail: 0, unsure: 0, error: 0 });
            if (review.state === 'done' && review.verdict in b) b[review.verdict] += 1;
            if (review.state === 'error') b.error += 1;
        }
        if (review && review.state === 'done' && review.verdict in verdicts) {
            verdicts[review.verdict] += 1;
            if (num(review.reviewed_at) >= weekAgo && review.verdict in week) week[review.verdict] += 1;
        }
        if (item.status !== 'pending') continue;
        if (!review) pending.waiting += 1;
        else if (review.state === 'submitted') pending.inReview += 1;
        else if (review.state === 'error') pending.errored += 1;
        else if (review.state === 'done' && review.verdict === 'unsure') pending.unsure += 1;
        else pending.waiting += 1;
        // 夜の補充と同じく、確認でつまずいたものは在庫に数えない
        if (!(review && review.state === 'error') && item.subject) {
            cellFor(item.subject, num(item.grade), item.difficulty).pending += 1;
        }
    }

    const cellList = [...cells.values()];
    const plannedCells = cellList.filter(c => c.planned);
    const passRate = (p, f) => (p + f > 0 ? round(p / (p + f), 3) : null);

    return {
        target,
        subjects,
        grades,
        difficulties: DIFFICULTIES,
        cells: cellList,
        totals: {
            bank: bankCount,
            plannedBuckets: plannedCells.length,
            bucketsAtTarget: plannedCells.filter(c => c.bank >= target).length,
            emptyBuckets: plannedCells.filter(c => c.bank === 0).length,
            shortfall: plannedCells.reduce((sum, c) => sum + Math.max(0, target - c.bank), 0),
        },
        origins,
        pending,
        archive: archiveStatus,
        review: {
            ...verdicts,
            passRate: passRate(verdicts.pass, verdicts.fail),
            week: { ...week, passRate: passRate(week.pass, week.fail) },
        },
        lowest: plannedCells
            .slice()
            .sort((a, b) => (a.bank + a.pending) - (b.bank + b.pending) || a.bank - b.bank)
            .slice(0, 10),
        builderBatches: batchRows(builderBatches, (id, record) => ({
            questions: record.questions === undefined ? null : num(record.questions),
        })).slice(0, 10),
        reviewBatches: batchRows(reviewBatches, id => ({
            ...(byBatch[id] || { pass: 0, fail: 0, unsure: 0, error: 0 }),
        })).slice(0, 10),
    };
}

function executionState(execution) {
    if (!execution.completionTime) return 'running';
    if (num(execution.failedCount) > 0 || num(execution.cancelledCount) > 0) return 'failed';
    return num(execution.succeededCount) > 0 ? 'succeeded' : 'failed';
}

// 夜のジョブ: Cloud Run Jobs の実行履歴と Cloud Scheduler の次回予定
function jobsSummary({ jobs, executions = {}, schedulers = [] }) {
    return jobs.map(job => {
        const scheduler = schedulers.find(s => String((s.httpTarget || {}).uri || '').includes(`/jobs/${job.name}:run`));
        const runs = (executions[job.name] || []).map(e => ({
            name: String(e.name || '').split('/').pop(),
            startedAt: e.startTime || e.createTime || null,
            finishedAt: e.completionTime || null,
            state: executionState(e),
        }));
        return {
            name: job.name,
            label: job.label,
            schedule: scheduler ? scheduler.schedule : null,
            timeZone: scheduler ? scheduler.timeZone : null,
            schedulerState: scheduler ? scheduler.state : null,
            nextRunAt: scheduler ? scheduler.scheduleTime || null : null,
            lastAttemptAt: scheduler ? scheduler.lastAttemptTime || null : null,
            lastAttemptOk: scheduler && scheduler.lastAttemptTime ? !(scheduler.status && scheduler.status.code) : null,
            lastRun: runs[0] || null,
            recent: runs.slice(0, 5),
        };
    });
}

module.exports = {
    bankSummary,
    claudeSummary,
    jobsSummary,
    lastDays,
    modelName,
    moneySummary,
    playersSummary,
};
