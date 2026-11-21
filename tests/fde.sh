#!/bin/bash
# Stories F1a and F1b checks for the fde plugin (files only, no model calls). Usage: tests/fde.sh [repo-root]
# (default: this repo). Called by tests/run.sh; exit 0 = pass.
R="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
python3 - "$R" <<'PY'
import json, os, re, sys
R = sys.argv[1]; bad = []
P = os.path.join(R, "plugins/fde")
def rel(p): return os.path.relpath(p, R)
def read(p):
    try: return open(p).read()
    except OSError: bad.append(f"{rel(p)}: missing"); return ""
def section(s, h):
    m = re.search(rf"^## {re.escape(h)}\n(.*?)(?=^## |\Z)", s, re.S | re.M)
    return m.group(1) if m else None

COMMERCIAL = ["proposal", "sow", "change-request"]
DELIVERY = ["design-doc", "workflow", "status-report", "handover"]
SKILLS = ["discovery"] + COMMERCIAL + DELIVERY
HEADS = {
    "discovery": ["Goals", "Stakeholders", "Current state", "Constraints", "Approved AI providers", "Data boundaries"],
    "proposal": ["Pricing", "Timeline"], "sow": ["Acceptance criteria", "Pricing", "Timeline", "Terms"],
    "change-request": ["Pricing", "Timeline"],
    "design-doc": ["Context", "Diagram", "Integrations", "Security", "Rollout", "Secrets"],
    "workflow": ["Current process", "Future process"],
    "status-report": ["Done", "Next", "Risks", "Decisions needed"],
    "handover": ["Runbook", "Architecture summary", "Operate and support", "Open issues", "Secrets"],
}
FIRST = "Read `<folder>/docs/customer/constraints.md` first. If it is missing, stop and point the user to `discovery`."
LEAKS = [(r"[$€£]\s?\d", "a price"), (r"\b(USD|EUR|GBP|CAD|PHP)\s?\d", "a price"),
         (r"\d{4}-\d{2}-\d{2}", "a date"), (r"\d+\s?(days|weeks|months)", "a duration")]

pj = os.path.join(P, ".claude-plugin/plugin.json")
if os.path.exists(pj) and "document" not in json.load(open(pj)).get("keywords", []): bad.append(f"{rel(pj)}: keywords lack 'document'")
for name in SKILLS:
    f = os.path.join(P, "skills", name, "SKILL.md"); s = read(f)
    t = os.path.join(P, "skills", name, "template.md"); tm = read(t)
    if s:
        # AC2 (F1a), AC1 (F1b): constraints first, except discovery, which writes them.
        if name != "discovery" and FIRST not in s: bad.append(f"{rel(f)}: lacks the constraints-first line '{FIRST}'")
        if name == "discovery" and "docs/customer/constraints.md" not in s: bad.append(f"{rel(f)}: does not say it writes docs/customer/constraints.md")
        # AC6: Ask first names sending, sharing, signing, exporting; export only to an approved target.
        ask = (section(s, "Ask first") or "").lower()
        for w in ["send", "shar", "export"] + ([] if name in DELIVERY else ["sign"]):
            if w not in ask: bad.append(f"{rel(f)}: '## Ask first' does not name {w}ing a document")
        if not re.search(r"export\w*[^\n]*only[^\n]*(approve|constraints)", ask): bad.append(f"{rel(f)}: '## Ask first' does not limit export to a target the constraints approve")
    for h in HEADS[name]:
        if tm and section(tm, h) is None: bad.append(f"{rel(t)}: no '## {h}'")
    if name in COMMERCIAL and tm:
        # AC3: no price, date or duration in a commercial template.
        for i, l in enumerate(tm.splitlines(), 1):
            for pat, what in LEAKS:
                if re.search(pat, l): bad.append(f"{rel(t)}:{i}: {what} ('{l.strip()}'); leave it as a [[TO FILL: ...]] blank")
        # AC4: blanks in Pricing, Timeline and (sow) Terms.
        for h in ["Pricing", "Timeline"] + (["Terms"] if name == "sow" else []):
            if "[[TO FILL:" not in (section(tm, h) or ""): bad.append(f"{rel(t)}: '## {h}' has no [[TO FILL: ...]] blank")
# F1b AC2-AC4: workflow maps in Mermaid with step tables; status-report reads only the folder; secrets sections.
wf = read(os.path.join(P, "skills/workflow/template.md")) if os.path.isdir(os.path.join(P, "skills/workflow")) else ""
for h in ["Current process", "Future process"]:
    sec = section(wf, h) or ""
    if wf and ("```mermaid" not in sec or not re.search(r"^\|.*\|$", sec, re.M)): bad.append(f"plugins/fde/skills/workflow/template.md: '## {h}' lacks a Mermaid map and a step table")
sr = os.path.join(P, "skills/status-report/SKILL.md")
if os.path.exists(sr) and "Read only the named folder" not in open(sr).read(): bad.append("plugins/fde/skills/status-report/SKILL.md: does not say it reads only the named folder")
for name in ["design-doc", "handover"]:
    t = os.path.join(P, "skills", name, "template.md")
    if os.path.exists(t) and "names and locations only" not in (section(open(t).read(), "Secrets") or "").lower(): bad.append(f"{rel(t)}: '## Secrets' does not say names and locations only")
# F1b AC6: the release.
if os.path.exists(pj) and json.load(open(pj)).get("version") == "0.1.0": bad.append(f"{rel(pj)}: version not bumped for part 2")
if "`status-report`" not in open(os.path.join(R, "CHANGELOG.md")).read(): bad.append("CHANGELOG.md does not record the fde part 2 release")
# AC5: sow acceptance criteria, one per line, each provable.
ac = (section(read(os.path.join(P, "skills/sow/template.md")) if os.path.exists(os.path.join(P, "skills/sow/template.md")) else "", "Acceptance criteria") or "").lower()
if "one criterion per line" not in ac or not re.search(r"test or recorded evidence", ac):
    bad.append("plugins/fde/skills/sow/template.md: '## Acceptance criteria' does not say one criterion per line, each provable by a test or recorded evidence")
# AC7: marketplace and release.
m = json.load(open(os.path.join(R, ".claude-plugin/marketplace.json")))
if not any(p["name"] == "fde" and p["source"] == "./plugins/fde" for p in m["plugins"]): bad.append("marketplace.json does not list fde")
if "`fde` plugin" not in open(os.path.join(R, "CHANGELOG.md")).read(): bad.append("CHANGELOG.md does not record the fde plugin release")
print("\n".join("FAIL: " + b for b in bad)) if bad else None
sys.exit(1 if bad else 0)
PY
