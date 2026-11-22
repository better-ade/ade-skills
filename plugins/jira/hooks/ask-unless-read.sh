#!/bin/bash
# PreToolUse hook for one plugin's MCP server (story K1). Usage: bash ask-unless-read.sh <tool-name prefix>, the hook's
# JSON on stdin. A tool of this server whose name is on read-tools.txt (next to this script) gets no decision, so the
# project's own permission rules apply. Every other tool of this server, and any input this cannot read, gets "ask";
# with prompts switched off (permission_mode bypassPermissions) such a tool gets "deny" instead. Tools of other servers
# get no decision. It never allows and makes no network call. It prints exactly one JSON object or nothing, whatever
# its helper prints. Needs bash and python3; hooks.json runs it through bash with onFailure "block".
prefix="${1:-}"; list="$(cd "$(dirname "$0")" && pwd)/read-tools.txt"
ask='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This tool could change something, and this hook could not read which tool it is; approve only if you asked for it."}}'
command -v python3 >/dev/null 2>&1 || { printf '%s\n' "$ask"; exit 0; }
out="$(python3 -I -c '
import json, sys
prefix, path = sys.argv[1], sys.argv[2]
try:
    data = json.loads(sys.stdin.read())
    name = data.get("tool_name")
    mode = data.get("permission_mode", "default")
except Exception:
    name = mode = None
if not isinstance(name, str) or not isinstance(mode, str) or not prefix:
    print("ASK"); sys.exit(0)
if not name.startswith(prefix):
    print("PASS"); sys.exit(0)  # another server: no decision
tool = name[len(prefix):]
try:
    reads = {l.split("#", 1)[0].strip() for l in open(path)} - {""}
except OSError:
    reads = set()
if tool in reads:
    print("PASS"); sys.exit(0)  # a read tool: no decision, the project rules apply
if mode == "bypassPermissions":
    decision = "deny"
    why = f"{tool} is not on this plugin'"'"'s read list, and the session is in bypassPermissions mode, so no one would be asked; it is refused. Run it in a mode that prompts."
else:
    decision = "ask"
    why = f"{tool} is not on this plugin'"'"'s read list, so it may change something; approve only if you asked for it."
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                         "permissionDecisionReason": why}}))
' "$prefix" "$list" 2>/dev/null)"; rc=$?
# Pass on only what this script expects from its helper: PASS (no decision) or one JSON line with a decision.
if [ "$rc" = 0 ] && [ "$out" = PASS ]; then exit 0; fi
case "$out" in
  *$'\n'*) ;;
  '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", '*'}}'|\
  '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", '*'}}')
    [ "$rc" = 0 ] && { printf '%s\n' "$out"; exit 0; } ;;
esac
printf '%s\n' "$ask"; exit 0
