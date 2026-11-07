'use strict';

// ---- 共通 ----

const LEVELS = {
  green: { label: '緑', text: '予算どおり' },
  yellow: { label: '黄', text: '少し使いすぎ' },
  orange: { label: '橙', text: 'かなり使いすぎ' },
  red: { label: '赤', text: '今日の目安を使い切った' },
  stop: { label: '停止', text: '上限を超えたので新作を止めている' },
};
const STOP_REASONS = { daily_budget: '1日の上限', monthly_budget: '月の上限' };
const DENIAL_LABELS = {
  daily_budget: '全体の1日の上限',
  monthly_budget: '全体の月の上限',
  device_daily_budget: '端末の1日の上限',
  ip_daily_budget: '回線の1日の上限',
  device_blocked: 'ブロックした端末',
  ip_blocked: 'ブロックした回線',
  device_token: '許可証なし・不正な許可証',
  rate_limited: '回数制限（1分あたり）',
  session_rate_limited: '許可証の発行の回数制限',
  round_no_new: '新作0問にした試合',
};
const MODEL_COLORS = ['var(--accent)', 'var(--orange)', 'var(--green)', 'var(--yellow)', 'var(--red)', 'var(--stop)'];
const AUTO_REFRESH_MS = 60 * 1000;
const JOBS_REFRESH_MS = 5 * 60 * 1000;

const $ = id => document.getElementById(id);
const state = { tab: 'money', overview: null, jpy: 150, loaded: {}, busy: false };

function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function usd(value) {
  const v = Number(value || 0);
  if (v === 0) return '$0';
  const a = Math.abs(v);
  return `$${v.toFixed(a >= 0.1 ? 2 : a >= 0.01 ? 3 : 4)}`;
}

function yen(value) {
  return `¥${Math.round(Number(value || 0) * state.jpy).toLocaleString('ja-JP')}`;
}

function int(value) {
  return Number(value || 0).toLocaleString('ja-JP');
}

function pct(value, digits = 0) {
  return value === null || value === undefined ? '—' : `${(value * 100).toFixed(digits)}%`;
}

const jstFormat = new Intl.DateTimeFormat('ja-JP', {
  timeZone: 'Asia/Tokyo', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit',
});
function when(value) {
  if (!value) return '—';
  const date = typeof value === 'number' ? new Date(value * 1000) : new Date(value);
  return Number.isNaN(date.getTime()) ? '—' : jstFormat.format(date);
}

function shortDay(day) {
  const [, m, d] = day.split('-');
  return `${Number(m)}/${Number(d)}`;
}

function bar(value, max, { marker = null, soft = 0 } = {}) {
  const frac = max > 0 ? value / max : 0;
  const cls = frac >= 1 ? 'over' : frac >= 0.8 ? 'warn' : '';
  const width = Math.min(100, frac * 100);
  const softWidth = max > 0 ? Math.min(100 - width, (soft / max) * 100) : 0;
  const markerHtml = marker !== null && max > 0 ? `<b style="left:${Math.min(100, (marker / max) * 100)}%"></b>` : '';
  const softHtml = softWidth > 0 ? `<i class="soft" style="left:${width}%;width:${softWidth}%"></i>` : '';
  return `<div class="bar ${cls}"><i style="width:${width}%"></i>${softHtml}${markerHtml}</div>`;
}

// 区分ごとに積んだ横棒。parts は [{ value, color }]。soft はその後ろに薄い色で足す見込み
function stackBar(parts, max, { marker = null, soft = 0 } = {}) {
  let left = 0;
  let html = '';
  for (const p of parts) {
    const width = max > 0 ? Math.min(100 - left, (Number(p.value || 0) / max) * 100) : 0;
    if (width > 0) html += `<i style="left:${left}%;width:${width}%;background:${p.color}"></i>`;
    left += Math.max(0, width);
  }
  const softWidth = max > 0 ? Math.min(100 - left, (soft / max) * 100) : 0;
  if (softWidth > 0) html += `<i class="soft" style="left:${left}%;width:${softWidth}%"></i>`;
  if (marker !== null && max > 0) html += `<b style="left:${Math.min(100, (marker / max) * 100)}%"></b>`;
  return `<div class="bar">${html}</div>`;
}

function miniBar(frac) {
  const f = Number(frac || 0);
  const cls = f >= 1 ? 'over' : f >= 0.8 ? 'warn' : '';
  return `<span class="mini-bar ${cls}"><i style="width:${Math.min(100, f * 100)}%"></i></span>`;
}

function stat(label, value, sub = '') {
  return `<div class="card stat"><div class="label">${esc(label)}</div><div class="value">${value}</div>`
    + `<div class="sub">${sub}</div></div>`;
}

