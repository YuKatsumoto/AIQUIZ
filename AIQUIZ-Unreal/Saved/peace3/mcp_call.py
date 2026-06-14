#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Direct TCP client for the UnrealMCP C++ bridge (port 55557).

Bypasses the Python MCP server so that newly added bridge commands can be
called without updating the MCP tool definitions.

Usage:
    python mcp_call.py <command_type> '<params_json>'
    python mcp_call.py --file <batch.json>   # [{"type":..., "params":...}, ...]
"""
import sys, json, socket, time

HOST, PORT = "127.0.0.1", 55557
TIMEOUT = 30.0


def call(command_type, params):
    payload = json.dumps({"type": command_type, "params": params}).encode("utf-8")
    with socket.create_connection((HOST, PORT), timeout=TIMEOUT) as sock:
        sock.sendall(payload)
        chunks = b""
        sock.settimeout(TIMEOUT)
        while True:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            chunks += chunk
            try:
                return json.loads(chunks.decode("utf-8"))
            except ValueError:
                continue
    raise RuntimeError("no parseable response: %r" % chunks[:500])


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--file":
        batch = json.load(open(sys.argv[2], encoding="utf-8"))
        results = []
        for entry in batch:
            time.sleep(0.3)  # let the editor tick settle between commands
            res = call(entry["type"], entry.get("params", {}))
            results.append({"cmd": entry["type"], "res": res})
            status = res.get("status")
            if status == "error":
                print(json.dumps({"ok": False, "failed_at": entry, "results": results},
                                 ensure_ascii=False, indent=2))
                return 1
        print(json.dumps({"ok": True, "results": results}, ensure_ascii=False, indent=2))
        return 0

    command_type = sys.argv[1]
    params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    print(json.dumps(call(command_type, params), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
