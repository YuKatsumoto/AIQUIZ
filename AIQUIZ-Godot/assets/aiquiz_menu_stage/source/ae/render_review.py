"""AE のコンポジションの指定した秒をフレームに書き出し、コンタクトシートにまとめる。

  python render_review.py previews/wipe_sheet.jpg 5 WIPE_Strokes=0.1,0.2,0.45 LED_Sting=1.2

After Effects を開いた状態で実行する（render_frames.jsx を ae_run.mjs 経由で動かす）。
"""
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
FRAMES = HERE / "previews" / "frames"


def main() -> None:
    out, cols = Path(sys.argv[1]), int(sys.argv[2])
    shots = []
    for arg in sys.argv[3:]:
        comp, times = arg.split("=")
        shots += [[comp, float(t)] for t in times.split(",")]
    script = (HERE / "render_frames.jsx").read_text(encoding="utf-8").replace("$SHOTS$", json.dumps(shots))
    temp = HERE / "previews" / "_render_frames.jsx"
    temp.write_text(script, encoding="utf-8")
    subprocess.run(["node", str(HERE / "ae_run.mjs"), str(temp)], check=True, capture_output=True, timeout=600)
    temp.unlink()
    for _ in range(40):
        if len(list(FRAMES.glob("*.png"))) >= len(shots):
            break
        time.sleep(0.5)
    time.sleep(1.0)
    subprocess.run([sys.executable, str(HERE / "contact_sheet.py"), str(cols), str(out if out.is_absolute() else HERE / out)], check=True)


if __name__ == "__main__":
    main()
