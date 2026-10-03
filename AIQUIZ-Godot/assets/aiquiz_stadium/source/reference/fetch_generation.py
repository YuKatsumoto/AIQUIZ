"""Higgsfield の生成結果を取り込み、generation_record.json に記録する。

原寸 PNG は artifacts/aiquiz_stadium/reference_r1/<ID>/（git 管理外）、資料用の高品質 JPEG は
assets/aiquiz_stadium/source/reference/<ID>/ に置く。記録は saw_operator v2 の形式に合わせ、
見積（estimate）と実費（actual_charge）を分けて書く。実費は残高の差から分かったときだけ書く。

    python fetch_generation.py <entry.json>   # entry: id, name, job_id, url, model, params, refs, estimate, status, reason
    python fetch_generation.py --set <ID/name> status=accepted reason="..." [mirrored=true]
"""
from __future__ import annotations

import hashlib
import json
import sys
import urllib.request
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RAW = ROOT / "artifacts" / "aiquiz_stadium" / "reference_r1"
RECORD = HERE.parent / "generation_record.json"


def load() -> dict:
    if RECORD.exists():
        return json.loads(RECORD.read_text(encoding="utf-8"))
    return {
        "version": 1,
        "purpose": "AIQUIZ STADIUM 原本 v1 から Blender 精密制作用の参照画像をそろえる（参照画像と寸法表の段階）",
        "project": {"higgsfield_project": "264e3cac-30e6-47b8-a4fb-3a7e0be1b2c7", "model_default": "nano_banana_pro"},
        "master": {"job_id": "b34835af-abae-42bc-babe-dcac08d266ec", "file": "master/aiquiz_stadium_master_v1.png"},
        "uploads": {},
        "entries": [],
    }


def save(data: dict) -> None:
    RECORD.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def fetch(entry: dict) -> dict:
    rid, name = entry["id"], entry["name"]
    raw_dir = RAW / rid
    raw_dir.mkdir(parents=True, exist_ok=True)
    png = raw_dir / f"{name}.png"
    if not png.exists():
        urllib.request.urlretrieve(entry["url"], png)
    img = Image.open(png)
    if entry.get("mirrored"):
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    jpg_dir = HERE / rid
    jpg_dir.mkdir(parents=True, exist_ok=True)
    jpg = jpg_dir / f"{name}.jpg"
    img.convert("RGB").save(jpg, quality=92, optimize=True)
    entry.update({
        "file_raw": str(png.relative_to(ROOT)).replace("\\", "/"),
        "file": str(jpg.relative_to(HERE.parent)).replace("\\", "/"),
        "sha256_raw": hashlib.sha256(png.read_bytes()).hexdigest(),
        "pixels": list(img.size),
    })
    return entry


def upsert(data: dict, entry: dict) -> None:
    key = (entry["id"], entry["name"])
    for i, e in enumerate(data["entries"]):
        if (e["id"], e["name"]) == key:
            merged = {**e, **entry}
            data["entries"][i] = merged
            return
    data["entries"].append(entry)


def main(argv: list[str]) -> None:
    data = load()
    if argv[0] == "--set":
        rid, name = argv[1].split("/", 1)
        patch = {}
        for kv in argv[2:]:
            k, v = kv.split("=", 1)
            patch[k] = {"true": True, "false": False}.get(v, v)
        upsert(data, {"id": rid, "name": name, **patch})
        if patch.get("mirrored") is True:
            e = next(e for e in data["entries"] if (e["id"], e["name"]) == (rid, name))
            fetch(e)
    else:
        entry = json.loads(Path(argv[0]).read_text(encoding="utf-8"))
        entries = entry if isinstance(entry, list) else [entry]
        for e in entries:
            upsert(data, fetch(e))
            print(e["id"], e["name"], e["pixels"])
    save(data)


if __name__ == "__main__":
    main(sys.argv[1:])
