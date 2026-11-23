#!/bin/bash
# PreToolUse hook for the orgo plugin's MCP server (story K8; the K1 connectors' hook, with Orgo's two additions).
# Usage: bash ask-unless-read.sh <tool-name prefix>, the hook's JSON on stdin. A tool of this server whose name is on
# read-tools.txt (next to this script) gets no decision, so the project's own permission rules apply. Every other tool
# of this server, and any input this cannot read, gets "ask"; with prompts switched off (permission_mode
# bypassPermissions) such a tool gets "deny" instead. Tools of other servers get no decision. The question names the
# tool; for a tool that creates or starts a computer it says Orgo bills the computer by the hour while it runs; for
# the bash and Python tools it ends with the command: its first line, without control or invisible characters, cut to
# 200 characters. It never allows and makes no network call. It prints exactly one JSON object or nothing, whatever
# its helper prints. Needs bash and python3; hooks.json runs it through bash with onFailure "block".
prefix="${1:-}"; list="$(cd "$(dirname "$0")" && pwd)/read-tools.txt"
ask='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This tool could change something, and this hook could not read which tool it is; approve only if you asked for it."}}'
command -v python3 >/dev/null 2>&1 || { printf '%s\n' "$ask"; exit 0; }
helper="$(cat <<'PY'
import json, sys, unicodedata
prefix, path = sys.argv[1], sys.argv[2]
RUNS = {"orgo_create_computer", "orgo_clone_computer", "orgo_fork_computer", "orgo_start_computer",
        "orgo_restart_computer", "orgo_resume_computer"}           # each leaves a computer running
COSTS = {"orgo_resize_computer", "orgo_extend_computer"}
COMMANDS = {"orgo_execute_bash": ("command", "Command"), "orgo_execute_python": ("code", "Code")}
def clean(s):
    # Tabs become spaces; control, format, surrogate, private-use and unassigned characters and line separators go.
    return "".join(" " if c == "\t" else c for c in s
                   if c == "\t" or (unicodedata.category(c)[0] != "C" and unicodedata.category(c) not in ("Zl", "Zp")))
try:
    data = json.loads(sys.stdin.read())
    name = data.get("tool_name")
    mode = data.get("permission_mode", "default")
except Exception:
    data = name = mode = None
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
shown = clean(tool)[:80] or "A tool with no name"
why = f"{shown} is not on this plugin's read list"
if tool in RUNS:
    why += "; it creates or starts a computer, and Orgo bills the computer by the hour while it runs"
elif tool in COSTS:
    why += "; it can change what Orgo charges for the computer"
elif tool in COMMANDS:
    why += "; it runs a command on a remote Orgo computer"
else:
    why += ", so it may change something on Orgo"
if mode == "bypassPermissions":
    decision = "deny"
    why += ", and the session is in bypassPermissions mode, so no one would be asked; it is refused. Run it in a mode that prompts."
else:
    decision = "ask"
    why += "; approve only if you asked for it."
if tool in COMMANDS:
    key, label = COMMANDS[tool]
    ti = data.get("tool_input")
    text = ti.get(key) if isinstance(ti, dict) else None
    lines = [l for l in text.splitlines() if l.strip()] if isinstance(text, str) else []
    if not lines:
        why += " This hook could not read the command."
    else:
        first = clean(lines[0][:4000]).strip()
        cut = len(first) > 200 or len(lines[0]) > 4000
        if len(lines) > 1: label += f", first line of {len(lines)}"
        if cut: label += ", cut to 200 characters"
        why += f" {label}: {first[:200]}"
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                         "permissionDecisionReason": why}}))
PY
)"
out="$(python3 -I -c "$helper" "$prefix" "$list" 2>/dev/null)"; rc=$?
# Pass on only what this script expects from its helper: PASS (no decision) or one JSON line with a decision.
if [ "$rc" = 0 ] && [ "$out" = PASS ]; then exit 0; fi
case "$out" in
  *$'\n'*) ;;
  '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", '*'}}'|\
  '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", '*'}}')
    [ "$rc" = 0 ] && { printf '%s\n' "$out"; exit 0; } ;;
esac
printf '%s\n' "$ask"; exit 0
