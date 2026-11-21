#!/bin/bash
# Story N1 checks for the notes plugin (files only, no model calls). Called by tests/run.sh; exit 0 = pass.
cd "$(dirname "$0")/.." || exit 1
python3 - <<'PY'
import json, os, re, sys
bad = []
P = "plugins/notes"
def read(p):
    try: return open(p).read()
    except OSError: bad.append(f"{p}: missing"); return ""
def section(s, h):
    m = re.search(rf"^## {re.escape(h)}\n(.*?)(?=^## |\Z)", s, re.S | re.M)
    return m.group(1) if m else ""

pj = json.load(open(f"{P}/.claude-plugin/plugin.json")) if os.path.exists(f"{P}/.claude-plugin/plugin.json") else {}
if "document" not in pj.get("keywords", []): bad.append(f"{P}: plugin.json keywords lack 'document' (docs.sh would skip it)")

# AC2 + AC4: five skills; each Ask first names sending or sharing a note, creating tickets, writing outside the folder.
for name in ["meeting-notes", "summarize", "action-items", "digest", "capture"]:
    f = f"{P}/skills/{name}/SKILL.md"; s = read(f)
    if not s: continue
    if not s.startswith(f"---\nname: {name}\n"): bad.append(f"{f}: front matter name is not {name}")
    ask = section(s, "Ask first").lower()
    for need, pat in [("sending or sharing a note", r"(send|shar)\w*[^.\n]*note"), ("creating tickets", r"creat\w*[^.\n]*ticket"),
                      ("writing outside the named folder", r"writ\w*[^.\n]*outside the named folder")]:
        if not re.search(pat, ask): bad.append(f"{f}: '## Ask first' does not name {need}")

# AC5: the two templates and their headings (docs.sh checks the Source: lines).
for name, heads in [("meeting-notes", ["Decisions", "Action items", "Open questions"]), ("summarize", ["Summary"])]:
    t = read(f"{P}/skills/{name}/template.md")
    for h in heads:
        if not re.search(rf"^## {h}$", t, re.M): bad.append(f"{P}/skills/{name}/template.md: no '## {h}'")
    if t and not re.search(r"^\s*- ", t, re.M): bad.append(f"{P}/skills/{name}/template.md: no example bullet")

# AC6: digest reads only the named folder unless the owner asks for a hub-wide digest.
d = read(f"{P}/skills/digest/SKILL.md")
if "Read only the named folder" not in d or "hub-wide digest" not in d:
    bad.append(f"{P}/skills/digest/SKILL.md: does not say it reads only the named folder unless the owner asks for a hub-wide digest")

# AC7: conventions, marketplace, release.
c = read("docs/conventions.md")
for need in ["notes/YYYY-MM-DD-<slug>.md", "## Approved AI providers", "skills/<name>/template.md", "Source:", '"document"']:
    if c and need not in c: bad.append(f"docs/conventions.md: does not record {need}")
m = json.load(open(".claude-plugin/marketplace.json"))
if not any(p["name"] == "notes" and p["source"] == "./plugins/notes" for p in m["plugins"]): bad.append("marketplace.json does not list notes")
if "`notes` plugin" not in open("CHANGELOG.md").read(): bad.append("CHANGELOG.md does not record the notes plugin release")

print("\n".join("FAIL: " + b for b in bad)) if bad else None
sys.exit(1 if bad else 0)
PY
