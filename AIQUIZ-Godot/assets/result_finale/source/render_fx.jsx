// Render the white-on-alpha FX comps to PNG sequences for Godot (ExtendScript ES3).
// Godot tints them per player: res://assets/result_finale/fx/<name>/<name>_NN.png
var ROOT = "C:/AIQUIZ/AIQUIZ-Godot/assets/result_finale/fx/";
var jobs = [["FX_Burst", "burst"], ["FX_LockRing", "lock_ring"]];
var done = {};
for (var j = 0; j < jobs.length; j++) {
  var comp = null;
  for (var i = 1; i <= app.project.numItems; i++) if (app.project.item(i).name === jobs[j][0]) comp = app.project.item(i);
  if (!comp) continue;
  var dir = new Folder(ROOT + jobs[j][1]);
  if (!dir.exists) dir.create();
  var old = dir.getFiles("*.png");
  for (var o = 0; o < old.length; o++) old[o].remove();
  var frames = Math.round(comp.duration * comp.frameRate);
  for (var f = 0; f < frames; f++) {
    var file = new File(dir.fsName + "/" + jobs[j][1] + "_" + (f < 10 ? "0" : "") + f + ".png");
    comp.saveFrameToPng(f / comp.frameRate, file);
  }
  done[jobs[j][1]] = { frames: frames, fps: comp.frameRate, size: [comp.width, comp.height] };
}
return done;
