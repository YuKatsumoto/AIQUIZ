#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""起動中エディタの remote-exec ノードを最大 N 秒待って発見し、指定 .py を実行する。
Usage: python p3_drive.py <script.py> [deadline_sec]
"""
import sys, os, time, json

RE_DIR = r"G:/UE_5.7/Engine/Plugins/Experimental/PythonScriptPlugin/Content/Python"
sys.path.insert(0, RE_DIR)
import remote_execution as re  # noqa: E402


def make_config():
    cfg = re.RemoteExecutionConfig()
    cfg.multicast_group_endpoint = ("239.0.0.1", 6766)
    cfg.multicast_bind_address = "127.0.0.1"
    cfg.multicast_ttl = 0
    return cfg


def main():
    target = os.path.abspath(sys.argv[1]).replace("\\", "/")
    deadline_sec = float(sys.argv[2]) if len(sys.argv) > 2 else 180.0

    rexec = re.RemoteExecution(make_config())
    rexec.start()
    try:
        node_id = None
        deadline = time.time() + deadline_sec
        while time.time() < deadline:
            nodes = rexec.remote_nodes
            if nodes:
                node_id = nodes[0]["node_id"]
                break
            time.sleep(1.0)
        if not node_id:
            print(json.dumps({"ok": False, "error": "no UE node within %ss" % deadline_sec}))
            return 1
        rexec.open_command_connection(node_id)
        result = rexec.run_command(target, unattended=True, exec_mode=re.MODE_EXEC_FILE, raise_on_failure=False)
        print(json.dumps({"ok": bool(result.get("success")), "output": result.get("output")}, ensure_ascii=False))
        return 0 if result.get("success") else 1
    finally:
        try:
            rexec.close_command_connection()
        except Exception:
            pass
        rexec.stop()


if __name__ == "__main__":
    sys.exit(main())
