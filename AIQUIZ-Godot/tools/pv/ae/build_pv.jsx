// AIQUIZ 3D PV (ゲームクリエイター甲子園2026) — After Effects 2026 assembly, ExtendScript ES3.
// Run through the local Higgsfield AE bridge (ae_run.mjs runs this file as a function body):
//   node assets/aiquiz_menu_stage/source/ae/ae_run.mjs tools/pv/ae/build_pv.jsx artifacts/pv/ae_build.json
//
// Reads tools/pv/edit.json (the same cut list tools/pv/rough_cut.py renders) and builds, in the
// project folder "AIQUIZ_PV" (rebuilt each run; nothing else in the project is touched):
//   PV_Master  1920x1080, 60 fps: the clips from artifacts/pv/mezz/ cut and timed per the list,
//              game sound on each clip, telops as live text layers (NotoSansJP-Bold), cards with
//              the logo, a marker per shot, and the music (edit.json "bgm") under everything
//   PV_Thumb   one 1920x1080 frame for the contest thumbnail (edit.json "thumb")
// then saves tools/pv/ae/AIQUIZ_PV.aep. Text, timing and music can be edited by hand afterwards;
// rerunning rebuilds the comps from edit.json (hand edits in them are lost).

var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/";
var EDIT = ROOT + "tools/pv/edit.json";
var MEZZ = ROOT + "artifacts/pv/mezz/";
var SAVE = ROOT + "tools/pv/ae/AIQUIZ_PV.aep";
var FOLDER = "AIQUIZ_PV";
var W = 1920, H = 1080, FPS = 60;
var FONT = "NotoSansJP-Bold";
var INK = [0.063, 0.125, 0.227];
var WHITE = [1, 1, 1];
var YELLOW = [1.0, 0.878, 0.4];

function readText(path) {
  var f = new File(path);
  f.encoding = "UTF-8";
  if (!f.open("r")) throw new Error("cannot read " + path);
  var t = f.read();
  f.close();
  return t;
}

function hexColor(hex) {
  var h = hex.replace("#", "");
  return [parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255];
}

function ownFolder() {
  for (var i = 1; i <= app.project.numItems; i++) {
    var it = app.project.item(i);
    if (it instanceof FolderItem && it.name === FOLDER) return it;
  }
  return app.project.items.addFolder(FOLDER);
}

function clearFolder(f) {
  var items = [];
  for (var i = 1; i <= f.numItems; i++) items.push(f.item(i));
  for (var c = 0; c < items.length; c++) if (items[c] instanceof CompItem) { try { items[c].remove(); } catch (e) {} }
  for (var o = 0; o < items.length; o++) { try { if (!(items[o] instanceof CompItem)) items[o].remove(); } catch (e2) {} }
}

var imported = {};
function footage(f, path) {
  if (imported[path]) return imported[path];
  var file = new File(path);
  if (!file.exists) throw new Error("missing " + path);
  var item = app.project.importFile(new ImportOptions(file));
  item.parentFolder = f;
  imported[path] = item;
  return item;
}

function tr(layer, name) {
  var map = { "Position": "ADBE Position", "Scale": "ADBE Scale", "Opacity": "ADBE Opacity", "Anchor Point": "ADBE Anchor Point" };
  return layer.property("ADBE Transform Group").property(map[name]);
}

function ease(prop) {
  for (var k = 1; k <= prop.numKeys; k++) {
    var dims = prop.value instanceof Array ? prop.value.length : 1;
    var e = [];
    for (var d = 0; d < dims; d++) e.push(new KeyframeEase(0, 66));
    try { prop.setTemporalEaseAtKey(k, e, e); } catch (err) {}
  }
}

