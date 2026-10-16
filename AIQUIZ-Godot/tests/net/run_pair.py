"""Online end-to-end pair test.

Starts the real relay (C:/AIQUIZ/relay-server) and two game processes running
tests/net/net_match_runtime.gd, then checks that host and guest agree.

    python tests/net/run_pair.py                       # clean link
    python tests/net/run_pair.py --netsim lat=120,jit=40
    python tests/net/run_pair.py --kill-at 3           # guest drops at wall 3 and resumes
    python tests/net/run_pair.py --kill-at 3 --kill-role host
    python tests/net/run_pair.py --headless            # no windows (dummy renderer)
    python tests/net/run_pair.py --scenario staging    # also checks the matching presentation (spec A5/A6)
    python tests/net/run_pair.py --quit-at-cutin       # host vanishes at its cut-in; guest searches again (spec A7)
    python tests/net/run_pair.py --scenario ghost      # guest falls off, rides the ghost shark and hits the host
    python tests/net/run_pair.py --scenario ghost_host # the same with the host as the rider
    python tests/net/run_pair.py --scenario result     # play to the goal and through the score-tower result ceremony
    python tests/net/run_pair.py --scenario result_elim  # both fall off first: the ceremony opens with two ghosts
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELAY = ROOT.parent / "relay-server"
GODOT = ROOT / "Godot_v4.7.2-stable_win64_console.exe"
OUT = ROOT / "artifacts" / "net"
PORT = 18766
WRONG_WALLS = {1, 4}


RELAY_WS = f"ws://127.0.0.1:{PORT}"


def health() -> dict:
    base = RELAY_WS.replace("wss://", "https://").replace("ws://", "http://")
    with urllib.request.urlopen(f"{base}/health", timeout=3) as resp:
        return json.loads(resp.read())


def wait_for(predicate, timeout: float, what: str) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except Exception:
            pass
        time.sleep(0.2)
    raise SystemExit(f"timed out waiting for {what}")


def launch(role: str, args) -> tuple[subprocess.Popen, object]:
    log = open(OUT / f"{role}.log", "w", encoding="utf-8")
    cmd = [str(GODOT), "--path", str(ROOT)]
    if args.headless:
        cmd.append("--headless")
    else:
        cmd += ["--resolution", "960x540", "--position", "0,0" if role == "host" else "970,0"]
    cmd += ["--script", "tests/net/net_match_bootstrap.gd", "--",
            f"role={role}", f"relay={RELAY_WS}", f"out={(OUT / f'{role}.json').as_posix()}",
            f"shots={(OUT / 'shots').as_posix()}"]
    if args.quit_at_cutin:
        cmd.append("scenario=quit_at_cutin")
    elif args.scenario:
        cmd.append(f"scenario={args.scenario}")
    if args.quit_at >= 0 and role == "guest":
        cmd.append(f"quit_at={args.quit_at}")
    if args.kill_at >= 0 and role == args.kill_role:
        cmd.append(f"kill_at={args.kill_at}")
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    return subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=flags), log


def check_ghost(scenario: str, h: dict, g: dict) -> list[str]:
    """The rider's screen decides aim, dash and hit; the other screen replays them; the host applies the knockback."""
    errors: list[str] = []
    rider, mirror = (h, g) if scenario == "ghost_host" else (g, h)
    rider_name, mirror_name = ("host", "guest") if scenario == "ghost_host" else ("guest", "host")
    rn = rider.get("ghost", {}).get("net", {})
    mn = mirror.get("ghost", {}).get("net", {})
    hn = h.get("ghost", {}).get("net", {})
    if "AIMING" not in rider.get("ghost", {}).get("phases", []):
        errors.append(f"{rider_name} never reached ghost AIMING: {rider.get('ghost', {}).get('phases')}")
    if "AIMING" not in mirror.get("ghost", {}).get("phases", []):
        errors.append(f"{mirror_name} never showed the opponent's ghost aiming: {mirror.get('ghost', {}).get('phases')}")
    sent, played = rn.get("launches_sent", 0), mn.get("launches_played", 0)
    if sent < 2:
        errors.append(f"{rider_name} launched only {sent} ghost dashes")
    # The last dash may still be on its way when the round ends.
    if played < sent - 1 or played > sent:
        errors.append(f"dashes: {rider_name} sent {sent}, {mirror_name} replayed {played}")
    hits = rn.get("hits_sent", 0)
    if hits < 1:
        errors.append(f"{rider_name} never hit the survivor ({rn})")
    applied = hn.get("impulses_applied", 0)
    if applied < hits - 1 or applied > hits:
        errors.append(f"knockbacks: {rider_name} hit {hits}, host applied {applied}")
    presented = mn.get("hits_presented", 0)
    if presented < hits - 1 or presented > hits:
        errors.append(f"hits: {rider_name} hit {hits}, {mirror_name} showed {presented}")
    for role_name, rep in (("host", h), ("guest", g)):
        if rep.get("ghost", {}).get("knockbacks", 0) < 1:
            errors.append(f"{role_name} never saw the survivor knocked back")
    return errors


