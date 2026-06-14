# -*- coding: utf-8 -*-
"""Phase4: BP_AiQuizPawn を Python 側で compile + save し、結果を検証。

MCP の compile_blueprint は裸の FKismetEditorUtilities::CompileBlueprint を
呼んでクラッシュするため使わない。ここでは BlueprintEditorLibrary 経由で
compile し、status を確認して接続ミス由来のコンパイルエラーを検知する。
"""
import unreal
import json

p = "/Game/AiQuiz/Pawn/BP_AiQuizPawn"
bp = unreal.EditorAssetLibrary.load_asset(p)

out = {"ok": False}

unreal.BlueprintEditorLibrary.compile_blueprint(bp)

# status: BlueprintStatus enum（BS_UP_TO_DATE が正常 / BS_ERROR が失敗）
try:
    st = bp.get_editor_property("status")
    out["status"] = str(st)
except Exception as e:
    out["status_err"] = str(e)

gc = bp.generated_class()
out["gen_class"] = (str(gc.get_name()) if gc else None)

# 変数が4つ揃っているか CDO 経由で確認
if gc:
    cdo = unreal.get_default_object(gc)
    present = []
    for n in ("AxisX", "VelY", "PlayerX", "PlayerY"):
        try:
            cdo.get_editor_property(n)
            present.append(n)
        except Exception:
            pass
    out["vars"] = present

saved = unreal.EditorAssetLibrary.save_asset(p)
out["saved"] = bool(saved)
out["ok"] = True
print("RESULT " + json.dumps(out))
