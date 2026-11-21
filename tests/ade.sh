#!/bin/bash
# Story P1 checks for the ade plugin (files only, no model calls). Called by tests/run.sh; exit 0 = pass.
cd "$(dirname "$0")/.." || exit 1
python3 - <<'PY'
import json, os, re, sys
bad = []
P = "plugins/ade"
def read(p):
    try: return open(p).read()
    except OSError: bad.append(f"{p}: missing"); return ""
def section(s, h):
    m = re.search(rf"^## {re.escape(h)}\n(.*?)(?=^## |\Z)", s, re.S | re.M)
    return m.group(1) if m else ""

# AC2: each command file runs exactly one `ade ...` command, every user argument double-quoted.
want = {
    "status": ("ade status", 0), "doctor": ("ade doctor", 0),
    "work": ("ade work", 2), "dispatch": ("ade dispatch", 1), "notify": ("ade notify", 2),
    "agent-add": ("ade agent add", 1), "skills-add": ("ade skills add", 1),
}
ESCAPE = "Before running it, escape every `\"`, `$` and backtick in each argument with a backslash; if an argument contains a newline, run nothing and say why."
changes_state = {"work", "dispatch", "notify", "agent-add", "skills-add"}
for name, (prefix, nargs) in want.items():
    f = f"{P}/commands/{name}.md"
    s = read(f)
    if not s: continue
    if not s.startswith("---\ndescription: "): bad.append(f"{f}: no front matter with description")
    lines = [l.strip() for l in s.splitlines() if re.match(r"^\s*ade\s", l)]
    # One command runs; work.md shows two variants (with and without a role) so an empty role never becomes --role "".
    variants = {"work": ['ade work "$1"', 'ade work --role "$2" "$1"']}
    if name in variants:
        if sorted(lines) != sorted(variants[name]): bad.append(f"{f}: command lines {lines}, want exactly {variants[name]}")
        if "Only when a role was given" not in s: bad.append(f"{f}: does not say the --role variant is only for a given role")
        if ESCAPE not in s: bad.append(f"{f}: lacks the argument rule '{ESCAPE}'")
        continue
    if len(lines) != 1: bad.append(f"{f}: {len(lines)} 'ade ...' command lines, want exactly 1"); continue
    line = lines[0]
    if not (line == prefix or line.startswith(prefix + " ")): bad.append(f"{f}: runs '{line}', want '{prefix} ...'"); continue
    rest = line[len(prefix):].strip()
    args = re.findall(r'"[^"]*"', rest)
    if re.sub(r'"[^"]*"|--[a-z-]+', "", rest).strip(): bad.append(f"{f}: unquoted argument in '{line}'")
    if len(args) != nargs: bad.append(f"{f}: {len(args)} quoted arguments in '{line}', want {nargs}")
    if nargs and ESCAPE not in s: bad.append(f"{f}: lacks the argument rule '{ESCAPE}'")
    if '--role ""' in s: bad.append(f"{f}: can produce --role \"\"")
    if "--approve" in s or "dangerously-skip-permissions" in s: bad.append(f"{f}: mentions --approve or skipping permissions")
    if name in changes_state and re.search(r"^allowed-tools:", s, re.M):
        bad.append(f"{f}: changes state, so it must not pre-allow tools (the owner's prompt decides)")
extra = sorted(set(os.listdir(f"{P}/commands")) - {n + ".md" for n in want}) if os.path.isdir(f"{P}/commands") else []
if extra: bad.append(f"{P}/commands: unexpected files {extra}")

# AC1 + AC3: the skill exists and its Ask first names the four risky actions.
sk = read(f"{P}/skills/ade/SKILL.md")
ask = section(sk, "Ask first").lower()
for need, pat in [("starting agents", r"start\w*[^.\n]*agent|agent[^.\n]*start"), ("approving tickets", r"approv\w*[^.\n]*ticket"),
                  ("starting a chat orchestrator", r"chat orchestrator"), ("messaging agents", r"messag\w*[^.\n]*agent")]:
    if not re.search(pat, ask): bad.append(f"{P}/skills/ade/SKILL.md: '## Ask first' does not name {need}")
if "--approve" not in sk: bad.append(f"{P}/skills/ade/SKILL.md: does not say never to use --approve for the user")

# AC4: the README's permission block parses as settings JSON with the story's rules.
rd = read(f"{P}/README.md")
blocks = re.findall(r"```json\n(.*?)```", rd, re.S)
if len(blocks) != 1: bad.append(f"{P}/README.md: {len(blocks)} json blocks, want 1 permission block")
else:
    try:
        perm = json.loads(blocks[0]).get("permissions", {})
        rules = {
            "allow": ["Bash(ade status*)", "Bash(ade doctor*)", "Bash(ade agent list*)"],
            "ask": ["Bash(ade work*)", "Bash(ade dispatch*)", "Bash(ade chat*)", "Bash(ade notify*)", "Bash(ade agent add*)", "Bash(ade skills add*)"],
            "deny": ["Bash(*--dangerously-skip-permissions*)"],
        }
        for k, rs in rules.items():
            for r in rs:
                if r not in perm.get(k, []): bad.append(f"{P}/README.md: permissions.{k} lacks {r}")
        for k in ("allow",):
            for r in perm.get(k, []):
                if any(w in r for w in ("work", "dispatch", "chat", "notify", "agent add", "skills add")): bad.append(f"{P}/README.md: {r} must not be allowed")
    except ValueError as e: bad.append(f"{P}/README.md: permission block is not valid JSON ({e})")

# AC5: marketplace lists ade; VERSION has a CHANGELOG entry.
m = json.load(open(".claude-plugin/marketplace.json"))
if not any(p["name"] == "ade" and p["source"] == "./plugins/ade" for p in m["plugins"]): bad.append("marketplace.json does not list ade")
v = open("VERSION").read().strip()
if f"\n## {v}\n" not in open("CHANGELOG.md").read(): bad.append(f"CHANGELOG.md has no '## {v}' entry")
if v == "0.1.0": bad.append("VERSION still 0.1.0: the ade release is not recorded")
if "`ade` plugin" not in open("CHANGELOG.md").read(): bad.append("CHANGELOG.md does not record the ade plugin release")

print("\n".join("FAIL: " + b for b in bad)) if bad else None
sys.exit(1 if bad else 0)
PY
