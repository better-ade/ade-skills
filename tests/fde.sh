#!/bin/bash
# Stories F1a and F1b checks for the fde plugin (files only, no model calls). Usage: tests/fde.sh [repo-root]
# (default: this repo). Called by tests/run.sh; exit 0 = pass. tests/meta.sh holds a negative case for each rule.
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
BLANK = r"\[\[TO FILL:[^\]]*\]\]"

COMMERCIAL = ["proposal", "sow", "change-request"]
SKILLS = ["discovery"] + COMMERCIAL
HEADS = {
    "discovery": ["Goals", "Stakeholders", "Current state", "Constraints", "Approved AI providers",
                  "Approved tools and destinations", "Data boundaries"],
    "proposal": ["Pricing", "Timeline"], "sow": ["Acceptance criteria", "Pricing", "Timeline", "Change process", "Terms"],
    "change-request": ["Pricing", "Timeline"],
}
FIRST = "Read `<folder>/docs/customer/constraints.md` first. If it is missing, stop and point the user to `discovery`."
# Exact lines every fde SKILL.md carries (as a line or a bullet).
LINES = [
    "Outside the blanks, write no price, date, duration or legal term, even when quoting the customer; quote it as `[[TO FILL: customer asked: …]]`.",
    "A provider counts only if its bullet names a provider and a written approval in `Source:`; placeholders, `unknown` or an empty section mean none; use it only for the data it is approved for.",
    "A `<slug>` uses only `a-z`, `0-9` and `-`.",
    "If the current folder has no `docs/customer/` and is not a customer folder, ask which folder to use.",
]
ASK = {
    "send": "- Sending or sharing the document with anyone (the customer, a partner, a shared drive): ask the user before each one.",
    "sign": "- Signing, or asking someone to sign: never do it; the owner signs.",
    "export": "- Exporting the document (PDF, Word, a wiki, another tool): only to a target listed in `docs/customer/constraints.md`, section `## Approved tools and destinations`, and ask first; a missing or empty section means no export.",
    "outside": "- Writing outside the named folder: ask first.",
}
ASK_FOR = {n: ["send", "sign", "export", "outside"] for n in SKILLS}
MONTH = r"jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sep(t(ember)?)?|oct(ober)?|nov(ember)?|dec(ember)?"
NUM = r"\d+|one|two|three|four|five|six|seven|eight|nine|ten|thirty|sixty|ninety"
LEAKS = [
    (r"[$€£¥₱₹]\s?\d", "a price"), (r"\b(usd|eur|gbp|cad|php|aud|sgd|inr|jpy)\s?\d", "a price"),
    (r"\d[\d,.]*\s?[km]?\s?(usd|eur|gbp|cad|php|aud|sgd|inr|jpy|dollars?|euros?|pesos?)\b", "a price"),
    (r"\bnet\s?\d+", "a payment term"),
    (r"\d{4}-\d{2}-\d{2}", "a date"), (r"\d{1,2}/\d{1,2}/\d{2,4}", "a date"), (r"\bq[1-4]\b", "a date"),
    (rf"\b({MONTH})\.?\s+\d", "a date"), (rf"\d(st|nd|rd|th)?\s+({MONTH})\b", "a date"),
    (rf"\b({NUM})[\s-]?(business\s)?(day|week|month|year|sprint|quarter)s?\b", "a duration"),
]
LEGAL = ["liability", "indemn", "governing law", "warranty", "termination for", "penalty"]
ONLY_BLANKS = {"proposal": ["Pricing"], "sow": ["Pricing", "Terms", "Change process"], "change-request": ["Pricing"]}
PLACE = "(name the system and its owner; never a credential, key, URL with a token, or internal host)"
CR = "the requested change, without prices or dates"

