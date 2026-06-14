# -*- coding: utf-8 -*-
"""Phase 7: BP_AiQuizGameMode を本番フロー用に設定。
- bAutoStartInPIE = False（メニューから StartRoundFromMenu で開始）
- HUDClass = AAiQuizHUD（C++ コンストラクタの既定を BP が上書きしていないか確認/再設定）
"""
import unreal
import json

GM_PATH = "/Game/AiQuiz/Core/BP_AiQuizGameMode"
out = {}

eal = unreal.EditorAssetLibrary
bp = eal.load_asset(GM_PATH)
assert bp is not None, "load BP_AiQuizGameMode failed"

# Blueprint の CDO を取得して既定値を設定
gen_class = bp.generated_class() if hasattr(bp, "generated_class") else unreal.load_object(None, GM_PATH + "_C")
cdo = unreal.get_default_object(gen_class) if gen_class else None
assert cdo is not None, "no CDO"

try:
    cdo.set_editor_property("bAutoStartInPIE", False)
    out["bAutoStartInPIE"] = cdo.get_editor_property("bAutoStartInPIE")
except Exception as e:
    out["autostart_err"] = str(e)

try:
    hud_cls = unreal.AiQuizHUD
    cdo.set_editor_property("HUDClass", hud_cls)
    cur = cdo.get_editor_property("HUDClass")
    out["HUDClass"] = cur.get_name() if cur else None
except Exception as e:
    out["hud_err"] = str(e)

# DefaultPawnClass は Phase 4 で AAiQuizPawn 系に配線済み（念のため記録）
try:
    dp = cdo.get_editor_property("DefaultPawnClass")
    out["DefaultPawnClass"] = dp.get_name() if dp else None
except Exception as e:
    out["pawn_err"] = str(e)

eal.save_loaded_asset(bp)
out["ok"] = True
print("RESULT " + json.dumps(out, ensure_ascii=False))
