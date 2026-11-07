'use strict';

// 「生成ライン」のタブ: 問題がどこで作られ、どう確かめられ、どこから出題されるかの図。
// 箱には今の数字（お金・プレイヤー・共有バンク・毎週のジョブの各 API から）を載せる。
// 試合中の AI は 2026-11-03 から Claude（aiquiz-proxy-claude。モデルはプロキシが用途ごとに決める）。
// app.js の共通部品（$, esc, usd, int, pct, when, getJson, LEVELS, DENIAL_LABELS）を使う。

const PIPE = {
  width: 1270,
  height: 650,
  nodeW: 174,
  nodeH: 84,
};

// x, y は箱の左上（列は 210 おき。箱の幅 174 との差の 36 が矢印とことばの通り道）。
// kind で色を分ける。tab を付けた箱は押すとそのタブに移る
const PIPE_NODES = [
  { id: 'game', x: 20, y: 50, kind: 'player', tab: 'players', title: 'ゲーム（試合開始）',
    lines: d => [`今日 ${int(d.players?.today.rounds)} 試合`, `端末 ${int(d.players?.today.devices)} 台`] },
  { id: 'plan', x: 230, y: 50, kind: 'proxy', tab: 'money', title: '新作の数を決める',
    lines: d => {
      const g = d.money?.live;
      if (!g) return ['—'];
      const level = LEVELS[g.level] || LEVELS.stop;
      return [`段階: ${level.label}（${level.text}）`,
        `最初の${g.newCount.priorityRounds}試合 新作 ${g.newCount.first} 問`, `3試合目から 新作 ${g.newCount.later} 問`];
    } },
  { id: 'split', x: 440, y: 50, kind: 'player', title: '10問の枠を分ける',
    lines: () => ['新作 N 問', '＋ ストック 10−N 問'] },
  { id: 'gate', x: 650, y: 50, kind: 'proxy', tab: 'players', title: 'プロキシの関所',
    lines: d => ['合言葉・許可証・上限・予算',
      `今日止めた ${int((d.players?.denials || []).filter(x => x.reason !== 'round_no_new').reduce((s, x) => s + x.count, 0))} 回`] },
  { id: 'live', x: 860, y: 50, kind: 'claude', tab: 'money', title: 'Claude（新作）',
    lines: d => [`今日 ${usd(d.money?.live.today.usd)}・${int(d.money?.live.today.requests)} 回`,
      'Sonnet 5.5・6本同時に作る'] },
  { id: 'check', x: 1070, y: 50, kind: 'player', title: '端末でチェック',
    lines: () => ['重複・形式・ジャンル', '正解を Sonnet 5.5 で確認'] },

  { id: 'stock', x: 440, y: 190, kind: 'store', tab: 'bank', title: 'ストックで埋める',
    lines: () => ['共有バンク → 端末内', '→ 同梱 → 別の難易度'] },
  { id: 'play', x: 1070, y: 190, kind: 'player', tab: 'players', title: '出題（壁）',
    lines: d => [`1試合あたり ${d.players?.today.usdPerRound == null ? '—' : usd(d.players.today.usdPerRound)}`,
      '解説も Sonnet 5.5'] },

  { id: 'sync', x: 20, y: 340, kind: 'store', title: '差分同期',
    lines: () => ['変わった分だけ', '各端末へ届ける'] },
  { id: 'bank', x: 230, y: 340, kind: 'store', tab: 'bank', title: '共有バンク',
    lines: d => (d.bank ? [`${int(d.bank.totals.bank)} 問`,
      `目標達成 ${d.bank.totals.bucketsAtTarget}/${d.bank.totals.plannedBuckets} 区分`] : ['読み込み中…']) },
  { id: 'review', x: 440, y: 340, kind: 'claude', tab: 'bank', title: '判定（Opus・毎週）',
    lines: d => [`合格率 ${d.bank ? pct(d.bank.review.passRate, 1) : '—'}`,
      `今月 ${usd(d.money?.batch.review.usd)} / ${usd(d.money?.batch.review.budgetUsd)}`, jobLine(d, 'quiz-claude-review')] },
  { id: 'archive', x: 650, y: 340, kind: 'store', tab: 'bank', title: 'アーカイブ（候補）',
    lines: d => (d.bank ? [`判定待ち ${int(d.bank.pending.waiting)} 問`, `判定中 ${int(d.bank.pending.inReview)} 問`]
      : ['読み込み中…']) },
  { id: 'outbox', x: 1070, y: 340, kind: 'player', title: '候補として送る',
    lines: () => ['試合中に作った問題を', '通信の合間に送信'] },

  { id: 'rejected', x: 440, y: 480, kind: 'muted', tab: 'bank', title: '不合格（使わない）',
    lines: d => [d.bank ? `${int(d.bank.archive.bad)} 問` : '—'] },
  { id: 'builder', x: 650, y: 480, kind: 'claude', tab: 'bank', title: '補充（Haiku・毎週）',
    lines: d => [`今月 ${usd(d.money?.batch.builder.usd)} / ${usd(d.money?.batch.builder.budgetUsd)}`,
      jobLine(d, 'quiz-bank-builder')] },
  { id: 'ops', x: 1070, y: 480, kind: 'ops', tab: 'log', title: '管理ソフト（この画面）',
    lines: d => [`ブロック中 ${int(d.players?.today.blockedCount)} 件`, '問題を外す・戻す'] },
];

