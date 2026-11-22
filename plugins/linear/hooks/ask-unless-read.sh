#!/bin/bash
# PreToolUse hook for one plugin's MCP server (story K1). Usage: ask-unless-read.sh <tool-name prefix>, the hook's JSON
# on stdin. A tool of this server whose name is on read-tools.txt (next to this script) gets no decision, so the
# project's own permission rules apply. Every other tool of this server, and any input this cannot read, gets "ask".
# Tools of other servers get no decision. It never allows or denies and makes no network call. Needs bash and python3.
prefix="${1:-}"; list="$(cd "$(dirname "$0")" && pwd)/read-tools.txt"
ask='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This tool could change something, and this hook could not read which tool it is; approve only if you asked for it."}}'
command -v python3 >/dev/null || { echo "$ask"; exit 0; }
python3 -I -c '
import json, sys
prefix, path, fallback = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    name = json.loads(sys.stdin.read()).get("tool_name")
except Exception:
    name = None
if not isinstance(name, str) or not prefix:
    print(fallback); sys.exit(0)
if not name.startswith(prefix):
    sys.exit(0)  # another server: no decision
tool = name[len(prefix):]
try:
    reads = {l.split("#", 1)[0].strip() for l in open(path)} - {""}
except OSError:
    reads = set()
if tool in reads:
    sys.exit(0)  # a read tool: no decision, the project rules apply
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask",
    "permissionDecisionReason": f"{tool} is not on this plugin'"'"'s read list, so it may change something; approve only if you asked for it."}}))
' "$prefix" "$list" "$ask" || echo "$ask"
exit 0
