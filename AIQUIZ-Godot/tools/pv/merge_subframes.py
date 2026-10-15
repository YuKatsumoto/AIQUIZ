"""PV 撮影（tests/pv_capture/pv_v3_runtime.gd を sub=N で撮ったもの）の、各フレームの最後の N/2 回（pv_NNNN_0, _1, ...）を
平均して 1 枚にする。シャッター 180° 相当の動きのブレになる。

    python tools/pv/merge_subframes.py artifacts/pv_capture/v3_sub8 artifacts/pv_capture/v3_frames
出力は pv_NNNN.jpg（品質 97）。After Effects に連番で読み込む。
"""
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image


def merge(src: Path, dst: Path, n: int) -> str:
    parts = sorted(src.glob(f"pv_{n:04d}_*.jpg"))
    if not parts:
        return f"missing pv_{n:04d}_*"
    acc = None
    for p in parts:
        a = np.asarray(Image.open(p), dtype=np.float32)
        acc = a if acc is None else acc + a
    out = Image.fromarray(np.clip(acc / len(parts) + 0.5, 0, 255).astype(np.uint8))
    out.save(dst / f"pv_{n:04d}.jpg", quality=97, subsampling=0)
    return ""


def main() -> None:
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    frames = sorted({int(p.name[3:7]) for p in src.glob("pv_*_*.jpg")})
    with ThreadPoolExecutor(max_workers=8) as pool:
        errors = [e for e in pool.map(lambda n: merge(src, dst, n), frames) if e]
    print(f"merged {len(frames) - len(errors)} frames -> {dst}")
    for e in errors[:10]:
        print(e)


if __name__ == "__main__":
    main()
