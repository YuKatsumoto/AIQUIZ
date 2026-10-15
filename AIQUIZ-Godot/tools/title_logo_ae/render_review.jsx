// Save review frames of TitleLogo_Intro (ExtendScript ES3, run via ae_run.mjs).
// $TIMES$ is replaced by render_review.py with the seconds to save.
var OUT = "C:/AIQUIZ/AIQUIZ-Godot/artifacts/title_logo_ae/frames/";
var TIMES = $TIMES$;
var dir = new Folder(OUT);
if (!dir.exists) dir.create();
var old = dir.getFiles("*.png");
for (var o = 0; o < old.length; o++) old[o].remove();
var comp = null;
for (var i = 1; i <= app.project.numItems; i++) if (app.project.item(i).name === "TitleLogo_Intro") comp = app.project.item(i);
if (!comp) throw new Error("TitleLogo_Intro not found");
var done = [];
for (var s = 0; s < TIMES.length; s++) {
  var f = new File(OUT + "t" + ("0000" + Math.round(TIMES[s] * 1000)).slice(-5) + ".png");
  comp.saveFrameToPng(TIMES[s], f);
  done.push(f.name);
}
return done;
