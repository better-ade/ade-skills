#!/bin/bash
# make-hooks.sh [<guard plugin folder>]: prints the guard's hooks/hooks.json, generated from its connectors/*.json
# (story K6): one PreToolUse group for the Bash tool and one per prefix of a `ready` recipe, "<prefix>.*" (a held
# recipe gets none, so a failing guard never blocks a tool it makes no claim on), each running
# hooks/guard.sh through bash with "timeout": 10 (seconds) and onFailure "block", so a hung helper blocks the call
# within ten seconds. Each recipe must pass check-recipe.sh first; otherwise it prints
# the refusal on stderr and exits 1. Regenerate after changing a recipe:
#   bash plugins/guard/scripts/make-hooks.sh > plugins/guard/hooks/hooks.json
# tests/guard.sh fails when the committed file differs. Reads files only; needs bash and python3.
here="${BASH_SOURCE[0]%/*}"; [ "$here" = "${BASH_SOURCE[0]}" ] && here=.
G="${1:-$here/..}"
command -v python3 >/dev/null 2>&1 || { echo "make-hooks.sh: python3 is needed" >&2; exit 1; }
n=0
for f in "$G"/connectors/*.json; do
  [ -e "$f" ] || continue
  msg="$(bash "$G/scripts/check-recipe.sh" "$f")" || { echo "${msg:-$f: refused}" >&2; exit 1; }
  n=$((n + 1))
done
[ "$n" -gt 0 ] || { echo "make-hooks.sh: no recipe in $G/connectors" >&2; exit 1; }
python3 -I - "$G" <<'PY'
import glob, json, sys
prefixes = set()
for f in sorted(glob.glob(f"{sys.argv[1]}/connectors/*.json")):
    r = json.load(open(f, encoding="utf-8"))
    if r["state"] == "ready":
        prefixes.update(r["guard"]["prefixes"])
hook = {"type": "command", "command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"], "timeout": 10,
        "onFailure": "block"}
groups = [{"matcher": "Bash", "hooks": [hook]}] + [{"matcher": p + ".*", "hooks": [hook]} for p in sorted(prefixes)]
print(json.dumps({"hooks": {"PreToolUse": groups}}, indent=2))
PY