function table(headers, rows, empty = 'まだありません') {
  if (!rows.length) return `<div class="muted small">${esc(empty)}</div>`;
  const head = headers.map(h => `<th class="${h.r ? 'r' : ''}">${esc(h.label)}</th>`).join('');
  const body = rows.map(cells => `<tr>${cells.map((c, i) => `<td class="${headers[i].r ? 'r' : ''}">${c}</td>`).join('')}</tr>`).join('');
  return `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}

async function getJson(url) {
  const res = await fetch(url, { cache: 'no-store' });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `${url}: ${res.status}`);
  return body;
}

function showError(error) {
  const box = $('error');
  if (!error) {
    box.hidden = true;
    return;
  }
  box.hidden = false;
  box.textContent = `読み込みに失敗しました: ${error.message || error}`;
}

// ---- グラフ（SVG を手で描く） ----

function niceMax(value) {
  if (value <= 0) return 1;
  const exp = Math.pow(10, Math.floor(Math.log10(value)));
  for (const step of [1, 2, 2.5, 5, 10]) {
    if (value <= step * exp) return step * exp;
  }
  return 10 * exp;
}

// 回数のグラフは目盛りが整数になるように、4 で割り切れる上限にする
function axisMax(value, integer) {
  const max = niceMax(value);
  return integer ? Math.max(4, Math.ceil(max / 4) * 4) : max;
}

function barChart({ labels, series, line = null, format = v => v, lineFormat = v => v, integer = false, height = 180 }) {
  const width = 900;
  const pad = { top: 10, right: line ? 40 : 10, bottom: 22, left: 52 };
  const innerW = width - pad.left - pad.right;
  const innerH = height - pad.top - pad.bottom;
  const totals = labels.map((_, i) => series.reduce((sum, s) => sum + (s.values[i] || 0), 0));
  const max = axisMax(Math.max(...totals, 0), integer);
  const slot = innerW / labels.length;
  const barW = Math.max(2, slot * 0.7);
  let svg = `<svg viewBox="0 0 ${width} ${height}" role="img">`;
  for (let k = 0; k <= 4; k++) {
    const y = pad.top + innerH - (innerH * k) / 4;
    svg += `<line class="grid-line" x1="${pad.left}" x2="${width - pad.right}" y1="${y}" y2="${y}"/>`;
    svg += `<text x="${pad.left - 6}" y="${y + 3}" text-anchor="end">${esc(format((max * k) / 4))}</text>`;
  }
  labels.forEach((label, i) => {
    const x = pad.left + slot * i + (slot - barW) / 2;
    let y = pad.top + innerH;
    const tip = [label, ...series.map(s => `${s.name}: ${format(s.values[i] || 0)}`)].join('\n');
    svg += `<g><title>${esc(tip)}</title>`;
    for (const s of series) {
      const h = ((s.values[i] || 0) / max) * innerH;
      if (h <= 0) continue;
      y -= h;
      svg += `<rect x="${x}" y="${y}" width="${barW}" height="${h}" fill="${s.color}" rx="1"/>`;
    }
    svg += `<rect x="${pad.left + slot * i}" y="${pad.top}" width="${slot}" height="${innerH}" fill="transparent"/></g>`;
    // 日数が多いときは、今日から数えて3日おきに日付を出す
    if (labels.length <= 16 || (labels.length - 1 - i) % 3 === 0) {
      svg += `<text x="${pad.left + slot * i + slot / 2}" y="${height - 6}" text-anchor="middle">${esc(label)}</text>`;
    }
  });
  if (line) {
    const lineMax = axisMax(Math.max(...line.values, 0), integer);
    const points = line.values.map((v, i) => `${pad.left + slot * i + slot / 2},${pad.top + innerH - (v / lineMax) * innerH}`);
    svg += `<polyline points="${points.join(' ')}" fill="none" stroke="var(--orange)" stroke-width="2"/>`;
    line.values.forEach((v, i) => {
      svg += `<circle cx="${pad.left + slot * i + slot / 2}" cy="${pad.top + innerH - (v / lineMax) * innerH}" r="2.5" fill="var(--orange)"/>`;
    });
    for (let k = 0; k <= 4; k++) {
      const y = pad.top + innerH - (innerH * k) / 4;
      svg += `<text x="${width - pad.right + 6}" y="${y + 3}">${esc(lineFormat((lineMax * k) / 4))}</text>`;
    }
  }
  return `${svg}</svg>`;
}

// ---- お金 ----

function renderMoney(m) {
  const g = m.live;
  const level = LEVELS[g.level] || LEVELS.stop;
  const first = g.newCount.first;
  const later = g.newCount.later;
  let note = `試合中の Claude の新作は、各端末のその日の最初の${g.newCount.priorityRounds}試合が10問中${first}問、3試合目からは${later}問。残りは共有バンクなどで埋めます。`;
  if (g.forcedLevel) note += `（プロキシの設定 ROUND_PLAN_FORCE_LEVEL で「${LEVELS[g.forcedLevel].label}」に固定中）`;
  if (g.stopReason) note += `（${STOP_REASONS[g.stopReason] || g.stopReason}に達しています）`;
  $('money-level').className = `level-card level-${g.level}`;
  $('money-level').innerHTML = `<span class="level-badge badge-${g.level}">${level.label}</span>`
    + `<div><div><b>今の段階: ${esc(level.text)}</b></div><div class="muted small">${esc(note)}</div></div>`;

  // Claude 全体（試合中＋毎週のジョブ）を Claude Console の支出上限に対して見る
  const total = m.total;
  const c = m.batch;
  const totalParts = [
    { name: '試合中', value: g.month.usd, budget: g.month.budgetUsd, color: 'var(--accent)' },
    { name: '判定', value: c.review.usd, budget: c.review.budgetUsd, color: 'var(--orange)' },
    { name: '補充', value: c.builder.usd, budget: c.builder.budgetUsd, color: 'var(--green)' },
  ];
  const legacy = m.legacyGeminiUsd > 0
    ? `<div class="row" style="margin-top:6px"><span>旧 Gemini 系統（aiquiz-proxy）からも今月 ${usd(m.legacyGeminiUsd)} 使われています。Google の請求で、上の合計には入りません</span></div>` : '';
  $('money-total').innerHTML = `<h2>Claude 今月の合計（${esc(m.month)}・Claude Console の支出上限 ${usd(total.capUsd)}）</h2>`
    + `<div class="big">${usd(total.usd)} <small>/ ${usd(total.capUsd)}　${yen(total.usd)} / ${yen(total.capUsd)}</small></div>`
    + stackBar(totalParts, total.capUsd, { marker: total.budgetUsd, soft: total.inflightUsd })
    + `<div class="legend" style="margin-top:4px">${totalParts.map(p => `<span><i class="swatch" style="background:${p.color}"></i>`
      + `${esc(p.name)} ${usd(p.value)} / ${usd(p.budget)}</span>`).join('')}`
    + `<span><i class="swatch" style="background:var(--accent-soft)"></i>回収待ちの見込み ${usd(total.inflightUsd)}</span></div>`
    + `<div class="row" style="margin-top:4px"><span>縦線: 3つの上限の合計 ${usd(total.budgetUsd)}（それぞれの上限でも止まります）</span>`
    + `<span>${total.usd + total.inflightUsd > total.budgetUsd ? '上限の合計を超えそうです' : `残り ${usd(total.budgetUsd - total.usd - total.inflightUsd)}`}</span></div>`
    + legacy;

  const t = g.today;
  $('money-today').innerHTML = `<h2>試合中の Claude 今日（${esc(shortDay(m.day))}）</h2>`
    + `<div class="big">${usd(t.usd)} <small>/ ${usd(t.budgetUsd)}　${yen(t.usd)}</small></div>`
    + bar(t.usd, t.budgetUsd, { marker: t.targetUsd })
    + `<div class="row"><span>今日の目安 ${usd(t.targetUsd)}（縦線）</span><span>${int(t.requests)} 回</span></div>`
    + `<div class="row"><span>今日の経過 ${pct(g.timeFrac)}</span><span>目安に対して ${t.targetUsd > 0 ? pct(t.usd / t.targetUsd) : '—'}</span></div>`;

  const mo = g.month;
  const projection = mo.projectedUsd === null ? '月の初日はまだ出しません'
    : `このペースだと月末 ${usd(mo.projectedUsd)}（${yen(mo.projectedUsd)}）${mo.projectedUsd > mo.budgetUsd ? '→ 上限で止まります' : ''}`;
  $('money-month').innerHTML = `<h2>試合中の Claude 今月（${esc(m.month)}）</h2>`
    + `<div class="big">${usd(mo.usd)} <small>/ ${usd(mo.budgetUsd)}　${yen(mo.usd)} / ${yen(mo.budgetUsd)}</small></div>`
    + bar(mo.usd, mo.budgetUsd, { marker: mo.budgetUsd * (mo.elapsedDays / mo.daysInMonth) })
    + `<div class="row"><span>縦線: 今日までの予定額</span><span>${int(mo.requests)} 回</span></div>`
    + `<div class="row"><span>${esc(projection)}</span></div>`;

  const part = (title, p) => `<div class="row" style="margin-top:6px"><span><b style="color:var(--text)">${esc(title)}</b> ${esc(p.model)}</span>`
    + `<span>${usd(p.usd)} / ${usd(p.budgetUsd)}</span></div>`
    + bar(p.usd, p.budgetUsd, { soft: p.inflight.estUsd })
    + `<div class="row"><span>${p.inflight.batches ? `回収待ち ${p.inflight.batches} 件（見込み ${usd(p.inflight.estUsd)}、薄い色）` : '回収待ちなし'}</span></div>`;
  $('money-batch').innerHTML = `<h2>毎週のジョブ 今月（Batch）</h2>`
    + `<div class="big">${usd(c.totalUsd)} <small>/ ${usd(c.totalBudgetUsd)}　${yen(c.totalUsd)}</small></div>`
    + part('判定', c.review) + part('補充', c.builder);

  const models = [...new Set(g.history.flatMap(h => Object.keys(h.models)))].sort();
  const series = models.map((name, i) => ({
    name, color: MODEL_COLORS[i % MODEL_COLORS.length], values: g.history.map(h => h.models[name] || 0),
  }));
  if (!series.length) series.push({ name: '使用額', color: MODEL_COLORS[0], values: g.history.map(h => h.usd) });
  $('money-chart').innerHTML = barChart({ labels: g.history.map(h => shortDay(h.day)), series, format: v => usd(v) });
  $('money-legend').innerHTML = series.map(s => `<span><i class="swatch" style="background:${s.color}"></i>${esc(s.name)}</span>`).join('')
    + `<span>1日の上限 ${usd(t.budgetUsd)}</span>`;

  const modelTable = rows => table(
    [{ label: 'モデル' }, { label: '回数', r: true }, { label: '使用額', r: true }, { label: '円', r: true }],
    rows.map(r => [esc(r.model), int(r.requests), usd(r.usd), yen(r.usd)]),
  );
  $('models-today').innerHTML = modelTable(g.modelsToday);
  $('models-month').innerHTML = modelTable(g.modelsMonth);
}

// ---- 共有バンク ----

function heatClass(cell, target) {
  if (!cell || !cell.planned) return 'heat-none';
  const f = cell.bank / target;
  if (f >= 1) return 'heat-3';
  if (f >= 0.5) return 'heat-2';
  if (cell.bank > 0) return 'heat-1';
  return 'heat-0';
}

function renderBank(b) {
  const t = b.totals;
  const r = b.review;
  $('bank-totals').innerHTML = [
    stat('共有バンクの問題', int(t.bank), `補充 ${int(b.origins.builder)}／試合中の生成 ${int(b.origins.match)}`),
    stat('目標に届いた区分', `${t.bucketsAtTarget} <small class="muted">/ ${t.plannedBuckets}</small>`, `空の区分 ${t.emptyBuckets}／不足 ${int(t.shortfall)} 問`),
    stat('判定待ち', int(b.pending.waiting), `次の判定のジョブで送る（1回 ${int(state.overview?.review?.maxPerRun || 0)} 問まで）`),
    stat('判定中', int(b.pending.inReview), `保留 ${int(b.pending.unsure)}／エラー ${int(b.pending.errored)}`),
    stat('Claude の合格率', pct(r.passRate, 1), `直近7日 ${pct(r.week.passRate, 1)}（合格 ${int(r.week.pass)}・不合格 ${int(r.week.fail)}）`),
  ].join('');
  $('bank-target').textContent = int(b.target);
  fillSearchFilters(b);
  $('bank-fetched').innerHTML = `データ取得 ${esc(when(b.fetchedAt))}（重いので10分間は同じ結果）`
    + ' <button class="btn" id="bank-reload">今すぐ読み直す</button>';
  $('bank-reload').onclick = () => loadBank(true);

  const byKey = new Map(b.cells.map(c => [`${c.subject}|${c.grade}|${c.difficulty}`, c]));
  $('bank-grid').innerHTML = b.subjects.map(subject => {
    const head = `<tr><th></th>${b.difficulties.map(d => `<th>${esc(d)}</th>`).join('')}</tr>`;
    const rows = b.grades.map(grade => `<tr><th>${grade}年</th>${b.difficulties.map(d => {
      const cell = byKey.get(`${subject}|${grade}|${d}`);
      if (!cell || !cell.planned) {
        return `<td class="heat-none" title="補充の対象外">${cell && cell.bank ? int(cell.bank) : '—'}</td>`;
      }
      const tip = `${subject} ${grade}年 ${d}\n共有バンク ${cell.bank} 問／判定待ち・判定中 ${cell.pending} 問`;
      return `<td class="${heatClass(cell, b.target)}" title="${esc(tip)}">${int(cell.bank)}`
        + `${cell.pending ? `<span class="p">+${int(cell.pending)}</span>` : ''}</td>`;
    }).join('')}</tr>`).join('');
    return `<table><caption>${esc(subject)}</caption>${head}${rows}</table>`;
  }).join('');
  $('bank-legend').innerHTML = [
    ['heat-0', '0 問'], ['heat-1', `${int(b.target / 2)} 問未満`], ['heat-2', `${int(b.target)} 問未満`],
    ['heat-3', `${int(b.target)} 問以上`], ['heat-none', '補充の対象外'],
  ].map(([cls, label]) => `<span><i class="swatch ${cls}"></i>${esc(label)}</span>`).join('')
    + '<span>小さい「+数字」は判定待ち・判定中の数</span>';

  const stateTag = s => (s === 'collected' ? '<span class="tag ok">回収済み</span>' : '<span class="tag run">回収待ち</span>');
  $('builder-batches').innerHTML = table(
    [{ label: '送信' }, { label: '状態' }, { label: '依頼', r: true }, { label: '入った問題', r: true }, { label: '実費', r: true }],
    b.builderBatches.map(x => [esc(when(x.submittedAt)), stateTag(x.state), int(x.count),
      x.questions === null ? '—' : int(x.questions), x.usd === null ? '—' : usd(x.usd)]),
  );
  $('review-batches').innerHTML = table(
    [{ label: '送信' }, { label: '状態' }, { label: '問題', r: true }, { label: '合格', r: true }, { label: '不合格', r: true },
      { label: '合格率', r: true }, { label: '実費', r: true }],
    b.reviewBatches.map(x => [esc(when(x.submittedAt)), stateTag(x.state), int(x.count),
      x.state === 'collected' ? int(x.pass) : '—', x.state === 'collected' ? int(x.fail) : '—',
      x.pass + x.fail > 0 ? pct(x.pass / (x.pass + x.fail), 1) : '—', x.usd === null ? '—' : usd(x.usd)]),
  );
}

function renderJobs(jobs) {
  const runTag = run => {
    if (!run) return '<span class="tag">まだ動いていない</span>';
    if (run.state === 'succeeded') return '<span class="tag ok">成功</span>';
    if (run.state === 'running') return '<span class="tag run">実行中</span>';
    return '<span class="tag bad">失敗</span>';
  };
  $('jobs').innerHTML = jobs.map(job => {
    const schedule = job.scheduleText || '予定なし';
    const recent = job.recent.map(r => `${runTag(r)} <span class="small muted">${esc(when(r.startedAt))}</span>`).join('　');
    return `<div class="card"><h2>${esc(job.label)}</h2>`
      + `<div class="row"><span>前回 ${runTag(job.lastRun)} ${esc(when(job.lastRun && job.lastRun.startedAt))}</span>`
      + `<span>次回 ${esc(when(job.nextRunAt))}（${esc(schedule)}${job.schedulerState && job.schedulerState !== 'ENABLED' ? '・停止中' : ''}）</span></div>`
      + `<div class="small muted" style="margin-top:6px">最近: ${recent || '—'}</div>`
      + `<div style="margin-top:8px"><button class="btn small" data-action="run-job" data-name="${esc(job.name)}" data-label="${esc(job.label)}">今すぐ実行</button></div></div>`;
  }).join('');
}

// ---- プレイヤー ----

function shortId(id) {
  return id.length > 12 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id;
}

function renderPlayers(p) {
  const t = p.today;
  $('players-totals').innerHTML = [
    stat('今日の試合数', int(t.rounds), '新作の数を聞きに来た回数'),
    stat('遊んだ端末', int(t.devices), `新作を作った端末 ${int(t.generatingDevices)}`),
    stat('回線', int(t.ips), '使用額が記録された回線'),
    stat('1試合あたり', t.usdPerRound === null ? '—' : usd(t.usdPerRound), t.usdPerRound === null ? '' : yen(t.usdPerRound)),
    stat('上限の8割を超えた端末', int(t.nearCapDevices), `上限に達した ${int(t.atCapDevices)}（1日 ${usd(p.caps.deviceUsd)}）`),
    stat('ブロック中', int(t.blockedCount), 'device_blocklist の件数'),
  ].join('');

  $('players-chart').innerHTML = barChart({
    labels: p.history.map(h => shortDay(h.day)),
    series: [{ name: '試合数', color: 'var(--accent)', values: p.history.map(h => h.rounds) }],
    line: { values: p.history.map(h => h.devices) },
    format: v => int(v),
    lineFormat: v => int(v),
    integer: true,
  });

  const blockedTag = row => (row.blocked ? ' <span class="tag bad">ブロック中</span>' : '');
  const blockButton = (kind, row) => (row.blocked
    ? `<button class="btn small" data-action="unblock" data-key="${esc(row.id)}">解除</button>`
    : `<button class="btn small danger" data-action="block" data-kind="${kind}" data-key="${esc(row.id)}">ブロック</button>`);
  $('top-devices').innerHTML = table(
    [{ label: '端末' }, { label: '上限比' }, { label: '使用額', r: true }, { label: '試合', r: true }, { label: '回数', r: true }, { label: '', r: true }],
    p.topDevices.map(d => [`<span class="id" title="${esc(d.id)}">${esc(shortId(d.id))}</span>${blockedTag(d)}`,
      `${miniBar(d.capPct)}${pct(d.capPct)}`, usd(d.usd), int(d.rounds), int(d.requests), blockButton('device', d)]),
    '今日はまだ誰も遊んでいません',
  );
  $('top-ips').innerHTML = table(
    [{ label: '回線（暗号化した値）' }, { label: '上限比' }, { label: '使用額', r: true }, { label: '回数', r: true }, { label: '', r: true }],
    p.topIps.map(d => [`<span class="id" title="${esc(d.id)}">${esc(shortId(d.id))}</span>${blockedTag(d)}`,
      `${miniBar(d.capPct)}${pct(d.capPct, 1)}`, usd(d.usd), int(d.requests), blockButton('ip', d)]),
    '今日はまだ記録がありません',
  ) + `<div class="small muted" style="margin-top:6px">回線の上限は1日 ${usd(p.caps.ipUsd)}。学校など同じ回線から大勢が遊ぶと増えます。</div>`;

  $('denials').innerHTML = table(
    [{ label: '理由' }, { label: '回数', r: true }],
    p.denials.map(d => [`${esc(DENIAL_LABELS[d.reason] || d.reason)} <span class="small muted id">${esc(d.reason)}</span>`, int(d.count)]),
    '今日はまだ止めていません',
  ) + '<div class="small muted" style="margin-top:6px">プロキシに記録の仕組みを入れた後から数えます（10秒ごとにまとめて記録）。</div>';

  $('blocked-list').innerHTML = table(
    [{ label: '種類' }, { label: 'ID' }, { label: '理由' }, { label: 'ブロックした日時' }, { label: '', r: true }],
    p.blockedList.map(b => [b.kind === 'ip' ? '回線' : '端末', `<span class="id" title="${esc(b.key)}">${esc(shortId(b.key))}</span>`,
      esc(b.reason || '—'), esc(when(b.at)), `<button class="btn small" data-action="unblock" data-key="${esc(b.key)}">解除</button>`]),
    'ブロックしている端末・回線はありません',
  );
}

// ---- 問題を探す ----

function fillSearchFilters(b) {
  const fill = (id, values, format = v => v) => {
    const select = $(id);
    if (select.options.length > 1) return;
    for (const v of values) select.add(new Option(format(v), v));
  };
  fill('q-subject', b.subjects);
  fill('q-grade', b.grades, g => `${g}年`);
  fill('q-difficulty', b.difficulties);
}

const ORIGIN_LABELS = {
  CLAUDE_HAIKU: '補充（Haiku）', CLAUDE: '試合中の生成（Claude）', CLAUDE_STREAM: '試合中の生成（Claude）',
  CLAUDE_POOL: '試合中の生成（Claude）', GEMINI: '試合中の生成（Gemini・旧）', GEMINI_STREAM: '試合中の生成（Gemini・旧）',
  GEMINI_POOL: '試合中の生成（Gemini・旧）', OPENAI: '試合中の生成（OpenAI・旧）',
};
const VERDICT_LABELS = { pass: '合格', fail: '不合格', unsure: '保留' };

async function searchQuestions() {
  const params = new URLSearchParams();
  const removed = $('q-removed').checked;
  for (const [key, id] of [['text', 'q-text'], ['id', 'q-id'], ['subject', 'q-subject'], ['grade', 'q-grade'], ['difficulty', 'q-difficulty']]) {
    const value = $(id).value.trim();
    if (value) params.set(key, value);
  }
  if (removed) params.set('removed', '1');
  if (!removed && !params.toString()) {
    $('q-results').innerHTML = '<div class="muted small">言葉・ID・教科などを入れて探してください。</div>';
    return;
  }
  $('q-results').innerHTML = '<div class="muted small">探しています…</div>';
  try {
    const r = await getJson(`/api/questions?${params}`);
    if (!r.items.length) {
      $('q-results').innerHTML = '<div class="muted small">見つかりませんでした。</div>';
      return;
    }
    $('q-results').innerHTML = `<div class="small muted">${int(r.total)} 件${r.total > r.items.length ? `（先頭 ${r.items.length} 件を表示）` : ''}</div>`
      + r.items.map(renderQuestion).join('');
  } catch (error) {
    $('q-results').innerHTML = `<div class="muted small">探せませんでした: ${esc(error.message)}</div>`;
  }
}

function renderQuestion(item) {
  const answer = Number(item.a);
  const choices = item.c.map((c, i) => `<span class="${i === answer ? 'correct' : ''}">${i === answer ? '◯ ' : ''}${esc(c)}</span>`).join('');
  const review = item.review
    ? `Claude 判定: ${esc(VERDICT_LABELS[item.review.verdict] || item.review.verdict)}${item.review.note ? `（${esc(item.review.note)}）` : ''}`
    : 'Claude 判定: まだ';
  const removedInfo = item.removed
    ? `<div class="q-meta">外した日時 ${esc(when(item.removed.at))}・理由 ${esc(item.removed.reason || '—')}</div>` : '';
  const button = item.removed
    ? `<button class="btn small" data-action="restore-question" data-id="${esc(item.id)}" data-q="${esc(item.q)}">共有バンクに戻す</button>`
    : `<button class="btn small danger" data-action="remove-question" data-id="${esc(item.id)}" data-q="${esc(item.q)}">共有バンクから外す</button>`;
  return `<div class="q-item"><div class="q-main"><div class="q-text">${esc(item.q)}</div>`
    + `<div class="q-choices">${choices}</div>`
    + (item.e ? `<div class="q-meta">解説: ${esc(item.e)}</div>` : '')
    + `<div class="q-meta">${esc(item.subject)} ${esc(item.grade)}年 ${esc(item.difficulty)}・`
    + `${esc(ORIGIN_LABELS[item.origin] || item.origin || '出どころ不明')}・出題 ${int(item.seenCount)} 回・${review}</div>`
    + `<div class="q-meta id">${esc(item.id)}</div>${removedInfo}</div><div>${button}</div></div>`;
}

// ---- 記録 ----

const LOG_LABELS = {
  block: 'ブロック', unblock: 'ブロック解除', remove_question: '問題を外した',
  restore_question: '問題を戻した', run_job: 'ジョブを実行',
};

async function loadLog() {
  const rows = await getJson('/api/log');
  $('ops-log').innerHTML = table(
    [{ label: '日時' }, { label: '操作' }, { label: '対象' }, { label: '内容' }, { label: '操作した人' }],
    rows.map(r => [esc(when(r.at)), esc(LOG_LABELS[r.action] || r.action),
      `<span class="id" title="${esc(r.target)}">${esc(shortId(String(r.target || '')))}</span>`,
      esc([r.kind === 'ip' ? '回線' : r.kind === 'device' ? '端末' : '', r.q, r.reason ? `理由: ${r.reason}` : '', r.execution]
        .filter(Boolean).join('　')),
      esc(r.by || '')]),
    'まだ操作していません',
  );
}

// ---- 操作（確認してから実行） ----

function confirmAction({ title, body, confirmLabel = '実行', askReason = true }) {
  const dialog = $('confirm');
  $('confirm-title').textContent = title;
  $('confirm-body').innerHTML = body;
  $('confirm-ok').textContent = confirmLabel;
  $('confirm-reason').value = '';
  $('confirm-reason-wrap').hidden = !askReason;
  dialog.returnValue = '';
  dialog.showModal();
  return new Promise(resolve => {
    dialog.addEventListener('close', () => {
      resolve(dialog.returnValue === 'ok' ? { reason: $('confirm-reason').value.trim() } : null);
    }, { once: true });
  });
}

let toastTimer = null;
function toast(message, bad = false) {
  const box = $('toast');
  box.textContent = message;
  box.className = bad ? 'toast bad' : 'toast';
  box.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { box.hidden = true; }, bad ? 8000 : 4000);
}

async function postAction(name, body) {
  const res = await fetch(`/api/actions/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Ops-Request': '1' },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `${res.status}`);
  return data;
}