RESULT_PHASES = ["ASSEMBLE", "WALK", "SCORE_ROLL", "VERDICT", "EFFECT", "WINNER", "INTERACTIVE"]


def check_result(scenario: str, h: dict, g: dict) -> list[str]:
    """Both screens play the same score-tower ceremony; the guest's starts from the host's result_begin."""
    errors: list[str] = []
    hr, gr = h.get("result", {}), g.get("result", {})
    for role_name, rep in (("host", hr), ("guest", gr)):
        if rep.get("game_over_card"):
            errors.append(f"{role_name}: showed the GAME OVER card instead of the ceremony")
        phases = rep.get("phases", [])
        if phases != RESULT_PHASES:
            errors.append(f"{role_name}: ceremony phases {phases}")
        if rep.get("finished_at_begin"):
            errors.append(f"{role_name}: the match was already finished when the ceremony began")
        if rep.get("state_at_end") != "CLEAR":
            errors.append(f"{role_name}: state at the end of the ceremony was {rep.get('state_at_end')}")
        hud = rep.get("hud", {})
        if not hud.get("actions_visible") or hud.get("buttons") != ["BtnHistory", "BtnMenu"]:
            errors.append(f"{role_name}: result buttons {hud.get('buttons')} (want history and menu, no retry)")
        if hud.get("menu_text") != "オンラインメニューへ":
            errors.append(f"{role_name}: menu button reads {hud.get('menu_text')!r}")
        if scenario == "result_elim" and (rep.get("ghosts") != 3 or not rep.get("elimination")):
            errors.append(f"{role_name}: elimination ceremony without both ghosts ({rep.get('ghosts')}, {rep.get('elimination')})")
    for key in ("winner", "points", "correct", "ghosts", "elimination"):
        if hr.get(key) != gr.get(key):
            errors.append(f"result {key} differ: host={hr.get(key)} guest={gr.get(key)}")
    if hr.get("hud", {}).get("totals") != gr.get("hud", {}).get("totals"):
        errors.append(f"tower totals differ: host={hr.get('hud', {}).get('totals')} guest={gr.get('hud', {}).get('totals')}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--netsim", default="")
    parser.add_argument("--kill-at", type=int, default=-1)
    parser.add_argument("--kill-role", default="guest", choices=["host", "guest"])
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--scenario", default="", choices=["", "push", "staging", "ghost", "ghost_host", "result", "result_elim"])
    parser.add_argument("--quit-at-cutin", action="store_true", help="host vanishes when its cut-in starts; the guest must search again in the air")
    parser.add_argument("--reveal-limit", type=float, default=11.0, help="max seconds from match to the split opening (staging, spec A6 v1.3)")
    parser.add_argument("--quit-at", type=int, default=-1, help="guest vanishes at this wall; host must win by forfeit")
    parser.add_argument("--timeout", type=float, default=400)
    parser.add_argument("--relay", default="", help="use a running relay (e.g. the deployed wss:// URL) instead of a local one")
    args = parser.parse_args()
    global RELAY_WS
    if args.relay:
        RELAY_WS = args.relay.rstrip("/")
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ("host.json", "guest.json"):
        (OUT / name).unlink(missing_ok=True)

    env = {**os.environ}
    if args.netsim:
        env["RELAY_NETSIM"] = args.netsim
    if args.quit_at >= 0 or args.quit_at_cutin:
        env["RELAY_GRACE_S"] = "6"
    relay_log = open(OUT / "relay.log", "w", encoding="utf-8")
    relay = None
    if not args.relay:
        relay = subprocess.Popen([sys.executable, "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", str(PORT)],
                                 cwd=RELAY, env=env, stdout=relay_log, stderr=subprocess.STDOUT)
    procs = []
    try:
        wait_for(lambda: health()["status"] == "ok", 20, "relay")
        host = launch("host", args)
        procs.append(host)
        # The earlier queue entry becomes host: start the guest only once the host waits.
        wait_for(lambda: health()["queued"] >= 1, 90, "host to queue")
        guest = launch("guest", args)
        procs.append(guest)
        deadline = time.monotonic() + args.timeout
        for proc, _log in procs:
            proc.wait(max(1, deadline - time.monotonic()))
    except subprocess.TimeoutExpired:
        print("pair timed out")
    finally:
        for proc, log in procs:
            if proc.poll() is None:
                proc.kill()
            log.close()
        if relay is not None:
            relay.terminate()
            relay.wait(10)
        relay_log.close()

    errors: list[str] = []
    reports = {}
    for role in ("host", "guest"):
        path = OUT / f"{role}.json"
        if not path.exists():
            if not ((args.quit_at >= 0 and role == "guest") or (args.quit_at_cutin and role == "host")):
                errors.append(f"{role}: no report")
            continue
        reports[role] = json.loads(path.read_text(encoding="utf-8"))
        errors += [f"{role}: {f}" for f in reports[role].get("failures", [])]
    if args.quit_at_cutin:
        g = reports.get("guest", {})
        errors = [e for e in errors if not e.startswith("host:")]
        if not g.get("requeued"):
            errors.append("guest did not search again after the host vanished at the cut-in")
        if not g.get("back_to_search"):
            errors.append("guest did not return to the search band in the air")
        reports = {}
    if args.quit_at >= 0:
        h = reports.get("host", {})
        errors = [e for e in errors if not e.startswith("guest:")]
        if "かち" not in h.get("match_over", ""):
            errors.append(f"host was not awarded the forfeit win: {h.get('match_over')!r}")
        reports = {}
    if len(reports) == 2:
        h, g = reports["host"], reports["guest"]
        if not (h.get("is_host") and not g.get("is_host")):
            errors.append("roles not assigned host/guest")
        if g.get("local_slot") != 2:
            errors.append("guest local_slot is not 2")
        for key in ("winners", "hp", "scores", "alive"):
            if h.get(key) != g.get(key):
                errors.append(f"{key} differ: host={h.get(key)} guest={g.get(key)}")
        # Every question the guest reached first must be judged the way the guest saw it.
        winners = h.get("winners", [])
        for hit in g.get("guest_hits", []):
            wall = hit["wall"]
            if wall >= len(winners) or winners[wall] < 0:
                continue
            guest_saw_correct = hit["door"] == hit["answer"]
            host_says_guest_correct = (winners[wall] & 2) != 0
            if guest_saw_correct != host_says_guest_correct:
                errors.append(f"wall {wall}: guest saw {'correct' if guest_saw_correct else 'wrong'} door, host judged otherwise")
        if args.scenario == "push":
            hp, gp = h.get("push_events", {}), g.get("push_events", {})
            if hp.get("hit_p2", 0) < 1:
                errors.append(f"guest never landed a shove on the host: {hp}")
            for kind in ("contact", "hit_p1", "hit_p2", "clash"):
                if hp.get(kind, 0) != gp.get(kind, 0):
                    errors.append(f"push {kind}: host saw {hp.get(kind, 0)}, guest saw {gp.get(kind, 0)}")
            if not g.get("push_contact_seen"):
                errors.append("guest never rendered push contact")
        if args.scenario in ("ghost", "ghost_host"):
            errors += check_ghost(args.scenario, h, g)
        if args.scenario in ("result", "result_elim"):
            errors += check_result(args.scenario, h, g)
        if args.scenario == "staging":
            hs, gst = h.get("staging", {}), g.get("staging", {})
            hn, gn = hs.get("cutin_names", []), gst.get("cutin_names", [])
            if len(hn) != 2 or len(gn) != 2 or hn != list(reversed(gn)):
                errors.append(f"cut-in names do not mirror: host={hn} guest={gn}")
            if hs.get("cutin_poses") != list(reversed(gst.get("cutin_poses", []))):
                errors.append(f"cut-in poses do not mirror: host={hs.get('cutin_poses')} guest={gst.get('cutin_poses')}")
            for role_name, st in (("host", hs), ("guest", gst)):
                seconds = st.get("match_to_reveal_s")
                if seconds is None or seconds > args.reveal_limit:
                    errors.append(f"{role_name}: match to reveal took {seconds} s (limit {args.reveal_limit})")
                if "CUTIN_HOLD" not in st.get("states", []):
                    errors.append(f"{role_name}: never showed the cut-in hold ({st.get('states')})")
                # 対峙の演出（合流〜割れて開く）はカクつかない：25 ms をこえるフレームがない（覆いの静止画のあいだは除く）
                for phase in ("JOIN", "FORMATION", "CUTIN_IN", "CUTIN_HOLD", "REVEAL"):
                    frames = st.get("vs_frames", {}).get(phase)
                    if frames and frames.get("hitches", 0) > 0:
                        errors.append(f"{role_name}: {phase} stuttered ({frames})")
                # 問題生成は覆いが開ききってから（ホスト）
                if role_name == "host" and st.get("generation_in_reveal"):
                    errors.append("host: quiz generation started while the VS cover was opening")
                # VS の効果音：カットインの入り・溜め・割れて開く
                cues = [c[0] for c in st.get("sfx", [])]
                for cue in ("versus_cutin_in", "versus_charge"):
                    if cue not in cues:
                        errors.append(f"{role_name}: {cue} never played ({cues})")
                if "versus_reveal" not in cues and "versus_reveal_short" not in cues:
                    errors.append(f"{role_name}: the reveal sound never played ({cues})")
        # 中央の線が開いたら、両方の画面でそれぞれのヘリが 2 人を運んでくる（計画書 M9）
        for role_name, rep in (("host", h), ("guest", g)):
            arr = rep.get("arrival", {})
            if not arr.get("present") or arr.get("helicopters") != 2:
                errors.append(f"{role_name}: no helicopter arrival for both players ({arr})")
            elif not (arr.get("finished") and arr.get("landed_before_start")):
                errors.append(f"{role_name}: the round started before the helicopters had landed ({arr})")
        if h.get("wall", 0) < 3 and args.scenario != "result_elim":
            errors.append(f"only reached wall {h.get('wall')}")
        if args.kill_at >= 0:
            for role, rep in (("host", h), ("guest", g)):
                if not (rep.get("pause_seen") and rep.get("resume_seen")):
                    errors.append(f"{role} did not pause and resume after the {args.kill_role}'s dropped link")
    summary = {"passed": not errors, "relay": RELAY_WS, "netsim": args.netsim, "kill_at": args.kill_at, "failures": errors,
               "host": {k: reports.get("host", {}).get(k) for k in ("state", "wall", "winners", "hp", "rtt_ms", "push_events", "staging", "arrival", "ghost", "result")},
               "guest": {k: reports.get("guest", {}).get(k) for k in ("state", "wall", "winners", "hp", "corrections", "far_corrections", "rtt_ms", "push_events", "push_contact_seen", "staging", "arrival", "ghost", "result")}}
    (OUT / "report.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
