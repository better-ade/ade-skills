#!/bin/bash
# The verification command for ade-skills: bash tests/run.sh (exit 0 = pass).
cd "$(dirname "$0")/.." || exit 1; rc=0; fail() { echo "FAIL: $*"; rc=1; }
python3 - <<'PY' || rc=1
import json, os, sys
bad = []
m = json.load(open(".claude-plugin/marketplace.json"))
names = [p["name"] for p in m["plugins"]]
if len(names) != len(set(names)): bad.append("duplicate plugin names in marketplace.json")
for p in m["plugins"]:
    if "version" in p: bad.append(f"{p['name']}: version belongs in plugin.json only")
    pj = os.path.join(p["source"], ".claude-plugin", "plugin.json")
    if not os.path.exists(pj): bad.append(f"{p['name']}: no {pj}"); continue
    j = json.load(open(pj))
    if j.get("name") != p["name"]: bad.append(f"{pj}: name {j.get('name')} != {p['name']}")
    if not j.get("version"): bad.append(f"{pj}: no version")
for root, _, files in os.walk("plugins"):
    for f in files:
        if f == "SKILL.md":
            s = open(os.path.join(root, f)).read()
            if not s.startswith("---\nname: "): bad.append(f"{root}/SKILL.md: no front matter with name")
            if "\n## Ask first\n" not in s: bad.append(f"{root}/SKILL.md: no '## Ask first' section")
        if f == ".mcp.json":
            for n, c in json.load(open(os.path.join(root, f))).get("mcpServers", {}).items():
                for a in c.get("args", []):
                    if a.startswith("@") and "@" not in a[1:]: bad.append(f"{root}/.mcp.json: {n} package {a} has no pinned version")
print("\n".join("FAIL: " + b for b in bad)) if bad else None
sys.exit(1 if bad else 0)
PY
for t in validate docs meta ade notes fde connectors recipes; do bash "tests/$t.sh" || rc=1; done
if command -v gitleaks >/dev/null; then gitleaks dir . --no-banner --redact --log-level warn >/dev/null || fail "gitleaks found a secret"
else echo "note: gitleaks not installed, secret scan skipped"; fi
[ $rc = 0 ] && echo ok; exit $rc
