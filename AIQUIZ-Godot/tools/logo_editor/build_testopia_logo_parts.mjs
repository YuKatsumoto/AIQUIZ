// TESTOPIA のロゴ（assets/branding/logo/testopia_logo.json と .svg）を、AIQUIZ のロゴと同じ作りで組み立てる。
//
//   node tools/logo_editor/build_testopia_logo.mjs
//   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/logo_editor/render_logo_png.gd
//
// 文字は AIQUIZ のロゴ（aiquiz_logo.json）の部品だけで組む：縦棒 35.5・横棒 31・曲線と斜め 33.5（I は 36）を
// WEIGHT 倍に太くし、外形は変えずに内側へ太らせる。A は AIQUIZ の A（脚の先を水平に切る）、O は Q の輪、
// S と P の丸みは U と同じ「直線と丸い角」。文字の間は AIQUIZ の平均（24）。
// 要素の id の「_」より前が部品の名前（t1・e・s・t2・o・p・i・a）。タイトルの演出は t1 と e を
// 1 つの扉のブロック（TitleLogoIntro.DOOR_KEY）として運ぶ。
// 飾り（2026-10-17〜）：I は「!」（縦棒と点のあいだに切れ目）で、点は P2 の青。O の穴は紺の奥に、P1 の頭（オレンジの四角）が見える。
// 色は要素の color（無ければ白）。flat の要素（O の穴の中、「!」の点のつや）には、メニューの文字の紺の厚みを付けない。
// 名前の表記はいつも TESTOPIA（「!」はロゴの絵の中だけ）。
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
const LG = require("./logo_geometry.js");
const OUT_JSON = path.join(ROOT, "assets/branding/logo/testopia_logo.json");
const OUT_SVG = path.join(ROOT, "assets/branding/logo/testopia_logo.svg");

const WEIGHT = 1.18;
const CAP = 166;
const GAP = 24;
// 1024 の画用紙に収めるための縮め（形の比率は変わらない）
const FIT = 0.8;
const TOP = 421.75;

const P1 = "#F28C33";      // P1 の色（player_health_hud.gd の PLAYER_COLORS）
const P2 = "#33A6E6";      // P2 の色
const SV = 35.5 * WEIGHT;  // 縦棒
const SH = 31 * WEIGHT;    // 横棒
const SC = 33.5 * WEIGHT;  // 曲線・斜め・輪
const IW = 36 * WEIGHT;    // I
const hw = SC / 2;
const AE = hw * Math.hypot(71, 166) / 166;  // A の脚を水平に切ったときの横のはみ出し

const line = (id, name, points, width, opts = {}) => ({
	id, name, kind: "line", op: "paint", points, radii: opts.radii || points.map(() => 0), width,
	capStart: opts.capStart || "butt", capEnd: opts.capEnd || "butt", visible: true,
});

