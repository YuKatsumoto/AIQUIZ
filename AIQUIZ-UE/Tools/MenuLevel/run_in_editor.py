"""起動中の Unreal Editor で Python スクリプトを実行する (Python Remote Execution)。

  python Tools/MenuLevel/run_in_editor.py Tools/MenuLevel/02_environment.py
"""
import io
import sys
import time

sys.path.insert(0, r"G:\UE_5.8\Engine\Plugins\Experimental\PythonScriptPlugin\Content\Python")
import remote_execution as rex  # noqa: E402

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")


def main():
    code = open(sys.argv[1], encoding="utf-8").read()
    cfg = rex.RemoteExecutionConfig()
    cfg.multicast_bind_address = "127.0.0.1"
    r = rex.RemoteExecution(cfg)
    r.start()
    try:
        deadline = time.time() + 12
        while time.time() < deadline and not r.remote_nodes:
            time.sleep(0.2)
        if not r.remote_nodes:
            print("NO_EDITOR_FOUND")
            sys.exit(2)
        node = r.remote_nodes[0]
        r.open_command_connection(node["node_id"])
        res = r.run_command(code, unattended=True, exec_mode=rex.MODE_EXEC_FILE, raise_on_failure=False)
        for o in res.get("output", []):
            t = o.get("type", "")
            line = o.get("output", "").rstrip()
            if t in ("Warning", "Error"):
                print("[%s] %s" % (t, line))
            else:
                print(line)
        if not res.get("success"):
            print("FAILED:", res.get("result"))
            sys.exit(1)
    finally:
        r.stop()


if __name__ == "__main__":
    main()
