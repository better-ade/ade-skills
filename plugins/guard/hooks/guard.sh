#!/bin/bash
# The guard's PreToolUse hook (story K6; .ade/context/connectors.md, section 4). hooks.json runs it through bash with
# onFailure "block", for every recipe's tool-name prefix and for the Bash tool; the hook's JSON arrives on stdin. It
# reads the recipes in this plugin's connectors/ folder, each checked by scripts/check-recipe.sh's own rules, and the
# project folder's .ade/connectors.json. A read tool of a connected service, a tool of a server no recipe names, and a
# shell command that cannot run gh or git get no decision; other calls under a ready recipe get "ask" (or "deny" naming
# the mode in bypassPermissions); a command that can print a credential gets "deny" in every mode. Input, a recipe or a
# helper it cannot read ends in "ask". It never allows, makes no network call, and prints exactly one JSON object or
# nothing, whatever its python3 helper (guard.py, next to this script) prints. Needs bash and python3 only.
here="${BASH_SOURCE[0]%/*}"; [ "$here" = "${BASH_SOURCE[0]}" ] && here=.
ask='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"The guard could not check this call; approve only if you asked for it."}}'
command -v python3 >/dev/null 2>&1 && [ -f "$here/guard.py" ] || { printf '%s\n' "$ask"; exit 0; }
out="$(python3 -I "$here/guard.py" "$here/.." 2>/dev/null)"; rc=$?
# Pass on only what this script expects from its helper: PASS (no decision) or one JSON line with ask or deny.
if [ "$rc" = 0 ] && [ "$out" = PASS ]; then exit 0; fi
case "$out" in
  *$'\n'*) ;;
  '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "'*'"}}'|\
  '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "'*'"}}')
    [ "$rc" = 0 ] && { printf '%s\n' "$out"; exit 0; } ;;
esac
printf '%s\n' "$ask"; exit 0