pj = os.path.join(P, ".claude-plugin/plugin.json")
if os.path.exists(pj) and "document" not in json.load(open(pj)).get("keywords", []): bad.append(f"{rel(pj)}: keywords lack 'document'")
for name in SKILLS:
    f = os.path.join(P, "skills", name, "SKILL.md"); s = read(f)
    t = os.path.join(P, "skills", name, "template.md"); tm = read(t)
    if s:
        stripped = {re.sub(r"^\s*(- )?", "", l).rstrip() for l in s.splitlines()}
        # F1a AC2, review 5: the constraints-first rule is the first non-blank line after the title.
        if name != "discovery":
            body = s.split("\n# ", 1)[1].splitlines()[1:] if "\n# " in s else []
            nb = [l for l in body if l.strip()]
            if not nb or nb[0].strip() != FIRST: bad.append(f"{rel(f)}: the first line after the title is not '{FIRST}'")
        if name == "discovery":
            if "docs/customer/constraints.md" not in s: bad.append(f"{rel(f)}: does not say it writes docs/customer/constraints.md")
            if "gitleaks dir docs/customer/constraints.md" not in s: bad.append(f"{rel(f)}: does not run gitleaks on the file it writes")
        # Review 4, 7, 9: exact lines.
        for l in LINES:
            if l not in stripped: bad.append(f"{rel(f)}: lacks the line '{l}'")
        if name == "change-request" and CR not in s: bad.append(f"{rel(f)}: does not say '{CR}'")
        # F1a AC6, review 6 and 8: exact Ask first bullets.
        ask = {l.rstrip() for l in (section(s, "Ask first") or "").splitlines()}
        for k in ASK_FOR[name]:
            if ASK[k] not in ask: bad.append(f"{rel(f)}: '## Ask first' lacks the {k} bullet '{ASK[k]}'")
    for h in HEADS[name]:
        if tm and section(tm, h) is None: bad.append(f"{rel(t)}: no '## {h}'")
    if name == "discovery" and tm:
        # Review 10 and 7.
        for h in ["Current state", "Constraints", "Data boundaries"]:
            if PLACE not in (section(tm, h) or ""): bad.append(f"{rel(t)}: '## {h}' lacks the placeholder note '{PLACE}'")
        if "(none listed" in tm: bad.append(f"{rel(t)}: has an inline '(none listed...)' note; the skill's provider rule decides")
    if name in COMMERCIAL and tm:
        # F1a AC3, review 1: no price, date, duration or payment term anywhere in a commercial template.
        for i, l in enumerate(tm.splitlines(), 1):
            for pat, what in LEAKS:
                if re.search(pat, l, re.I): bad.append(f"{rel(t)}:{i}: {what} ('{l.strip()}'); leave it as a [[TO FILL: ...]] blank"); break
        # Review 2: no legal term outside the blanks.
        outside = re.sub(BLANK, "", tm).lower()
        for k in LEGAL:
            if k in outside: bad.append(f"{rel(t)}: legal term '{k}' outside a [[TO FILL: ...]] blank")
        # F1a AC4: blanks in Pricing, Timeline and (sow) Terms.
        for h in ["Pricing", "Timeline"] + (["Terms"] if name == "sow" else []):
            if "[[TO FILL:" not in (section(tm, h) or ""): bad.append(f"{rel(t)}: '## {h}' has no [[TO FILL: ...]] blank")
        # Review 2 and 3: these sections hold only blanks.
        for h in ONLY_BLANKS[name]:
            sec = section(tm, h)
            if sec is not None and not re.fullmatch(r"[\s|]*", re.sub(BLANK, "", sec)):
                bad.append(f"{rel(t)}: '## {h}' must hold only [[TO FILL: ...]] blanks")
    if name == "change-request" and tm and CR not in (section(tm, "Change") or ""):
        bad.append(f"{rel(t)}: '## Change' does not say '{CR}'")
# F1a AC5: sow acceptance criteria, one per line, each provable.
st = os.path.join(P, "skills/sow/template.md")
ac = ((section(open(st).read(), "Acceptance criteria") if os.path.exists(st) else "") or "").lower()
if "one criterion per line" not in ac or "test or recorded evidence" not in ac:
    bad.append("plugins/fde/skills/sow/template.md: '## Acceptance criteria' does not say one criterion per line, each provable by a test or recorded evidence")
# F1a AC7: marketplace and release.
m = json.load(open(os.path.join(R, ".claude-plugin/marketplace.json")))
if not any(p["name"] == "fde" and p["source"] == "./plugins/fde" for p in m["plugins"]): bad.append("marketplace.json does not list fde")
if "`fde` plugin" not in open(os.path.join(R, "CHANGELOG.md")).read(): bad.append("CHANGELOG.md does not record the fde plugin release")
print("\n".join("FAIL: " + b for b in bad)) if bad else None
sys.exit(1 if bad else 0)
PY
