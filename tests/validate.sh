#!/bin/bash
# claude plugin validate on the marketplace and on every plugin it lists (story N1). Fails, never skips, when claude
# is missing. Usage: tests/validate.sh [repo-root] (default: this repo). Exit 0 = pass.
R="${1:-$(cd "$(dirname "$0")/.." && pwd)}"; rc=0
command -v claude >/dev/null || { echo "FAIL: claude is not installed, so plugins cannot be validated (install Claude Code)"; exit 1; }
claude plugin validate "$R" >/dev/null 2>&1 || { echo "FAIL: claude plugin validate $R (run it for details)"; rc=1; }
srcs="$(python3 -c 'import json,sys; [print(p["source"]) for p in json.load(open(sys.argv[1]))["plugins"]]' "$R/.claude-plugin/marketplace.json")" \
  || { echo "FAIL: cannot read $R/.claude-plugin/marketplace.json"; exit 1; }
while IFS= read -r s; do
  [ -n "$s" ] || continue; p="$R/${s#./}"
  claude plugin validate "$p" >/dev/null 2>&1 || { echo "FAIL: claude plugin validate $p (run it for details)"; rc=1; }
done <<< "$srcs"
exit $rc