const ACTIONS = {
  async block(el) {
    const kind = el.dataset.kind;
    const key = el.dataset.key;
    const what = kind === 'ip' ? '回線' : '端末';
    const ok = await confirmAction({
      title: `${what}をブロックしますか？`,
      body: `<p class="id">${esc(key)}</p><p>1分ほどで、この${what}からの新作の生成が止まります（共有バンクの問題では遊べます）。`
        + `${kind === 'ip' ? '同じ回線（学校や家）のほかの人も止まります。' : ''}あとで解除できます。</p>`,
      confirmLabel: 'ブロックする',
    });
    if (!ok) return false;
    await postAction('block', { kind, key, reason: ok.reason });
    toast(`${what}をブロックしました`);
    await loadPlayers();
    return true;
  },
  async unblock(el) {
    const key = el.dataset.key;
    const ok = await confirmAction({
      title: 'ブロックを解除しますか？',
      body: `<p class="id">${esc(key)}</p><p>1分ほどで、また新作を作れるようになります。</p>`,
      confirmLabel: '解除する',
      askReason: false,
    });
    if (!ok) return false;
    await postAction('unblock', { key });
    toast('ブロックを解除しました');
    await loadPlayers();
    return true;
  },
  async 'remove-question'(el) {
    const ok = await confirmAction({
      title: 'この問題を共有バンクから外しますか？',
      body: `<p><b>${esc(el.dataset.q)}</b></p><p>各プレイヤーの端末からも、次の同期で消えます。`
        + '判定や投票で勝手に戻ることはありません。「外した問題を表示」から戻せます。</p>',
      confirmLabel: '外す',
    });
    if (!ok) return false;
    await postAction('remove-question', { id: el.dataset.id, reason: ok.reason });
    toast('共有バンクから外しました');
    await searchQuestions();
    return true;
  },
  async 'restore-question'(el) {
    const ok = await confirmAction({
      title: 'この問題を共有バンクに戻しますか？',
      body: `<p><b>${esc(el.dataset.q)}</b></p><p>各プレイヤーの端末にも、次の同期で届きます。</p>`,
      confirmLabel: '戻す',
      askReason: false,
    });
    if (!ok) return false;
    await postAction('restore-question', { id: el.dataset.id });
    toast('共有バンクに戻しました');
    await searchQuestions();
    return true;
  },
  async 'run-job'(el) {
    const isBuilder = el.dataset.name === 'quiz-bank-builder';
    const o = state.overview || {};
    const body = isBuilder
      ? `<p>終わっている Batch を回収し、足りない区分の問題作りを新しく頼みます（最大 ${int(o.builder?.maxCallsPerRun)} 回・見込み $0.6 前後）。</p>`
        + `<p>月の上限 ${usd(o.builder?.monthlyBudgetUsd)} は守られます。回収待ちの Batch も上限に含めて計算します。</p>`
      : `<p>終わっている判定を回収して合格した問題を共有バンクに入れ、判定待ちを新しく Opus に送ります（1回 ${int(o.review?.maxPerRun)} 問まで）。</p>`
        + `<p>月の上限 ${usd(o.review?.monthlyBudgetUsd)} は守られます。</p>`;
    const ok = await confirmAction({
      title: `${el.dataset.label}を今すぐ実行しますか？`,
      body: `${body}<p>Claude のクレジットを使います。</p>`,
      confirmLabel: '実行する',
      askReason: false,
    });
    if (!ok) return false;
    const r = await postAction('run-job', { name: el.dataset.name });
    toast(`実行を始めました（${r.execution || r.name}）`);
    setTimeout(() => loadJobs().catch(() => {}), 5000);
    return true;
  },
};

