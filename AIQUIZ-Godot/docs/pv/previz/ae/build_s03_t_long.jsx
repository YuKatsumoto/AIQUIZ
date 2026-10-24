// PV S03（タイトル、10/21 夜（v1.3）から 12 拍 = 338 フレーム。10/20 夜は 20 拍、10/21 昼は 16 拍）を、build_s03_t.jsx の設定を変えて組む入口。
// 設定は通しの計画 docs/pv/previz/v6/master_plan.json の "s03"（tools/pv/pv_master.py の S03_LONG）から読む：
//   背景 = v3 を 1522 フレームまで撮り直した artifacts/pv_capture/v3_frames の PV 957〜、
//   ロゴ = ゲームの登場演出を S23 と同じ 1.6 倍で 562 フレーム書き出した artifacts/pv_capture/logo_s03_x16（頭から frames だけ使う）、
//   保存 = TESTOPIA_PV_S03_long.aep（コンポ PV_S03_T）。保存したら閉じる（AE に連番をつかませない）。
//   python tools/pv/pv_master.py s03      （= node tools/title_logo_ae/ae_run.mjs docs/pv/previz/ae/build_s03_t_long.jsx）
var ROOT = "G:/AIQUIZ-Main/AIQUIZ-Godot/";
function readText(p) { var f = new File(p); f.encoding = "UTF-8"; if (!f.open("r")) throw new Error("cannot open " + p); var s = f.read(); f.close(); return s; }
var P = JSON.parse(readText(ROOT + "docs/pv/previz/v6/master_plan.json"));
if (!P.s03) throw new Error("master_plan.json に s03 が無い（pv_master.py plan を先に流す）");
$.global.S03_T_CFG = { frames: P.s03.frames, logo_dir: P.s03.logo_dir, bg_first: P.s03.bg_first, bg_start_frame: P.s03.bg_start_frame,
                       save_as: P.s03.aep, close_after: true };
return (new Function(readText(ROOT + "docs/pv/previz/ae/build_s03_t.jsx")))();
