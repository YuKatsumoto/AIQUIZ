// 02_appeal.html の各スライドを、PowerPoint に移すための部品（箱・画像・文字・線・三角・表）の一覧にする。
// 座標はスライド左上からの px。結果は base64 の JSON を <pre id="__extract"> に書く（Edge の --dump-dom で読む）。
(function () {
  "use strict";

  function color(text) {
    if (!text) return null;
    const m = text.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(",").map((s) => parseFloat(s));
    const a = p.length > 3 ? p[3] : 1;
    if (a <= 0.001) return null;
    return { r: Math.round(p[0]), g: Math.round(p[1]), b: Math.round(p[2]), a: a };
  }

  function px(v) { const n = parseFloat(v); return isNaN(n) ? 0 : n; }

  function rel(rect, base) {
    return { x: rect.left - base.left, y: rect.top - base.top, w: rect.width, h: rect.height };
  }

  function radii(cs, w, h) {
    const lim = Math.min(w, h) / 2;
    return [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius]
      .map((v) => Math.min(px(v), lim));
  }

  function shadow(cs) {
    const s = cs.boxShadow;
    if (!s || s === "none") return null;
    // "rgba(11, 22, 48, 0.1) 0px 6px 18px 0px" / "... inset"
    const parts = s.split(/,(?![^(]*\))/);
    let outer = null, inset = null;
    for (const part of parts) {
      const c = color(part);
      const nums = part.replace(/rgba?\([^)]*\)/, "").trim().split(/\s+/).filter((t) => /px$/.test(t)).map(px);
      const item = { color: c, x: nums[0] || 0, y: nums[1] || 0, blur: nums[2] || 0, spread: nums[3] || 0 };
      if (/inset/.test(part)) inset = item; else outer = item;
    }
    return { outer: outer, inset: inset };
  }

  function gradient(cs) {
    const bg = cs.backgroundImage;
    if (!bg || bg === "none") return null;
    if (/repeating-linear-gradient/.test(bg)) return { kind: "stripes", colors: (bg.match(/rgba?\([^)]*\)/g) || []).map(color) };
    const m = bg.match(/linear-gradient\((.*)\)$/);
    if (!m) return null;
    const angle = (m[1].match(/^(-?[\d.]+)deg/) || [0, 180])[1];
    const stops = [];
    const re = /(rgba?\([^)]*\))\s*([\d.]+)%/g;
    let s;
    while ((s = re.exec(m[1]))) stops.push({ color: color(s[1]) || { r: 0, g: 0, b: 0, a: 0 }, pos: parseFloat(s[2]) / 100 });
    if (!stops.length) {
      const cols = (m[1].match(/rgba?\([^)]*\)/g) || []);
      cols.forEach((c, i) => stops.push({ color: color(c) || { r: 0, g: 0, b: 0, a: 0 }, pos: i / Math.max(1, cols.length - 1) }));
    }
    return { kind: "linear", angle: parseFloat(angle), stops: stops };
  }

  function border(cs, side) {
    const w = px(cs["border" + side + "Width"]);
    const st = cs["border" + side + "Style"];
    const c = color(cs["border" + side + "Color"]);
    if (w <= 0 || st === "none" || !c) return null;
    return { w: w, color: c, style: st };
  }

  function boxItem(el, cs, r) {
    const fill = color(cs.backgroundColor);
    const grad = gradient(cs);
    const sides = ["Top", "Right", "Bottom", "Left"].map((s) => border(cs, s));
    const sh = shadow(cs);
    const uniform = sides.every((b) => b && sides[0] && b.w === sides[0].w && b.style === sides[0].style);
    if (!fill && !grad && !sides.some(Boolean) && !(sh && (sh.outer || sh.inset))) return null;
    return {
      t: "box", x: r.x, y: r.y, w: r.w, h: r.h, fill: fill, grad: grad, radius: radii(cs, r.w, r.h),
      border: uniform ? sides[0] : null,
      sides: uniform ? null : { top: sides[0], right: sides[1], bottom: sides[2], left: sides[3] },
      shadow: sh && sh.outer, inset: sh && sh.inset, cls: el.className && el.className.baseVal === undefined ? String(el.className) : "",
    };
  }

  function contentBox(cs, r) {
    const l = px(cs.paddingLeft) + px(cs.borderLeftWidth);
    const t = px(cs.paddingTop) + px(cs.borderTopWidth);
    const rr = px(cs.paddingRight) + px(cs.borderRightWidth);
    const b = px(cs.paddingBottom) + px(cs.borderBottomWidth);
    return { x: r.x + l, y: r.y + t, w: r.w - l - rr, h: r.h - t - b };
  }

  function isInline(node) {
    if (node.nodeType === 3) return true;
    if (node.nodeType !== 1) return false;
    if (node.tagName === "BR") return true;
    const d = getComputedStyle(node).display;
    return d === "inline" || d === "contents";
  }

  function runStyle(el) {
    const cs = getComputedStyle(el);
    return {
      size: px(cs.fontSize), weight: parseInt(cs.fontWeight, 10) || 400, color: color(cs.color),
      ls: cs.letterSpacing === "normal" ? 0 : px(cs.letterSpacing),
    };
  }

  // 要素の中の「行の中身」（文字と inline 要素）を runs にする。block の子は除く。
  function collectRuns(el, runs, nodes) {
    for (const node of el.childNodes) {
      if (node.nodeType === 3) {
        const text = node.nodeValue.replace(/[\t\n\r ]+/g, " ");
        if (text.length) { runs.push(Object.assign({ s: text }, runStyle(el))); nodes.push(node); }
      } else if (node.nodeType === 1 && isInline(node)) {
        if (node.tagName === "BR") { runs.push(Object.assign({ s: "\n" }, runStyle(el))); nodes.push(node); }
        else {
          // inline 要素の左右の余白（margin・padding）は、PowerPoint では前の字の字間で表す
          const start = runs.length;
          collectRuns(node, runs, nodes);
          const ncs = getComputedStyle(node);
          const ml = px(ncs.marginLeft) + px(ncs.paddingLeft), mr = px(ncs.marginRight) + px(ncs.paddingRight);
          if (runs.length > start) {
            if (ml) runs[start].ml = (runs[start].ml || 0) + ml;
            if (mr) runs[runs.length - 1].mr = (runs[runs.length - 1].mr || 0) + mr;
          }
        }
      }
    }
  }

  function tidyRuns(runs) {
    // 行頭・行末・改行のまわりの空白を落とす（HTML の空白のつぶし方に合わせる）
    const out = [];
    for (const r of runs) {
      if (out.length && out[out.length - 1].s.endsWith(" ") && r.s.startsWith(" ")) r.s = r.s.replace(/^ +/, "");
      out.push(r);
    }
    let atStart = true;
    for (const r of out) {
      if (atStart) r.s = r.s.replace(/^ +/, "");
      if (r.s.length) atStart = r.s.endsWith("\n");
    }
    for (let i = 0; i < out.length; i++) {
      if (out[i].s === "\n" && i > 0) out[i - 1].s = out[i - 1].s.replace(/ +$/, "");
    }
    if (out.length) out[out.length - 1].s = out[out.length - 1].s.replace(/ +$/, "");
    return out.filter((r) => r.s.length);
  }

  function textItem(el, cs, base) {
    const runs = [], nodes = [];
    collectRuns(el, runs, nodes);
    const clean = tidyRuns(runs);
    if (!clean.some((r) => r.s.trim().length)) return null;
    const range = document.createRange();
    range.setStartBefore(nodes[0]);
    range.setEndAfter(nodes[nodes.length - 1]);
    const rects = Array.from(range.getClientRects()).filter((q) => q.width > 0 && q.height > 0);
    if (!rects.length) return null;
    const box = contentBox(cs, rel(el.getBoundingClientRect(), base));
    const top = Math.min(...rects.map((q) => q.top)) - base.top;
    const bottom = Math.max(...rects.map((q) => q.bottom)) - base.top;
    const left = Math.min(...rects.map((q) => q.left)) - base.left;
    const right = Math.max(...rects.map((q) => q.right)) - base.left;
    const fs = px(cs.fontSize);
    const lh = cs.lineHeight === "normal" ? null : px(cs.lineHeight);
    // 行の数（同じ高さの行をまとめる）
    const lines = [];
    for (const q of rects) { if (!lines.some((y) => Math.abs(y - q.top) < fs * 0.5)) lines.push(q.top); }
    return {
      t: "text", box: box, ink: { x: left, y: top, w: right - left, h: bottom - top }, lines: lines.length,
      align: cs.textAlign, vertical: /vertical/.test(cs.writingMode), nowrap: cs.whiteSpace === "nowrap",
      size: fs, lh: lh, runs: clean, tag: el.tagName, cls: String(el.className || ""),
    };
  }

  function imageItem(img, cs, base) {
    const r = rel(img.getBoundingClientRect(), base);
    const frame = contentBox(cs, r);
    let clip = null;
    for (let a = img.parentElement; a && !a.classList.contains("slide"); a = a.parentElement) {
      const acs = getComputedStyle(a);
      if (acs.overflow === "hidden") {
        const ar = rel(a.getBoundingClientRect(), base);
        clip = { x: ar.x, y: ar.y, w: ar.w, h: ar.h, radius: radii(acs, ar.w, ar.h) };
        break;
      }
    }
    const pos = cs.objectPosition.split(" ").map((v) => (/%$/.test(v) ? parseFloat(v) / 100 : 0.5));
    return {
      t: "img", src: decodeURIComponent(new URL(img.currentSrc || img.src).pathname).replace(/^\//, ""),
      frame: frame, nw: img.naturalWidth, nh: img.naturalHeight, fit: cs.objectFit, pos: pos, clip: clip,
      radius: radii(cs, r.w, r.h),
    };
  }

  function svgItems(svg, base) {
    const out = [];
    const sr = svg.getBoundingClientRect();
    const vb = svg.viewBox.baseVal;
    const sx = vb && vb.width ? sr.width / vb.width : 1;
    const sy = vb && vb.height ? sr.height / vb.height : 1;
    for (const path of svg.querySelectorAll("path")) {
      if (path.closest("defs") || path.closest("marker")) continue;
      const cs = getComputedStyle(path);
      const d = path.getAttribute("d");
      const tokens = d.match(/[MHVL][^MHVL]*/g) || [];
      let x = 0, y = 0;
      const pts = [];
      for (const tk of tokens) {
        const n = tk.slice(1).trim().split(/[\s,]+/).map(parseFloat);
        if (tk[0] === "M" || tk[0] === "L") { x = n[0]; y = n[1]; }
        else if (tk[0] === "H") x = n[0];
        else if (tk[0] === "V") y = n[0];
        pts.push([x, y]);
      }
      const marker = (path.getAttribute("marker-end") || cs.markerEnd || "");
      const dash = cs.strokeDasharray && cs.strokeDasharray !== "none";
      for (let i = 1; i < pts.length; i++) {
        out.push({
          t: "line",
          x1: sr.left - base.left + pts[i - 1][0] * sx, y1: sr.top - base.top + pts[i - 1][1] * sy,
          x2: sr.left - base.left + pts[i][0] * sx, y2: sr.top - base.top + pts[i][1] * sy,
          color: color(cs.stroke), width: px(cs.strokeWidth) * sx, dash: dash, arrow: i === pts.length - 1 && /url/.test(marker),
        });
      }
    }
    return out;
  }

  function tableItem(table, base) {
    const tr = rel(table.getBoundingClientRect(), base);
    const rows = [];
    for (const row of table.rows) {
      const rr = rel(row.getBoundingClientRect(), base);
      const cells = [];
      for (const cell of row.cells) {
        const cs = getComputedStyle(cell);
        const cr = rel(cell.getBoundingClientRect(), base);
        const runs = [], nodes = [];
        collectRuns(cell, runs, nodes);
        cells.push({
          x: cr.x, w: cr.w, fill: color(cs.backgroundColor), runs: tidyRuns(runs), size: px(cs.fontSize),
          lh: cs.lineHeight === "normal" ? null : px(cs.lineHeight), align: cs.textAlign,
          pad: [px(cs.paddingTop), px(cs.paddingRight), px(cs.paddingBottom), px(cs.paddingLeft)],
          bottom: border(cs, "Bottom"), radius: radii(cs, cr.w, cr.h),
        });
      }
      rows.push({ y: rr.y, h: rr.h, cells: cells });
    }
    return { t: "table", x: tr.x, y: tr.y, w: tr.w, h: tr.h, rows: rows };
  }

  // ::before / ::after（このデッキで使っている形だけ：箇条書きの四角、下向き・右向きの三角）
  function pseudoItems(el, base) {
    const out = [];
    for (const which of ["::before", "::after"]) {
      const ps = getComputedStyle(el, which);
      if (!ps || ps.content === "none" || ps.content === "normal") continue;
      const r = rel(el.getBoundingClientRect(), base);
      const cs = getComputedStyle(el);
      const w = px(ps.width), h = px(ps.height);
      const bl = px(ps.borderLeftWidth), br = px(ps.borderRightWidth), bt = px(ps.borderTopWidth), bb = px(ps.borderBottomWidth);
      if (ps.position === "absolute") {
        const x = r.x + px(cs.borderLeftWidth) + px(ps.left);
        const y = r.y + px(cs.borderTopWidth) + px(ps.top);
        const b = boxItem(el, ps, { x: x, y: y, w: w + bl + br, h: h + bt + bb });
        if (b) { b.cls = "pseudo"; out.push(b); }
      } else if ((w === 0 || h === 0 || ps.content === '""') && !color(ps.backgroundColor) && (bt || bl)) {
        // 三角（border の作り方）。親の flex で中央に置かれている。中身の高さ（stretch）は三角に含めない
        const tw = bl + br, th = bt + bb;
        const cb = contentBox(cs, r);
        let x = cb.x + (cb.w - tw) / 2;
        let y = cb.y + (cb.h - th) / 2;
        if (cs.alignItems !== "center") y = cb.y + px(ps.marginTop);
        const down = color(ps.borderTopColor) && bt > 0 && !color(ps.borderLeftColor);
        out.push({ t: "tri", x: x, y: y, w: tw, h: th, dir: down ? "down" : "right", color: color(down ? ps.borderTopColor : ps.borderLeftColor) });
      }
    }
    return out;
  }

  function walk(el, base, items) {
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden" || parseFloat(cs.opacity) === 0) return;
    const tag = el.tagName;
    if (tag === "SCRIPT" || tag === "STYLE" || tag === "FOOTER" && false) return;
    const r = rel(el.getBoundingClientRect(), base);
    if (tag === "svg" || tag === "SVG") { items.push(...svgItems(el, base)); return; }
    if (tag === "TABLE") { items.push(tableItem(el, base)); return; }
    if (tag === "IMG") {
      const b = boxItem(el, cs, r);
      if (b) items.push(b);
      items.push(imageItem(el, cs, base));
      return;
    }
    if (!el.classList.contains("slide")) {
      const b = boxItem(el, cs, r);
      if (b) items.push(b);
    }
    items.push(...pseudoItems(el, base));
    if (!isInline(el)) {
      const t = textItem(el, cs, base);
      if (t) items.push(t);
    }
    for (const child of el.children) {
      if (isInline(child) && child.tagName !== "IMG") continue; // 行の中身として textItem が拾った
      walk(child, base, items);
    }
  }

  function run() {
    const slides = [];
    for (const slide of document.querySelectorAll("section.slide")) {
      const base = slide.getBoundingClientRect();
      const cs = getComputedStyle(slide);
      const items = [];
      walk(slide, base, items);
      slides.push({ bg: color(cs.backgroundColor), cls: slide.className, items: items });
    }
    const json = JSON.stringify({ slides: slides });
    const pre = document.createElement("pre");
    pre.id = "__extract";
    pre.textContent = btoa(unescape(encodeURIComponent(json)));
    document.body.appendChild(pre);
  }

  window.addEventListener("load", () => document.fonts.ready.then(() => setTimeout(run, 300)));
})();
