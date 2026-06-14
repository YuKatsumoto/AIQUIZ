#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Phase4: BP_AiQuizPawn movement graph builder.

Drives the UnrealMCP TCP bridge to assemble the Tick-based analytic movement
graph that mirrors Godot game_state.gd _update_playing (1P branch):

  axis_x  : A/Left -> +1, D/Right -> -1 (keyboard polling, no input assets)
  player_x += axis_x * 7.6 * dt
  jump    : SpaceBar just pressed && player_y <= 0 && |player_x| <= 12 -> vel_y = 7
  vel_y  -= 18 * dt ; player_y += vel_y * dt
  landing : player_y <= 0 && |player_x| <= 12 -> player_y = 0, vel_y = 0
  magma   : player_y < -8 -> respawn (x=0, y=0, vel=0)
  actor   : SetActorLocation(-800, -100*player_x, 100*player_y)
"""
import json
import socket
import sys
import time

HOST, PORT = "127.0.0.1", 55557
BP = "/Game/AiQuiz/Pawn/BP_AiQuizPawn"
KM = "KismetMathLibrary"

ids = {}


def call(command_type, params, timeout=15):
    # Per-command connection. The bridge closes the socket right after
    # answering each BP-node command, so a persistent socket silently rots and
    # every subsequent send eats a full recv timeout. Reconnecting per command
    # (same as mcp_call.py / ping) makes each command answer immediately.
    payload = json.dumps({"type": command_type, "params": params}).encode("utf-8")
    with socket.create_connection((HOST, PORT), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(payload)
        chunks = b""
        while True:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                raise TimeoutError("recv timeout: %s" % command_type)
            if not chunk:
                break  # bridge closed after answering -> parse what we have
            chunks += chunk
            try:
                return json.loads(chunks.decode("utf-8"))
            except ValueError:
                continue
        if chunks:
            return json.loads(chunks.decode("utf-8"))
        raise RuntimeError("empty response: %s" % command_type)


def cmd(command_type, params):
    _lbl = (params.get('function_name') or params.get('variable_name')
            or params.get('event_name') or params.get('component_name') or '')
    print("CMD %s %s" % (command_type, _lbl))
    time.sleep(0.12)  # let the bridge accept loop settle between connections
    try:
        res = call(command_type, params)
    except (TimeoutError, OSError) as exc:
        print("WARN retry after %r: %s" % (exc, command_type))
        time.sleep(0.5)
        res = call(command_type, params)
    if res.get("status") != "success":
        print(json.dumps({"ok": False, "cmd": command_type, "params": params,
                          "res": res}, ensure_ascii=False, indent=2))
        sys.exit(1)
    return res.get("result", {})


COL = 0


def pos():
    global COL
    COL += 1
    return [(COL % 12) * 320, (COL // 12) * 280]


def fn(key, function, target="", params=None):
    p = {"blueprint_name": BP, "function_name": function, "target": target,
         "node_position": pos()}
    if params:
        p["params"] = params
    ids[key] = cmd("add_blueprint_function_node", p)["node_id"]


def getvar(key, varname):
    ids[key] = cmd("add_blueprint_get_self_component_reference",
                   {"blueprint_name": BP, "component_name": varname,
                    "node_position": pos()})["node_id"]


def setvar(key, varname):
    ids[key] = cmd("add_blueprint_variable_set_node",
                   {"blueprint_name": BP, "variable_name": varname,
                    "node_position": pos()})["node_id"]


def conn(src, sp, dst, dp):
    print("CONN %s.%s -> %s.%s" % (src, sp, dst, dp))
    cmd("connect_blueprint_nodes",
        {"blueprint_name": BP, "source_node_id": ids[src], "source_pin": sp,
         "target_node_id": ids[dst], "target_pin": dp})


def pindef(key, pin, value):
    cmd("set_blueprint_node_pin_default",
        {"blueprint_name": BP, "node_id": ids[key], "pin_name": pin,
         "pin_value": value})


# ---- member variables ------------------------------------------------------
for v in ("AxisX", "VelY", "PlayerX", "PlayerY"):
    cmd("add_blueprint_variable",
        {"blueprint_name": BP, "variable_name": v, "variable_type": "Float"})

# ---- nodes -----------------------------------------------------------------
ids["tick"] = cmd("add_blueprint_event_node",
                  {"blueprint_name": BP, "event_name": "ReceiveTick",
                   "node_position": [0, -300]})["node_id"]

# variable getters (pure, reused everywhere; re-evaluated at each consumer)
getvar("gAxisX", "AxisX")
getvar("gVelY", "VelY")
getvar("gPX", "PlayerX")
getvar("gPY", "PlayerY")

# input polling
fn("pc", "GetPlayerController", "GameplayStatics")
fn("keyA", "IsInputKeyDown", "PlayerController")
fn("keyLeft", "IsInputKeyDown", "PlayerController")
fn("keyD", "IsInputKeyDown", "PlayerController")
fn("keyRight", "IsInputKeyDown", "PlayerController")
fn("keySpace", "WasInputKeyJustPressed", "PlayerController")
fn("orL", "BooleanOR", KM)
fn("orR", "BooleanOR", KM)
fn("selL", "SelectFloat", KM, {"A": 1.0, "B": 0.0})
fn("selR", "SelectFloat", KM, {"A": -1.0, "B": 0.0})
fn("addAxis", "Add_DoubleDouble", KM)

# player_x integration
fn("mulSpeed", "Multiply_DoubleDouble", KM, {"B": 7.6})
fn("mulSpeedDt", "Multiply_DoubleDouble", KM)
fn("addX", "Add_DoubleDouble", KM)

# jump condition
fn("leY", "LessEqual_DoubleDouble", KM, {"B": 0.0})
fn("absX", "Abs", KM)
fn("leFloor", "LessEqual_DoubleDouble", KM, {"B": 12.0})
fn("andG", "BooleanAND", KM)
fn("andJump", "BooleanAND", KM)
fn("selJump", "SelectFloat", KM, {"A": 7.0})

# gravity + integrate y
fn("mulG", "Multiply_DoubleDouble", KM, {"A": 18.0})
fn("subG", "Subtract_DoubleDouble", KM)
fn("mulVdt", "Multiply_DoubleDouble", KM)
fn("addY", "Add_DoubleDouble", KM)

# landing
fn("andLand", "BooleanAND", KM)
fn("selLandY", "SelectFloat", KM, {"A": 0.0})
fn("selLandV", "SelectFloat", KM, {"A": 0.0})

# magma death -> respawn
fn("lessDead", "Less_DoubleDouble", KM, {"B": -8.0})
fn("selDeadX", "SelectFloat", KM, {"A": 0.0})
fn("selDeadV", "SelectFloat", KM, {"A": 0.0})
fn("selDeadY", "SelectFloat", KM, {"A": 0.0})

# location output
fn("mulUEY", "Multiply_DoubleDouble", KM, {"B": -100.0})
fn("mulUEZ", "Multiply_DoubleDouble", KM, {"B": 100.0})
fn("makeVec", "MakeVector", KM, {"X": -800.0})
fn("setLoc", "K2_SetActorLocation", "")

# variable setters (exec chain)
setvar("sAxisX", "AxisX")
setvar("sPXmove", "PlayerX")
setvar("sVjump", "VelY")
setvar("sVgrav", "VelY")
setvar("sPYint", "PlayerY")
setvar("sPYland", "PlayerY")
setvar("sVland", "VelY")
setvar("sPXdead", "PlayerX")
setvar("sVdead", "VelY")
setvar("sPYdead", "PlayerY")

# ---- key pin defaults ------------------------------------------------------
pindef("keyA", "Key", "A")
pindef("keyLeft", "Key", "Left")
pindef("keyD", "Key", "D")
pindef("keyRight", "Key", "Right")
pindef("keySpace", "Key", "SpaceBar")

# ---- data connections ------------------------------------------------------
for k in ("keyA", "keyLeft", "keyD", "keyRight", "keySpace"):
    conn("pc", "ReturnValue", k, "self")

conn("keyA", "ReturnValue", "orL", "A")
conn("keyLeft", "ReturnValue", "orL", "B")
conn("keyD", "ReturnValue", "orR", "A")
conn("keyRight", "ReturnValue", "orR", "B")
conn("orL", "ReturnValue", "selL", "bPickA")
conn("orR", "ReturnValue", "selR", "bPickA")
conn("selL", "ReturnValue", "addAxis", "A")
conn("selR", "ReturnValue", "addAxis", "B")
conn("addAxis", "ReturnValue", "sAxisX", "AxisX")

conn("gAxisX", "AxisX", "mulSpeed", "A")
conn("mulSpeed", "ReturnValue", "mulSpeedDt", "A")
conn("tick", "DeltaSeconds", "mulSpeedDt", "B")
conn("gPX", "PlayerX", "addX", "A")
conn("mulSpeedDt", "ReturnValue", "addX", "B")
conn("addX", "ReturnValue", "sPXmove", "PlayerX")

conn("gPY", "PlayerY", "leY", "A")
conn("gPX", "PlayerX", "absX", "A")
conn("absX", "ReturnValue", "leFloor", "A")
conn("leY", "ReturnValue", "andG", "A")
conn("leFloor", "ReturnValue", "andG", "B")
conn("keySpace", "ReturnValue", "andJump", "A")
conn("andG", "ReturnValue", "andJump", "B")
conn("gVelY", "VelY", "selJump", "B")
conn("andJump", "ReturnValue", "selJump", "bPickA")
conn("selJump", "ReturnValue", "sVjump", "VelY")

conn("tick", "DeltaSeconds", "mulG", "B")
conn("gVelY", "VelY", "subG", "A")
conn("mulG", "ReturnValue", "subG", "B")
conn("subG", "ReturnValue", "sVgrav", "VelY")

conn("gVelY", "VelY", "mulVdt", "A")
conn("tick", "DeltaSeconds", "mulVdt", "B")
conn("gPY", "PlayerY", "addY", "A")
conn("mulVdt", "ReturnValue", "addY", "B")
conn("addY", "ReturnValue", "sPYint", "PlayerY")

conn("leY", "ReturnValue", "andLand", "A")
conn("leFloor", "ReturnValue", "andLand", "B")
conn("gPY", "PlayerY", "selLandY", "B")
conn("andLand", "ReturnValue", "selLandY", "bPickA")
conn("selLandY", "ReturnValue", "sPYland", "PlayerY")
conn("gVelY", "VelY", "selLandV", "B")
conn("andLand", "ReturnValue", "selLandV", "bPickA")
conn("selLandV", "ReturnValue", "sVland", "VelY")

conn("gPY", "PlayerY", "lessDead", "A")
conn("gPX", "PlayerX", "selDeadX", "B")
conn("lessDead", "ReturnValue", "selDeadX", "bPickA")
conn("selDeadX", "ReturnValue", "sPXdead", "PlayerX")
conn("gVelY", "VelY", "selDeadV", "B")
conn("lessDead", "ReturnValue", "selDeadV", "bPickA")
conn("selDeadV", "ReturnValue", "sVdead", "VelY")
conn("gPY", "PlayerY", "selDeadY", "B")
conn("lessDead", "ReturnValue", "selDeadY", "bPickA")
conn("selDeadY", "ReturnValue", "sPYdead", "PlayerY")

conn("gPX", "PlayerX", "mulUEY", "A")
conn("gPY", "PlayerY", "mulUEZ", "A")
conn("mulUEY", "ReturnValue", "makeVec", "Y")
conn("mulUEZ", "ReturnValue", "makeVec", "Z")
conn("makeVec", "ReturnValue", "setLoc", "NewLocation")

# ---- exec chain ------------------------------------------------------------
CHAIN = ["tick", "sAxisX", "sPXmove", "sVjump", "sVgrav", "sPYint",
         "sPYland", "sVland", "sPXdead", "sVdead", "sPYdead", "setLoc"]
for a, b in zip(CHAIN, CHAIN[1:]):
    conn(a, "then", b, "execute")

print(json.dumps({"ok": True, "nodes": len(ids)}, ensure_ascii=False))