document.addEventListener('click', async event => {
  const el = event.target.closest('[data-action]');
  if (!el || !ACTIONS[el.dataset.action]) return;
  event.preventDefault();
  el.disabled = true;
  try {
    await ACTIONS[el.dataset.action](el);
  } catch (error) {
    toast(`できませんでした: ${error.message}`, true);
  } finally {
    el.disabled = false;
  }
});

$('q-form').addEventListener('submit', event => {
  event.preventDefault();
  searchQuestions();
});
$('q-removed').addEventListener('change', searchQuestions);
$('block-form').addEventListener('submit', async event => {
  event.preventDefault();
  const key = $('block-key').value.trim();
  if (!key) return;
  try {
    if (await ACTIONS.block({ dataset: { kind: $('block-kind').value, key } })) $('block-key').value = '';
  } catch (error) {
    toast(`できませんでした: ${error.message}`, true);
  }
});

// ---- 読み込み ----

function setUpdated() {
  $('updated').textContent = `最終更新 ${jstFormat.format(new Date())}`;
}

async function loadOverview() {
  state.overview = await getJson('/api/overview');
  const o = state.overview;
  $('foot').textContent = `プロキシ ${o.service} ${o.revision}（${o.gcpProject}）／ 1ドル ${state.jpy} 円で換算`
    + ` ／ 端末の上限 1日 ${usd(o.caps.deviceUsd)}（最初の24時間は ${usd(o.caps.newDeviceUsd)}）・回線 ${usd(o.caps.ipUsd)}`;
}

