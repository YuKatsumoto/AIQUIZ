#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Run Python inside an ALREADY-RUNNING Unreal editor (no cold boot).

Uses Unreal's official Python *Remote Execution* (multicast discovery + TCP), which
is already enabled for this project (Config/DefaultEngine.ini -> bRemoteExecution=True,
group 239.0.0.1:6766). Keep ONE editor open and every editor operation becomes instant
instead of paying the ~25-40s UnrealEditor-Cmd cold boot each time.

Usage:
    python ue_exec.py path/to/script.py        # execute a .py file in the live editor
    python ue_exec.py -c "import unreal; print(unreal.SystemLibrary.get_engine_version())"

Exit code: 0 = command ran & reported success, 1 = ran but reported failure,
           3 = no running editor found (start one first).

Output: the editor's captured stdout/log (so any print("RESULT ...") in your script
comes straight back here).
"""
import sys
import os
import time

# Official Epic remote-execution helper that ships with the engine.
ENGINE_RE_DIR = os.environ.get(
    "UE_REMOTE_EXEC_DIR",
    r"G:\UE_5.7\Engine\Plugins\Experimental\PythonScriptPlugin\Content\Python",
)
sys.path.insert(0, ENGINE_RE_DIR)
import remote_execution as remote  # noqa: E402


def _node_id(node):
    # remote_nodes entries may be dicts or objects across engine versions.
    if isinstance(node, dict):
        return node.get("node_id")
    return getattr(node, "node_id", None)


def main():
    if len(sys.argv) < 2:
        print("usage: ue_exec.py <script.py> | -c <code>")
        return 2

    if sys.argv[1] == "-c":
        command = sys.argv[2]
        exec_mode = remote.MODE_EXEC_STATEMENT
    else:
        command = os.path.abspath(sys.argv[1])  # a file path -> MODE_EXEC_FILE
        exec_mode = remote.MODE_EXEC_FILE

    rexec = remote.RemoteExecution()
    rexec.start()
    try:
        node_id = None
        deadline = time.time() + 8.0  # discovery window
        while time.time() < deadline:
            nodes = rexec.remote_nodes
            if nodes:
                node_id = _node_id(nodes[0])
                if node_id:
                    break
            time.sleep(0.15)
        if not node_id:
            print("ERROR: no running UE editor found. Start one once, e.g.:")
            print('  UnrealEditor-Cmd.exe "C:\\aiquiz\\AIQUIZ-Unreal\\AiQuiz.uproject"')
            return 3

        rexec.open_command_connection(node_id)
        try:
            res = rexec.run_command(
                command, unattended=True, exec_mode=exec_mode, raise_on_failure=False
            )
        finally:
            rexec.close_command_connection()
    finally:
        rexec.stop()

    ok = bool(res.get("success"))
    for entry in res.get("output", []) or []:
        line = (entry.get("output") or "").rstrip("\n")
        if line:
            print(line)
    if res.get("result") not in (None, "None", ""):
        print("RESULT_VALUE:", res.get("result"))
    print("SUCCESS:", ok)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
