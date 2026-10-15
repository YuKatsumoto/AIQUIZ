// AIQUIZ ロゴの形の計算（エディタとフィット用スクリプトで共用）。
//
// ロゴは「要素」を上から順に重ねて作る。
//   op "paint" … 白で塗る
//   op "cut"   … それまでに塗った白を消す（斜め線のまわりの黒いすき間）
// 要素の種類
//   kind "line"   … 中心線（points）と太さ（width）で描く線。曲がり角ごとに丸み（radii）を持てる。
//                   端の形 capStart / capEnd：butt 直角、round 丸、h 水平に切る、v 垂直に切る
//   kind "circle" … 中心（center）、中心線の半径（radius）、太さ（width）の輪
// 座標は icon.jpg と同じ 1024×1024 のピクセル（y は下向き）。
(function (root, factory) {
	const api = factory();
	if (typeof module === "object" && module.exports) module.exports = api;
	else root.LogoGeometry = api;
})(typeof self !== "undefined" ? self : this, function () {
	"use strict";

	const ARC_STEP = Math.PI / 90; // 曲線を 2° ごとの折れ線にする
	const MITER_LIMIT = 4.0;

	const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
	const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
	const mul = (a, s) => [a[0] * s, a[1] * s];
	const dot = (a, b) => a[0] * b[0] + a[1] * b[1];
	const cross = (a, b) => a[0] * b[1] - a[1] * b[0];
	const len = (a) => Math.hypot(a[0], a[1]);
	const norm = (a) => {
		const l = len(a);
		return l > 1e-9 ? [a[0] / l, a[1] / l] : [0, 0];
	};
	const leftOf = (d) => [d[1], -d[0]]; // 進む向きの左（y 下向きの画面で見た左）

	/** 角の丸みを入れた中心線を細かい折れ線にする。 */
	function centerline(el) {
		const pts = el.points || [];
		const n = pts.length;
		if (n < 2) return pts.slice();
		const radii = el.radii || [];
		// 各角が辺から使う長さ t を求め、隣の角と取り合う辺は比例で縮める
		const want = new Array(n).fill(0);
		const turn = new Array(n).fill(0);
		for (let i = 1; i < n - 1; i++) {
			const r = Math.max(0, +radii[i] || 0);
			const d1 = norm(sub(pts[i], pts[i - 1]));
			const d2 = norm(sub(pts[i + 1], pts[i]));
			const th = Math.acos(Math.max(-1, Math.min(1, dot(d1, d2))));
			turn[i] = th;
			if (r > 0 && th > 1e-4 && th < Math.PI - 1e-3) want[i] = r * Math.tan(th / 2);
		}
		const t = want.slice();
		for (let i = 0; i < n - 1; i++) {
			const segLen = len(sub(pts[i + 1], pts[i]));
			const need = t[i] + t[i + 1];
			if (need > segLen && need > 0) {
				const k = segLen / need;
				t[i] *= k;
				t[i + 1] *= k;
			}
		}
		const out = [pts[0].slice()];
		for (let i = 1; i < n - 1; i++) {
			const P = pts[i];
			if (t[i] <= 1e-6) {
				out.push(P.slice());
				continue;
			}
			const d1 = norm(sub(P, pts[i - 1]));
			const d2 = norm(sub(pts[i + 1], P));
			const th = turn[i];
			const r = t[i] / Math.tan(th / 2);
			const T1 = sub(P, mul(d1, t[i]));
			let nrm = leftOf(d1);
			if (dot(nrm, d2) < 0) nrm = mul(nrm, -1);
			const C = add(T1, mul(nrm, r));
			const a1 = Math.atan2(T1[1] - C[1], T1[0] - C[0]);
			const dir = cross(d1, d2) > 0 ? 1 : -1;
			const steps = Math.max(2, Math.ceil(th / ARC_STEP));
			for (let s = 0; s <= steps; s++) {
				const a = a1 + dir * th * (s / steps);
				out.push([C[0] + r * Math.cos(a), C[1] + r * Math.sin(a)]);
			}
		}
		out.push(pts[n - 1].slice());
		// 重なった点を落とす
		const clean = [out[0]];
		for (let i = 1; i < out.length; i++) {
			if (len(sub(out[i], clean[clean.length - 1])) > 1e-4) clean.push(out[i]);
		}
		return clean;
	}

	/** 端の形に合わせて、端の左右の点を決める。 */
	function capPoints(P, d, half, cap) {
		// d は線の外へ向かう向き（始点なら線の逆向き）
		const n = leftOf(d);
		let L = add(P, mul(n, half));
		let R = sub(P, mul(n, half));
		if (cap === "h" && Math.abs(d[1]) > 0.2) {
			L = add(L, mul(d, (P[1] - L[1]) / d[1]));
			R = add(R, mul(d, (P[1] - R[1]) / d[1]));
		} else if (cap === "v" && Math.abs(d[0]) > 0.2) {
			L = add(L, mul(d, (P[0] - L[0]) / d[0]));
			R = add(R, mul(d, (P[0] - R[0]) / d[0]));
		}
		const extra = [];
		if (cap === "round") {
			// L から外側（d の向き）を回って R へ
			const a0 = Math.atan2(n[1], n[0]);
			const steps = Math.ceil(Math.PI / ARC_STEP);
			for (let s = 1; s < steps; s++) {
				const a = a0 + Math.PI * (s / steps);
				extra.push([P[0] + half * Math.cos(a), P[1] + half * Math.sin(a)]);
			}
		}
		return { L, R, extra };
	}

	/** 線の輪郭（閉じた多角形 1 つ）。 */
	function lineOutline(el) {
		const c = centerline(el);
		const half = Math.max(0.01, (+el.width || 0) / 2);
		if (c.length < 2) return [];
		const left = [];
		const right = [];
		const m = c.length;
		for (let i = 0; i < m; i++) {
			if (i === 0 || i === m - 1) continue;
			const dPrev = norm(sub(c[i], c[i - 1]));
			const dNext = norm(sub(c[i + 1], c[i]));
			const nPrev = leftOf(dPrev);
			const nNext = leftOf(dNext);
			const mid = norm(add(nPrev, nNext));
			const cosHalf = dot(mid, nPrev);
			if (cosHalf > 1 / MITER_LIMIT) {
				const k = half / cosHalf;
				left.push(add(c[i], mul(mid, k)));
				right.push(sub(c[i], mul(mid, k)));
			} else {
				// 折り返しに近い鋭い角は面取り
				left.push(add(c[i], mul(nPrev, half)), add(c[i], mul(nNext, half)));
				right.push(sub(c[i], mul(nPrev, half)), sub(c[i], mul(nNext, half)));
			}
		}
		const dStart = norm(sub(c[0], c[1]));
		const dEnd = norm(sub(c[m - 1], c[m - 2]));
		const s = capPoints(c[0], dStart, half, el.capStart || "butt");
		const e = capPoints(c[m - 1], dEnd, half, el.capEnd || "butt");
		// 始点では外向きが線の逆向きなので、s.R が線の左側、s.L が右側になる
		const poly = [];
		poly.push(s.R);
		for (const p of left) poly.push(p);
		poly.push(e.L);
		for (const p of e.extra) poly.push(p);
		poly.push(e.R);
		for (let i = right.length - 1; i >= 0; i--) poly.push(right[i]);
		poly.push(s.L);
		for (const p of s.extra) poly.push(p);
		return [poly];
	}

	function circleOutline(el) {
		const [cx, cy] = el.center;
		const r = +el.radius || 0;
		const half = (+el.width || 0) / 2;
		const steps = 180;
		const outer = [];
		const inner = [];
		for (let s = 0; s < steps; s++) {
			const a = (s / steps) * Math.PI * 2;
			outer.push([cx + (r + half) * Math.cos(a), cy + (r + half) * Math.sin(a)]);
		}
		const ri = Math.max(0, r - half);
		if (ri > 0) {
			for (let s = steps; s > 0; s--) {
				const a = (s / steps) * Math.PI * 2;
				inner.push([cx + ri * Math.cos(a), cy + ri * Math.sin(a)]);
			}
		}
		return ri > 0 ? [outer, inner] : [outer];
	}

	/** 要素の輪郭（多角形の配列、塗りは nonzero）。 */
	function contours(el) {
		if (el.kind === "circle") return circleOutline(el);
		return lineOutline(el);
	}

	function visibleElements(model) {
		return (model.elements || []).filter((el) => el.visible !== false);
	}

	/** 描いたときに白が出る範囲（塗る要素の外接矩形）。 */
	function bounds(model) {
		let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
		for (const el of visibleElements(model)) {
			if (el.op === "cut") continue;
			for (const poly of contours(el)) {
				for (const [x, y] of poly) {
					if (x < x0) x0 = x;
					if (y < y0) y0 = y;
					if (x > x1) x1 = x;
					if (y > y1) y1 = y;
				}
			}
		}
		return { x0, y0, x1, y1 };
	}

	function tracePath(ctx, polys, scale, ox, oy) {
		ctx.beginPath();
		for (const poly of polys) {
			poly.forEach(([x, y], i) => {
				const px = (x - ox) * scale;
				const py = (y - oy) * scale;
				if (i === 0) ctx.moveTo(px, py);
				else ctx.lineTo(px, py);
			});
			ctx.closePath();
		}
	}

	/**
	 * ロゴを透明なキャンバスに描く。cut は destination-out で消すので、
	 * 必ずロゴ専用の（透明な）キャンバスに描いてから背景と合成すること。
	 */
	function drawLogo(ctx, model, opts) {
		const o = opts || {};
		const scale = o.scale || 1;
		const ox = o.originX || 0;
		const oy = o.originY || 0;
		ctx.save();
		ctx.fillStyle = o.color || model.color || "#ffffff";
		for (const el of visibleElements(model)) {
			ctx.globalCompositeOperation = el.op === "cut" ? "destination-out" : "source-over";
			tracePath(ctx, contours(el), scale, ox, oy);
			ctx.fill("nonzero");
		}
		ctx.restore();
	}

	function pathData(polys) {
		return polys
			.map((poly) => "M" + poly.map(([x, y]) => x.toFixed(2) + " " + y.toFixed(2)).join("L") + "Z")
			.join("");
	}

	/** 消す要素をマスクで表した SVG（Inkscape や Figma で開ける）。 */
	function toSVG(model, opts) {
		const o = opts || {};
		const [W, H] = model.canvas || [1024, 1024];
		const color = model.color || "#ffffff";
		let body = "";
		let defs = "";
		let maskId = 0;
		for (const el of visibleElements(model)) {
			const d = pathData(contours(el));
			if (el.op === "cut") {
				maskId += 1;
				defs += `<mask id="cut${maskId}" maskUnits="userSpaceOnUse" x="0" y="0" width="${W}" height="${H}">` +
					`<rect width="${W}" height="${H}" fill="#fff"/><path d="${d}" fill="#000" fill-rule="nonzero"/></mask>`;
				body = `<g mask="url(#cut${maskId})">${body}</g>`;
			} else {
				body += `<path d="${d}" fill="${color}" fill-rule="nonzero"/>`;
			}
		}
		const bg = o.background ? `<rect width="${W}" height="${H}" fill="${o.background}"/>` : "";
		return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">` +
			`<defs>${defs}</defs>${bg}${body}</svg>\n`;
	}

	return { centerline, contours, bounds, drawLogo, toSVG, visibleElements };
});
