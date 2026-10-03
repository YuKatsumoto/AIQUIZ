// Save review frames of the LED segments to source/ae/previews/frames (ExtendScript ES3).
// Edit SHOTS to choose comps and seconds; contact_sheet.py assembles them.
var OUT = "C:/AIQUIZ/AIQUIZ-Godot/assets/aiquiz_menu_stage/source/ae/previews/frames/";
var SHOTS = $SHOTS$;
var dir = new Folder(OUT);
if (!dir.exists) dir.create();
var old = dir.getFiles("*.png");
for (var o = 0; o < old.length; o++) old[o].remove();
function find(name) {
  for (var i = 1; i <= app.project.numItems; i++) if (app.project.item(i).name === name) return app.project.item(i);
  return null;
}
var done = [];
for (var s = 0; s < SHOTS.length; s++) {
  var comp = find(SHOTS[s][0]);
  if (!comp) continue;
  var t = SHOTS[s][1];
  var file = new File(OUT + SHOTS[s][0] + "_" + Math.round(t * 1000) + ".png");
  comp.saveFrameToPng(t, file);
  done.push(file.name);
}
return done;