// from/to の辺（top/right/bottom/left）。via は途中で通る点（重なりを避ける道）
const PIPE_EDGES = [
  { from: 'game', fs: 'right', to: 'plan', ts: 'left' },
  { from: 'plan', fs: 'right', to: 'split', ts: 'left' },
  { from: 'split', fs: 'right', to: 'gate', ts: 'left', label: '新作' },
  { from: 'gate', fs: 'right', to: 'live', ts: 'left' },
  { from: 'live', fs: 'right', to: 'check', ts: 'left' },
  { from: 'check', fs: 'bottom', to: 'play', ts: 'top' },
  { from: 'split', fs: 'bottom', to: 'stock', ts: 'top', label: 'ストック' },
  { from: 'stock', fs: 'right', to: 'play', ts: 'left', label: 'すぐ出せる問題' },
  { from: 'play', fs: 'bottom', to: 'outbox', ts: 'top', label: '作った問題' },
  { from: 'outbox', fs: 'left', to: 'archive', ts: 'right', label: '/quiz-bank' },
  { from: 'builder', fs: 'top', to: 'archive', ts: 'bottom', label: '足りない区分', tone: 'claude' },
  { from: 'archive', fs: 'left', to: 'review', ts: 'right', label: '判定', tone: 'claude' },
  { from: 'review', fs: 'left', to: 'bank', ts: 'right', label: '合格', tone: 'claude' },
  { from: 'review', fs: 'bottom', to: 'rejected', ts: 'top', label: '不合格' },
  { from: 'bank', fs: 'left', to: 'sync', ts: 'right' },
  { from: 'sync', fs: 'top', to: 'stock', ts: 'left', via: [[107, 232]], label: '端末の共有バンク' },
  { from: 'ops', fs: 'left', to: 'gate', ts: 'bottom', via: [[1050, 522], [1050, 160], [737, 160]], label: 'ブロック', labelAt: [900, 160], tone: 'ops' },
  { from: 'ops', fs: 'bottom', to: 'bank', ts: 'bottom', via: [[1157, 600], [317, 600]], label: '問題を外す・戻す', tone: 'ops' },
];

const PIPE_SECTIONS = [
  { y: 30, text: '試合ごと（プレイヤーの端末とプロキシ）' },
  { y: 320, text: '共有バンクを育てる（毎週のジョブ）' },
];

function jobLine(d, name) {
  const job = (d.jobs || []).find(j => j.name === name);
  if (!job) return '';
  const last = job.lastRun;
  const state = !last ? 'まだ' : last.state === 'succeeded' ? '成功' : last.state === 'running' ? '実行中' : '失敗';
  return `前回 ${state}・次回 ${when(job.nextRunAt)}`;
}

function pipeAnchor(node, side) {
  const { nodeW: w, nodeH: h } = PIPE;
  if (side === 'top') return [node.x + w / 2, node.y];
  if (side === 'bottom') return [node.x + w / 2, node.y + h];
  if (side === 'left') return [node.x, node.y + h / 2];
  return [node.x + w, node.y + h / 2];
}

// 縦横だけの折れ線。via が無ければ、出る向きに合わせて 1〜2 回曲げる
function pipePoints(edge, nodes) {
  const a = pipeAnchor(nodes[edge.from], edge.fs);
  const b = pipeAnchor(nodes[edge.to], edge.ts);
  if (edge.via) return [a, ...edge.via, b];
  const horizontal = s => s === 'left' || s === 'right';
  if (a[0] === b[0] || a[1] === b[1]) return [a, b];
  if (horizontal(edge.fs) && horizontal(edge.ts)) {
    const mx = (a[0] + b[0]) / 2;
    return [a, [mx, a[1]], [mx, b[1]], b];
  }
  if (!horizontal(edge.fs) && !horizontal(edge.ts)) {
    const my = (a[1] + b[1]) / 2;
    return [a, [a[0], my], [b[0], my], b];
  }
  return horizontal(edge.fs) ? [a, [b[0], a[1]], b] : [a, [a[0], b[1]], b];
}