function textLayer(comp, name, text, size, color, strokeWidth, pos, start, dur) {
  var l = comp.layers.addText(text);
  l.name = name;
  var src = l.property("ADBE Text Properties").property("ADBE Text Document");
  var doc = src.value;
  doc.resetCharStyle();
  doc.resetParagraphStyle();
  doc.font = FONT;
  doc.fontSize = size;
  doc.fillColor = color;
  doc.applyFill = true;
  doc.applyStroke = strokeWidth > 0;
  if (strokeWidth > 0) {
    doc.strokeColor = INK;
    doc.strokeWidth = strokeWidth;
    doc.strokeOverFill = false;
  }
  doc.justification = ParagraphJustification.CENTER_JUSTIFY;
  doc.tracking = 20;
  src.setValue(doc);
  var r = l.sourceRectAtTime(start, false);
  tr(l, "Anchor Point").setValue([r.left + r.width / 2, r.top + r.height / 2]);
  tr(l, "Position").setValue(pos);
  l.inPoint = start;
  l.outPoint = start + dur;
  if (dur < 0.6) return l; // a still (the thumbnail): no animation
  // pop in, settle, fade out
  var sc = tr(l, "Scale"), op = tr(l, "Opacity");
  sc.setValueAtTime(start, [82, 82]);
  sc.setValueAtTime(start + 0.18, [104, 104]);
  sc.setValueAtTime(start + 0.30, [100, 100]);
  op.setValueAtTime(start, 0);
  op.setValueAtTime(start + 0.15, 100);
  op.setValueAtTime(start + dur - 0.2, 100);
  op.setValueAtTime(start + dur, 0);
  ease(sc);
  ease(op);
  return l;
}

function addTelops(comp, shot, start, index) {
  var dur = shot.dur;
  var style = shot.style || "lower";
  if (shot.telop) {
    var y = style === "center" ? H / 2 : H - 190;
    textLayer(comp, "TL_" + index + "_main", shot.telop, style === "center" ? 96 : 80, WHITE, 9, [W / 2, y], start, dur);
  }
  if (shot.sub) {
    var y2 = style === "center" ? H / 2 + 105 : H - 95;
    textLayer(comp, "TL_" + index + "_sub", shot.sub, 44, YELLOW, 6, [W / 2, y2], start, dur);
  }
  if (shot.note) {
    var n = textLayer(comp, "TL_" + index + "_note", shot.note, 26, WHITE, 3, [W / 2, H - 42], start, dur);
    var nr = n.sourceRectAtTime(start, false);
    tr(n, "Position").setValue([W - 36 - nr.width / 2, H - 30 - nr.height / 2]);
  }
}

function addShot(comp, f, shot, start, index) {
  var dur = shot.dur;
  if (shot.card) {
    var solid = comp.layers.addSolid(hexColor(shot.bg || "#0b1630"), "CARD_" + index, W, H, 1, dur);
    solid.startTime = start;
    if (solid.source) solid.source.parentFolder = f;
    if (shot.image) {
      var img = footage(f, ROOT + shot.image);
      var il = comp.layers.add(img, dur);
      il.name = "CARD_" + index + "_image";
      il.startTime = start;
      var s = 100 * (shot.image_scale || 0.5);
      tr(il, "Scale").setValue([s, s]);
      tr(il, "Position").setValue([W / 2, H / 2 - (shot.image_lift || 60)]);
      var op = tr(il, "Opacity");
      op.setValueAtTime(start, 0);
      op.setValueAtTime(start + 0.25, 100);
      ease(op);
    }
    return;
  }
  var item = footage(f, MEZZ + shot.clip + ".mov");
  var layer = comp.layers.add(item);
  layer.name = "SH_" + index + "_" + shot.clip;
  var speed = shot.speed || 1.0;
  layer.stretch = 100 / speed;
  layer.startTime = start - shot["in"] / speed;
  layer.inPoint = start;
  layer.outPoint = start + dur;
  if (layer.hasAudio) {
    var levels = layer.property("ADBE Audio Group").property("ADBE Audio Levels");
    var g = shot.sfx_db !== undefined ? shot.sfx_db : -4;
    levels.setValue([g, g]);
  }
  if (shot.dim) {
    // a near-black solid at dim opacity: the same darkening as rough_cut.py's channel multiply
    var shade = comp.layers.addSolid([0.02, 0.035, 0.08], "SH_" + index + "_dim", W, H, 1, dur);
    shade.startTime = start;
    if (shade.source) shade.source.parentFolder = f;
    tr(shade, "Opacity").setValue(100 * shot.dim);
  }
  if (shot.image) {
    var over = comp.layers.add(footage(f, ROOT + shot.image));
    over.name = "SH_" + index + "_image";
    over.startTime = start;
    over.inPoint = start;
    over.outPoint = start + dur;
    var sc = 100 * (shot.image_scale || 0.5);
    tr(over, "Scale").setValue([sc, sc]);
    tr(over, "Position").setValue([W / 2, H / 2 - (shot.image_lift || 60)]);
    var o2 = tr(over, "Opacity");
    o2.setValueAtTime(start, 0);
    o2.setValueAtTime(start + 0.3, 100);
    ease(o2);
  }
}

