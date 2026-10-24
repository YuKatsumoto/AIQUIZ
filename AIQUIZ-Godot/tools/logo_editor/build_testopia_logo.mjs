// TESTOPIA のロゴ（assets/branding/logo/testopia_logo.json と .svg）を、書体 Stereofunk の字形で組み立てる（2026-10-19〜）。
//
//   python tools/logo_editor/extract_font_glyphs.py     （書体を替えたときだけ。字形を testopia_font_glyphs.json に書き出す）
//   node tools/logo_editor/build_testopia_logo.mjs
//   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/logo_editor/render_logo_png.gd
//
// 文字は 1 字ずつ 1 つの多角形（kind "poly"）。穴（O・A・P）は外周へ幅 0 のすき間でつないで 1 本の輪郭にする。
// 要素の id の「_」より前が部品の名前（t1・e・s・t2・o・p・i・a）。タイトルの演出は t1 と e を
// 1 つの扉のブロック（TitleLogoIntro.DOOR_KEY）として運ぶ。
// 飾り：O の穴に P1 の頭（オレンジの立方体）、A の穴に P2 の頭（青の立方体）。どちらも紺の奥の中に、
// 文字の紺の厚み（TitleLogoIntro.DEPTH_OFFSET）と同じ向き・長さで奥（右上）へ伸びる立方体（前の面と上の面。
// 右の面は穴の右の縁の外になるので見えない）。2026-10-19 の途中までは左上へ伸びる形（前・上・左の面）だった。
// 前の面は穴の右と下の縁まで届かせ（右と下に紺のすき間を作らない）、
// 頭の面は穴の形で切り抜く（穴の外へは出ない）。頭と紺の奥は文字より先に並べ、文字の白がその上に重なる。
// I は書体のままの I（2026-10-19 まではここを「!」にしていた）。
// 色は要素の color（無ければ白）。flat の要素（穴の中）には、メニューの文字の紺の厚みを付けない。
// それまでの部品で組んだロゴ（AIQUIZ と同じ部品）は build_testopia_logo_parts.mjs と
// assets/branding/logo/history/testopia_logo_20261019_parts.* に残してある。
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
const LG = require("./logo_geometry.js");
const GLYPHS = path.join(HERE, "testopia_font_glyphs.json");
const OUT_JSON = path.join(ROOT, "assets/branding/logo/testopia_logo.json");
const OUT_SVG = path.join(ROOT, "assets/branding/logo/testopia_logo.svg");

// 字の高さ（T の高さ、1024 の画用紙のピクセル）と上の端。部品で組んでいたころと同じ
const CAP = 166 * 0.8;
const TOP = 421.75;
// 字間（em）。見本の A 案と同じ
const TRACKING = 0.05;
// 字の組ごとの字間の詰め（em。負で狭める。部品の名前の「前-後」）。2026-10-19：T（1つ目）と E、S と T（2つ目）を少し詰めた
const KERNING = { "t1-e": -0.03, "s-t2": -0.03 };

const NAVY = "#1B2A4A";  // 文字の厚みと同じ紺（TitleLogoIntro.DEPTH_COLOR）
// 頭の色（player_health_hud.gd の PLAYER_COLORS）。光は上から：上の面が明るい
const HEADS = {
	O: { key: "o", label: "P1", front: "#F28C33", top: "#FFC489" },
	A: { key: "a", label: "P2", front: "#33A6E6", top: "#9DD8F7" },
};
// 頭の前の面の左と上の辺は、穴の中心から 0.38r（r は穴の半径。部品のロゴの O と同じ割合）
const HEAD_L = 0.38;
// 頭の奥行き：文字の紺の厚みと同じ（TitleLogoIntro.DEPTH_OFFSET。ロゴの高さ LOGO_HEIGHT の論理ピクセルに対して、y 下向き）
const DEPTH_OFFSET = [3.0, -3.8];
const LOGO_HEIGHT = 56;
// 紺の奥と頭は、穴より少し外まで広げる（文字の白の下に隠れ、縁に細いすき間が出ない）
const HOLE_GROW = 1.2;

const LETTERS = [
	["T", "t1", "T（1つ目）"], ["E", "e", "E"], ["S", "s", "S"], ["T", "t2", "T（2つ目）"],
	["O", "o", "O"], ["P", "p", "P"], ["I", "i", "I"], ["A", "a", "A"],
];

