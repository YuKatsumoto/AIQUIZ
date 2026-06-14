# -*- coding: utf-8 -*-
"""Phase4: PIE 中の Pawn / PlayerController を検査し、移動グラフの稼働を確認。

PIE world は editor world とは別インスタンスなので get_game_world で取得し、
GameplayStatics で Pawn / PlayerController を引く。Pawn が spawn され Possess
され、位置が初期 (-800,0,0) 付近（= SetActorLocation が毎 Tick 走っている）
ならグラフは構造的に正常稼働。
"""
import unreal
import json

out = {}
les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
out["in_pie"] = les.is_in_play_in_editor()

ues = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
gw = ues.get_game_world() if hasattr(ues, "get_game_world") else None
out["game_world"] = (gw.get_path_name() if gw else None)

if gw:
    pawns = unreal.GameplayStatics.get_all_actors_of_class(gw, unreal.Pawn)
    out["pawn_count"] = len(pawns)
    if pawns:
        p = pawns[0]
        loc = p.get_actor_location()
        out["pawn_class"] = p.get_class().get_name()
        out["pawn_loc"] = [round(loc.x, 1), round(loc.y, 1), round(loc.z, 1)]

    pc = unreal.GameplayStatics.get_player_controller(gw, 0)
    out["has_pc"] = pc is not None
    if pc:
        cp = pc.get_controlled_pawn()
        out["controlled_pawn"] = (cp.get_class().get_name() if cp else None)

print("RESULT " + json.dumps(out))