// 文字ごと：幅と、左上を原点にした要素（y 下向き）
const T = (key, label) => ({
	width: 130,
	elements: [
		line(`${key}_bar`, `${label} 横棒`, [[0, SH / 2], [130, SH / 2]], SH),
		line(`${key}_stem`, `${label} 縦棒`, [[65, 0], [65, CAP]], SV),
	],
});
const OI = 88.25 - SC;     // O の穴の半径
const BANG_STEM = 112;     // 「!」の縦棒の下の端と、点の上の端（切れ目は 20）
const BANG_DOT = 132;
// O の穴の P1 の頭：オレンジの立方体を、少し上から左寄りに見た形（前の面・上の面・左の面）。
// 前の面は穴の右と下の縁より外まで広げる（はみ出しは白い輪に隠れ、右と下に紺のすき間ができない）。
// 左上の角だけが穴の中に見え、その奥（左上）へ上の面と左の面が HEAD_D だけのびる。光は上から（上の面が一番明るく、左の面は陰）
const HEAD_L = -OI * 0.38;  // 前の面の左の辺と上の辺（穴の中心から）
const HEAD_R = OI * 1.08;   // 前の面の右の辺と下の辺（穴の縁より外）
const HEAD_D = OI * 0.17;   // 奥行き（左上へ）
const HEAD_FRONT = P1;
const HEAD_TOP_FACE = "#FFC489";
const HEAD_LEFT_FACE = "#C9661B";
const NAVY = "#1B2A4A";    // 文字の厚みと同じ紺（TitleLogoIntro.DEPTH_COLOR）
const square = (id, name, center, side, color) => ({
	...line(id, name, [[center[0] - side / 2, center[1]], [center[0] + side / 2, center[1]]], side), color, flat: true,
});
// 立方体の面：上の面は 45° の斜めの線を水平に切った平行四辺形、左の面は垂直に切った平行四辺形（太さ = 辺 ÷ √2）
const headCube = (c) => {
	const x0 = c[0] + HEAD_L, y0 = c[1] + HEAD_L, x1 = c[0] + HEAD_R, y1 = c[1] + HEAD_R, d = HEAD_D;
	const w = (x1 - x0) / Math.SQRT2, h = (y1 - y0) / Math.SQRT2;
	const flatColor = (el, color) => ({ ...el, color, flat: true });
	return [
		flatColor(line("o_head_left", "P1 の頭の左の面", [[x0, (y0 + y1) / 2], [x0 - d, (y0 + y1) / 2 - d]], h,
			{ capStart: "v", capEnd: "v" }), HEAD_LEFT_FACE),
		flatColor(line("o_head_top", "P1 の頭の上の面", [[(x0 + x1) / 2, y0], [(x0 + x1) / 2 - d, y0 - d]], w,
			{ capStart: "h", capEnd: "h" }), HEAD_TOP_FACE),
		flatColor(line("o_head", "P1 の頭の前の面", [[x0, (y0 + y1) / 2], [x1, (y0 + y1) / 2]], y1 - y0), HEAD_FRONT),
	];
};
const disc = (id, name, center, r, color) => ({
	id, name, kind: "circle", op: "paint", center, radius: r / 2, width: r, color, flat: true, visible: true,
});
const sr = (83 - hw) / 2;
const pr = (116 - 2 * hw) / 2;
const LETTERS = [
	T("t1", "T（1つ目）"),
	{
		width: 115,
		elements: [
			line("e_stem", "E 縦棒", [[SV / 2, 0], [SV / 2, CAP]], SV),
			line("e_top", "E 上の横棒", [[0, SH / 2], [115, SH / 2]], SH),
			line("e_mid", "E まん中の横棒", [[0, 83], [105, 83]], SH),
			line("e_bottom", "E 下の横棒", [[0, CAP - SH / 2], [115, CAP - SH / 2]], SH),
		],
	},
	{
		width: 125,
		elements: [
			line("s", "S", [[125, hw], [hw, hw], [hw, 83], [125 - hw, 83], [125 - hw, CAP - hw], [0, CAP - hw]], SC,
				{ radii: [0, sr, sr, sr, sr, 0] }),
		],
	},
	T("t2", "T（2つ目）"),
	{
		width: 176.5,
		elements: [
			// 穴の中：紺の奥（輪の内側より少し大きい円）に、右下へ寄せた P1 の頭（四角いブロック）と、その上の面の明るい帯。
			// どれも輪の下に描くので、穴からはみ出したところは白い輪に隠れる
			disc("o_hole", "O の穴の奥（紺）", [88.25, 83], OI + 2, NAVY),
			...headCube([88.25, 83]),
			{ id: "o", name: "O の輪", kind: "circle", op: "paint", center: [88.25, 83], radius: 88.25 - hw, width: SC, visible: true },
		],
	},
	{
		width: 126.75,
		elements: [
			line("p_stem", "P 縦棒", [[SV / 2, 0], [SV / 2, CAP]], SV),
			line("p_bowl", "P のふくらみ", [[SV / 2, hw], [126.75 - hw, hw], [126.75 - hw, 116 - hw], [SV / 2, 116 - hw]], SC,
				{ radii: [0, pr, pr, 0] }),
		],
	},
	{
		width: IW,
		elements: [
			line("i_stem", "I（!）の縦棒", [[IW / 2, 0], [IW / 2, BANG_STEM]], IW),
			{ ...line("i_dot", "I（!）の点（P2）", [[IW / 2, BANG_DOT], [IW / 2, CAP]], IW), color: P2 },
			{ ...line("i_shine", "I（!）の点のつや", [[0, BANG_DOT + 3], [IW, BANG_DOT + 3]], 6), color: "#FFFFFF59", flat: true },
		],
	},
	{
		width: 143.75 + 2 * AE,
		elements: [
			line("a_left", "A 左の脚", [[AE, CAP], [AE + 71, 0]], SC, { capStart: "h", capEnd: "h" }),
			line("a_right", "A 右の脚", [[AE + 71.5, 0], [AE + 143.75, CAP]], SC, { capStart: "h", capEnd: "h" }),
			line("a_bar", "A の横棒", [[AE + 19.5, 114.25], [AE + 129.5, 114.25]], SH),
		],
	},
];

const total = LETTERS.reduce((s, l) => s + l.width, 0) + GAP * (LETTERS.length - 1);
const ox = (1024 - total * FIT) / 2;
const r2 = (v) => Math.round(v * 100) / 100;
const place = (x0) => (p) => [r2(ox + (x0 + p[0]) * FIT), r2(TOP + p[1] * FIT)];

const elements = [];
let x = 0;
for (const letter of LETTERS) {
	const at = place(x);
	for (const el of letter.elements) {
		if (el.kind === "circle") {
			elements.push({ ...el, center: at(el.center), radius: r2(el.radius * FIT), width: r2(el.width * FIT) });
		} else {
			elements.push({ ...el, points: el.points.map(at), radii: el.radii.map((r) => r2(r * FIT)), width: r2(el.width * FIT) });
		}
	}
	x += letter.width + GAP;
}

const model = { version: 1, canvas: [1024, 1024], background: "#0e0e0e", color: "#ffffff", weight: WEIGHT, elements };
fs.writeFileSync(OUT_JSON, JSON.stringify(model, null, "\t") + "\n");
fs.writeFileSync(OUT_SVG, LG.toSVG(model));
const b = LG.bounds(model);
console.log(`wrote ${path.relative(ROOT, OUT_JSON)} / .svg  elements=${elements.length}  bounds=${JSON.stringify(b)}`);