const r2 = (v) => Math.round(v * 100) / 100;
const area = (poly) => {
	let a = 0;
	for (let i = 0; i < poly.length; i++) {
		const [x1, y1] = poly[i];
		const [x2, y2] = poly[(i + 1) % poly.length];
		a += x1 * y2 - x2 * y1;
	}
	return a / 2;
};
const inside = ([px, py], poly) => {
	let hit = false;
	for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
		const [xi, yi] = poly[i];
		const [xj, yj] = poly[j];
		if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) hit = !hit;
	}
	return hit;
};
const bbox = (poly) => {
	const xs = poly.map((p) => p[0]);
	const ys = poly.map((p) => p[1]);
	return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
};

// ほかの辺のごく近く（SNAP 単位以内）にある頂点を、その辺の上へ吸い付け、辺にも同じ点を足す。
// Stereofunk の A は、穴と下の切れ込みのあいだが幅 2 単位（ロゴで 0.4 px）のすき間でつながっているので、ここで閉じる
const SNAP = 3;
function snapToEdges(contour) {
	const pts = contour.map((p) => [...p]);
	for (let i = 0; i < pts.length; i++) {
		const p = pts[i];
		for (let j = 0; j < pts.length; j++) {
			const k = (j + 1) % pts.length;
			if (j === i || k === i || j === (i - 1 + pts.length) % pts.length) continue;
			const a = pts[j];
			const b = pts[k];
			const dx = b[0] - a[0];
			const dy = b[1] - a[1];
			const len2 = dx * dx + dy * dy;
			if (len2 < 1e-9) continue;
			const t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2;
			if (t <= 0.01 || t >= 0.99) continue;
			const q = [r2(a[0] + t * dx), r2(a[1] + t * dy)];
			if (Math.hypot(p[0] - q[0], p[1] - q[1]) > SNAP || Math.hypot(p[0] - q[0], p[1] - q[1]) < 1e-6) continue;
			pts[i] = q;
			pts.splice(k === 0 ? pts.length : k, 0, [...q]);
			if (k !== 0 && k <= i) i++;
			break;
		}
	}
	return pts;
}

// 輪郭が同じ点を 2 度通るとき（穴が外周と 1 点で接している A など）は、そこで別々の輪に分ける
function splitLoops(contour) {
	const loops = [];
	const stack = [];
	const seen = new Map();
	for (const p of contour) {
		const k = `${p[0]},${p[1]}`;
		if (seen.has(k)) {
			const at = seen.get(k);
			const loop = stack.splice(at);
			for (const q of loop) seen.delete(`${q[0]},${q[1]}`);
			if (loop.length >= 3) loops.push(loop);
		}
		seen.set(k, stack.length);
		stack.push(p);
	}
	if (stack.length >= 3) loops.push(stack);
	return loops;
}

// 穴を外周へ幅 0 のすき間でつなぐ（TitleLogoGeometry._keyhole と同じ：一番近い頂点どうし）
function keyhole(outer, hole) {
	const h = (area(outer) > 0) === (area(hole) > 0) ? [...hole].reverse() : hole;
	let best = Infinity;
	let bi = 0;
	let bj = 0;
	outer.forEach((o, i) => h.forEach((q, j) => {
		const d = (o[0] - q[0]) ** 2 + (o[1] - q[1]) ** 2;
		if (d < best) { best = d; bi = i; bj = j; }
	}));
	const merged = outer.slice(0, bi + 1);
	for (let k = 0; k <= h.length; k++) merged.push(h[(bj + k) % h.length]);
	return merged.concat(outer.slice(bi));
}

// 凸の多角形 clip で subject を切り抜く（Sutherland–Hodgman）
function clipConvex(subject, clip) {
	const ccw = area(clip) > 0;
	const side = (a, b, p) => {
		const c = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]);
		return ccw ? c >= 0 : c <= 0;
	};
	const cross = (a, b, p, q) => {
		const d = (a[0] - b[0]) * (p[1] - q[1]) - (a[1] - b[1]) * (p[0] - q[0]);
		const t = ((a[0] - p[0]) * (p[1] - q[1]) - (a[1] - p[1]) * (p[0] - q[0])) / d;
		return [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])];
	};
	let out = subject;
	for (let i = 0; i < clip.length && out.length; i++) {
		const a = clip[i];
		const b = clip[(i + 1) % clip.length];
		const input = out;
		out = [];
		for (let j = 0; j < input.length; j++) {
			const p = input[j];
			const q = input[(j + 1) % input.length];
			const pin = side(a, b, p);
			const qin = side(a, b, q);
			if (pin) out.push(p);
			if (pin !== qin) out.push(cross(p, q, a, b));
		}
	}
	return out;
}

// 穴をまわりへ少し広げる（中心から外へ押し出す。O・A の穴はどちらも中心から見渡せる形）
function grow(poly, d) {
	const b = bbox(poly);
	const cx = (b.x0 + b.x1) / 2;
	const cy = (b.y0 + b.y1) / 2;
	return poly.map(([x, y]) => {
		const len = Math.hypot(x - cx, y - cy) || 1;
		return [x + ((x - cx) / len) * d, y + ((y - cy) / len) * d];
	});
}