async function loadMoney() {
  const m = await getJson('/api/money');
  state.jpy = m.jpyPerUsd || state.jpy;
  renderMoney(m);
}

async function loadPlayers() {
  renderPlayers(await getJson('/api/players'));
}

async function loadBank(refresh = false) {
  const button = $('bank-reload');
  if (button) button.disabled = true;
  try {
    renderBank(await getJson(`/api/bank${refresh ? '?refresh=1' : ''}`));
    showError(null);
  } catch (error) {
    showError(error);
  } finally {
    if ($('bank-reload')) $('bank-reload').disabled = false;
  }
}

async function loadJobs() {
  renderJobs(await getJson('/api/jobs'));
}

async function refreshTab(tab, { force = false } = {}) {
  if (state.busy) return;
  state.busy = true;
  $('refresh').disabled = true;
  try {
    if (!state.overview) await loadOverview();
    if (tab === 'money') await loadMoney();
    if (tab === 'players') await loadPlayers();
    if (tab === 'log') await loadLog();
    if (tab === 'pipeline') await loadPipeline({ force });
    if (tab === 'bank') {
      await Promise.all([
        force || !state.loaded.bank ? loadBank(force) : null,
        force || !state.loaded.jobs || Date.now() - state.loaded.jobs > JOBS_REFRESH_MS ? loadJobs().then(() => { state.loaded.jobs = Date.now(); }) : null,
      ]);
      state.loaded.bank = true;
    }
    setUpdated();
    showError(null);
  } catch (error) {
    showError(error);
  } finally {
    state.busy = false;
    $('refresh').disabled = false;
  }
}