function pipeLabelAt(points) {
  let best = [points[0], points[1]];
  let bestLen = -1;
  for (let i = 0; i < points.length - 1; i++) {
    const [p, q] = [points[i], points[i + 1]];
    const len = Math.abs(p[0] - q[0]) + Math.abs(p[1] - q[1]);
    if (len > bestLen) { bestLen = len; best = [p, q]; }
  }
  const [p, q] = best;
  return { x: (p[0] + q[0]) / 2, y: (p[1] + q[1]) / 2, vertical: p[0] === q[0] };
}

function renderPipeline(d) {
  const nodes = Object.fromEntries(PIPE_NODES.map(n => [n.id, n]));
  const { width, height, nodeW, nodeH } = PIPE;
  let svg = `<svg viewBox="0 0 ${width} ${height}" class="pipe" role="img" aria-label="問題生成ラインの図">`
    + '<defs>'
    + ['default', 'claude', 'ops'].map(t => `<marker id="arrow-${t}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">`
      + `<path d="M0,0 L10,5 L0,10 z" class="arrowhead ${t}"/></marker>`).join('')
    + '</defs>';

  for (const s of PIPE_SECTIONS) {
    svg += `<text x="20" y="${s.y}" class="pipe-section">${esc(s.text)}</text>`;
  }
  svg += `<line x1="20" x2="${width - 20}" y1="300" y2="300" class="pipe-divider"/>`;

  // 矢印のことば（箱より手前に描くので、あとでまとめて足す）
  let labels = '';
  for (const edge of PIPE_EDGES) {
    const points = pipePoints(edge, nodes);
    const tone = edge.tone || 'default';
    svg += `<polyline points="${points.map(p => p.join(',')).join(' ')}" class="pipe-edge ${tone}" marker-end="url(#arrow-${tone})"/>`;
    if (edge.label) {
      const at = edge.labelAt ? { x: edge.labelAt[0], y: edge.labelAt[1], vertical: false } : pipeLabelAt(points);
      const w = [...edge.label].reduce((sum, ch) => sum + (ch.charCodeAt(0) < 128 ? 7 : 12), 10);
      const x = at.vertical ? at.x + 6 : at.x - w / 2;
      const y = at.vertical ? at.y - 9 : at.y - 19;
      labels += `<rect x="${x}" y="${y}" width="${w}" height="17" rx="3" class="pipe-label-bg"/>`
        + `<text x="${x + w / 2}" y="${y + 13}" text-anchor="middle" class="pipe-label">${esc(edge.label)}</text>`;
    }
  }

  for (const n of PIPE_NODES) {
    const lines = n.lines(d).filter(Boolean);
    svg += `<g class="pipe-node ${n.kind}${n.tab ? ' link' : ''}"${n.tab ? ` data-goto="${n.tab}" tabindex="0"` : ''}>`
      + `<title>${esc(n.title)}${n.tab ? '（押すと詳しいタブへ）' : ''}</title>`
      + `<rect x="${n.x}" y="${n.y}" width="${nodeW}" height="${nodeH}" rx="8"/>`
      + `<rect x="${n.x}" y="${n.y}" width="5" height="${nodeH}" rx="2" class="stripe"/>`
      + `<text x="${n.x + 14}" y="${n.y + 22}" class="pipe-title">${esc(n.title)}</text>`
      + lines.slice(0, 3).map((line, i) => `<text x="${n.x + 14}" y="${n.y + 42 + i * 16}" class="pipe-line">${esc(line)}</text>`).join('')
      + '</g>';
  }
  $('pipeline').innerHTML = `${svg}${labels}</svg>`;
}

const pipeState = { money: null, players: null, bank: null, jobs: null };

async function loadPipeline({ force = false } = {}) {
  // 共有バンクは重い（約 5MB）ので、まだ持っていないときと「更新」のときだけ読む
  const wantBank = force || !pipeState.bank;
  const [money, players, jobs] = await Promise.all([
    getJson('/api/money'), getJson('/api/players'), getJson('/api/jobs'),
  ]);
  Object.assign(pipeState, { money, players, jobs });
  renderPipeline(pipeState);
  if (wantBank) {
    pipeState.bank = await getJson('/api/bank');
    renderPipeline(pipeState);
  }
}

$('pipeline').addEventListener('click', event => {
  const node = event.target.closest('[data-goto]');
  if (node) selectTab(node.dataset.goto);
});
$('pipeline').addEventListener('keydown', event => {
  const node = event.target.closest('[data-goto]');
  if (node && (event.key === 'Enter' || event.key === ' ')) {
    event.preventDefault();
    selectTab(node.dataset.goto);
  }
});