const font = JSON.parse(fs.readFileSync(GLYPHS, "utf8"));
const s = CAP / font.capHeight;
// ロゴの高さ（全部の字の上の端から下の端まで、画用紙のピクセル）。メニューではこれが LOGO_HEIGHT 論理ピクセルになる
const allY = LETTERS.flatMap(([ch]) => font.glyphs[ch].contours.flat().map((p) => p[1]));
const logoHeight = (Math.max(...allY) - Math.min(...allY)) * s;
const depth = DEPTH_OFFSET.map((v) => (v * logoHeight) / LOGO_HEIGHT);
const track = TRACKING * font.unitsPerEm;
const advances = LETTERS.map(([ch]) => font.glyphs[ch].advance);
// n 番目の字の後ろの字間（フォントの単位）：TRACKING と、次の字との組の KERNING
const gapAfter = (n) => track + (KERNING[`${LETTERS[n][1]}-${LETTERS[n + 1]?.[1]}`] || 0) * font.unitsPerEm;
const total = (advances.reduce((a, b) => a + b, 0) + LETTERS.slice(0, -1).reduce((a, _, n) => a + gapAfter(n), 0)) * s;
const BASE = TOP + CAP;
const elements = [];
const poly = (id, name, points, extra = {}) => ({
	id, name, kind: "poly", op: "paint", points: points.map(([x, y]) => [r2(x), r2(y)]), visible: true, ...extra,
});
let pen = (1024 - total) / 2;
LETTERS.forEach(([ch, key, label], n) => {
	const g = font.glyphs[ch];
	const at = ([x, y]) => [pen + x * s, BASE - y * s];
	const loops = g.contours.map(snapToEdges).flatMap(splitLoops).map((loop) => loop.map(at));
	loops.sort((a, b) => Math.abs(area(b)) - Math.abs(area(a)));
	const outers = [];
	const holes = [];
	for (const loop of loops) {
		// 穴の判定は輪の頂点の平均で（A の穴の頂点は外周に接しているので、頂点そのものでは決まらない）
		const mid = [loop.reduce((a, p) => a + p[0], 0) / loop.length, loop.reduce((a, p) => a + p[1], 0) / loop.length];
		const parent = outers.find((o) => inside(mid, o) && (area(o) > 0) !== (area(loop) > 0));
		if (parent) holes.push({ loop, parent });
		else outers.push(loop);
	}
	const head = HEADS[ch];
	if (head && holes.length) {
		const hole = holes[0].loop;
		const b = bbox(hole);
		const r = Math.min(b.x1 - b.x0, b.y1 - b.y0) / 2;
		const cx = (b.x0 + b.x1) / 2;
		const cy = (b.y0 + b.y1) / 2;
		const fx = cx - r * HEAD_L;
		const fy = cy - r * HEAD_L;
		const [dx, dy] = depth;
		const ex = b.x1 + 4;
		const ey = b.y1 + 4;
		const wide = grow(hole, HOLE_GROW);
		const face = (id, name, shape, color) => poly(id, name, clipConvex(wide, shape), { color, flat: true });
		elements.push(poly(`${key}_hole`, `${label} の穴の奥（紺）`, wide, { color: NAVY, flat: true }));
		// 上の面：前の面の上の辺を、文字の厚みと同じ向き（右上）へずらした平行四辺形
		elements.push(face(`${key}_head_top`, `${head.label} の頭の上の面`, [[fx, fy], [ex, fy], [ex + dx, fy + dy], [fx + dx, fy + dy]], head.top));
		elements.push(face(`${key}_head`, `${head.label} の頭の前の面`, [[fx, fy], [ex, fy], [ex, ey], [fx, ey]], head.front));
	}
	outers.forEach((outer, k) => {
		let shape = outer;
		for (const h of holes) if (h.parent === outer) shape = keyhole(shape, h.loop);
		const id = outers.length > 1 ? `${key}_body${k + 1}` : `${key}_body`;
		elements.push(poly(id, label, shape));
	});
	pen += (advances[n] + gapAfter(n)) * s;
});

const model = { version: 1, canvas: [1024, 1024], background: "#0e0e0e", color: "#ffffff", font: font.family, elements };
fs.writeFileSync(OUT_JSON, JSON.stringify(model, null, "\t") + "\n");
fs.writeFileSync(OUT_SVG, LG.toSVG(model));
const b = LG.bounds(model);
console.log(`wrote ${path.relative(ROOT, OUT_JSON)} / .svg  elements=${elements.length}  bounds=${JSON.stringify(b)}`);
