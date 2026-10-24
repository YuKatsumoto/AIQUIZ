// 絵コンテ（docs/pv/storyboard.html）の SHOTS 配列を JSON で出す。PV の全体の組み立て（tools/pv/pv_master.py）が
// カットの順・長さ（拍）・テロップ・仮置きの画像をここから読む。
//   node tools/pv/storyboard_shots.mjs [docs/pv/storyboard.html]
// テロップの文字は <span class="y">…</span>（要のことば）を […] に替え、ほかのタグを外す（pv_telop.jsxinc の書き方）。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const html = fs.readFileSync(process.argv[2] || path.join(root, 'docs/pv/storyboard.html'), 'utf8');
const bpm = Number((html.match(/const BPM = (\d+(?:\.\d+)?)/) || [])[1]);
const start = html.indexOf('const SHOTS = [');
const end = html.indexOf('];', html.indexOf('{id:"S23"', start));
if (!bpm || start < 0 || end < 0) throw new Error('SHOTS / BPM not found in the storyboard');
const box = (l, t, w, h) => ({ l, t, w, h });
const SHOTS = new Function('box', html.slice(start, end + 2).replace('const SHOTS =', 'return'))(box);

const marked = (s) => (s ?? '').replace(/<span class="y">([^<]*)<\/span>/g, '[$1]').replace(/<[^>]+>/g, '');
const out = SHOTS.map((s) => ({
  id: s.id,
  beats: s.beats,
  title: s.title,
  img: s.img ? 'docs/pv/' + s.img : null,
  seq: (s.seq || []).map((q) => ({ img: 'docs/pv/' + q.img, from: q.from, to: q.to, label: q.label })),
  telops: s.ov.filter((o) => o.t === 'telop').map((o) => ({
    text: marked(o.text), sub: o.sub ? marked(o.sub) : null, pos: o.pos || 'bl',
    from: o.from ?? 0, to: o.to ?? 1, subFrom: o.subFrom ?? null, baked: !!o.baked,
  })),
  status: s.status,
}));
process.stdout.write(JSON.stringify({ bpm, shots: out }, null, 1));