function selectTab(tab) {
  if (!['money', 'pipeline', 'bank', 'players', 'log'].includes(tab)) tab = 'money';
  state.tab = tab;
  for (const button of document.querySelectorAll('.tabs button')) {
    button.setAttribute('aria-selected', String(button.dataset.tab === tab));
  }
  for (const section of document.querySelectorAll('.tab')) section.hidden = section.id !== `tab-${tab}`;
  if (location.hash !== `#${tab}`) history.replaceState(null, '', `#${tab}`);
  refreshTab(tab);
}

for (const button of document.querySelectorAll('.tabs button')) {
  button.addEventListener('click', () => selectTab(button.dataset.tab));
}
$('refresh').addEventListener('click', () => refreshTab(state.tab, { force: true }));

// お金とプレイヤーは1分ごとに読み直す（共有バンクは重いので手動か、タブを開いたときだけ）
setInterval(() => {
  if (document.visibilityState === 'visible' && ['money', 'pipeline', 'players'].includes(state.tab) && !$('confirm').open) refreshTab(state.tab);
}, AUTO_REFRESH_MS);

window.addEventListener('hashchange', () => {
  if (location.hash.slice(1) !== state.tab) selectTab(location.hash.slice(1));
});
// 生成ラインの図（pipeline.js）も読み込んでから始める
window.addEventListener('DOMContentLoaded', () => selectTab(location.hash.slice(1)));
