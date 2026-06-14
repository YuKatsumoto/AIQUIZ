#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UE Python Remote Execution runner.

Sends a local .py file to a running Unreal Editor (with bRemoteExecution=True)
and prints success/output. Pure stdlib + UE's bundled remote_execution.py.

Usage:
    python ue_run.py <abs_path_to_script.py>
    python ue_run.py --stmt "import unreal; print(unreal.SystemLibrary.get_engine_version())"
"""
import sys, os, time, json

RE_DIR = r"G:/UE_5.7/Engine/Plugins/Experimental/PythonScriptPlugin/Content/Python"
sys.path.insert(0, RE_DIR)
import remote_execution as re  # noqa: E402


def make_config():
    cfg = re.RemoteExecutionConfig()
    # Must match Config/DefaultEngine.ini [PythonScriptPluginSettings]
    cfg.multicast_group_endpoint = ("239.0.0.1", 6766)
    cfg.multicast_bind_address = "127.0.0.1"
    cfg.multicast_ttl = 0
    return cfg


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "no target given"}))
        return 2

    if sys.argv[1] == "--stmt":
        command = sys.argv[2]
        exec_mode = re.MODE_EXEC_STATEMENT
    else:
        command = os.path.abspath(sys.argv[1]).replace("\\", "/")
        exec_mode = re.MODE_EXEC_FILE
        if not os.path.isfile(command):
            print(json.dumps({"ok": False, "error": "file not found: " + command}))
            return 2

    rexec = re.RemoteExecution(make_config())
    rexec.start()
    try:
        # Discover the editor node (UDP multicast ping/pong)
        node_id = None
        deadline = time.time() + 12.0
        while time.time() < deadline:
            nodes = rexec.remote_nodes
            if nodes:
                node_id = nodes[0]["node_id"]
                break
            time.sleep(0.25)
        if not node_id:
            print(json.dumps({"ok": False, "error": "no UE node found (is bRemoteExecution=True and editor restarted?)"}))
            return 1

        rexec.open_command_connection(node_id)
        result = rexec.run_command(command, unattended=True, exec_mode=exec_mode, raise_on_failure=False)
        out = {
            "ok": bool(result.get("success")),
            "node": node_id,
            "command": command if exec_mode == re.MODE_EXEC_FILE else "<stmt>",
            "result": result.get("result"),
            "output": result.get("output"),
        }
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0 if out["ok"] else 1
    finally:
        rexec.close_command_connection()
        rexec.stop()


if __name__ == "__main__":
    sys.exit(main())