// ---------------------------------------------------------------- build

var edit = eval("(" + readText(EDIT) + ")");
if (app.project.file === null && app.project.numItems === 0 && new File(SAVE).exists) {
  app.open(new File(SAVE));
}
var f = ownFolder();
clearFolder(f);
var total = 0;
for (var i = 0; i < edit.shots.length; i++) total += edit.shots[i].dur;
var comp = app.project.items.addComp("PV_Master", W, H, 1, total, FPS);
comp.parentFolder = f;
comp.bgColor = [0, 0, 0];
var t = 0;
// clips first (bottom), telops on top
for (var s1 = 0; s1 < edit.shots.length; s1++) {
  addShot(comp, f, edit.shots[s1], t, s1);
  var m = new MarkerValue(edit.shots[s1].clip || edit.shots[s1].card || "");
  m.comment = (edit.shots[s1].telop || "") + (edit.shots[s1].sub ? " / " + edit.shots[s1].sub : "");
  comp.markerProperty.setValueAtTime(t, m);
  t += edit.shots[s1].dur;
}
t = 0;
for (var s2 = 0; s2 < edit.shots.length; s2++) {
  addTelops(comp, edit.shots[s2], t, s2);
  t += edit.shots[s2].dur;
}
if (edit.bgm) {
  var music = footage(f, ROOT + edit.bgm);
  var ml = comp.layers.add(music);
  ml.name = "BGM";
  ml.moveToEnd();
  ml.outPoint = Math.min(ml.outPoint, total);
  // to swap the music: select this layer's source in the Project panel, File > Replace Footage
  var lv = ml.property("ADBE Audio Group").property("ADBE Audio Levels");
  var db = edit.bgm_db || -6;
  lv.setValueAtTime(0, [db, db]);
  lv.setValueAtTime(total - 1.5, [db, db]);
  lv.setValueAtTime(total, [-48, -48]);
}
// thumbnail: one still frame of a clip with the logo and a line
var thumb = app.project.items.addComp("PV_Thumb", W, H, 1, 1 / FPS, FPS);
thumb.parentFolder = f;
if (edit.thumb) {
  var titem = footage(f, MEZZ + edit.thumb.clip + ".mov");
  var tl = thumb.layers.add(titem);
  tl.startTime = -edit.thumb.time;
  if (edit.thumb.image) {
    // a soft dark band from the top edge so the logo reads over the busy stadium
    var band = thumb.layers.addSolid(INK, "THUMB_band", W, H, 1, 1 / FPS);
    if (band.source) band.source.parentFolder = f;
    var bandBottom = edit.thumb.band_bottom || 330;
    var mask = band.property("ADBE Mask Parade").addProperty("ADBE Mask Atom");
    var shape = new Shape();
    shape.vertices = [[-200, -200], [W + 200, -200], [W + 200, bandBottom], [-200, bandBottom]];
    shape.closed = true;
    mask.property("ADBE Mask Shape").setValue(shape);
    mask.property("ADBE Mask Feather").setValue([0, 220]);
    tr(band, "Opacity").setValue(edit.thumb.band_opacity || 85);
    var li = thumb.layers.add(footage(f, ROOT + edit.thumb.image));
    var ls = 100 * (edit.thumb.image_scale || 0.45);
    tr(li, "Scale").setValue([ls, ls]);
    tr(li, "Position").setValue(edit.thumb.image_pos || [W / 2, 190]);
  }
  if (edit.thumb.telop) textLayer(thumb, "THUMB_text", edit.thumb.telop, 88, WHITE, 10, [W / 2, H - 150], 0, 1 / FPS);
}
app.project.save(new File(SAVE));
return { saved: SAVE, seconds: total, layers: comp.numLayers, shots: edit.shots.length };
