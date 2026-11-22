#!/bin/bash
# check-recipe.sh <recipe.json>: checks one connector recipe against format 1 of the contract
# (.ade/context/connectors.md, section 1). Exit 0 and no output: the recipe is valid. Exit 1 and one line on stdout,
# "<file>: <reason>": it is refused. Exit 2: usage. Every rule is in the RULES section below and nowhere else; ade-cli
# and the guard run this same file. Anything unknown (a field, a kind, an answer target, a format) is refused, never
# ignored. When the recipe sits at <root>/plugins/guard/connectors/<service>.json, a `plugin` recipe is also held to
# <root>/plugins/<plugin>/hooks/read-tools.txt. Reads files only; needs bash and python3.
[ $# -eq 1 ] || { echo "usage: check-recipe.sh <recipe.json>"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "$1: refused: python3 is needed to check a recipe"; exit 1; }
python3 -I - "$1" <<'PY'
import json, os, re, sys

path = sys.argv[1]

class Refused(Exception):
    pass

def clean(v, most=120):
    # Printed text loses control characters.
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", "", str(v))[:most]

def no(why):
    raise Refused(why)

# ---------------------------------------------------------------- RULES (format 1)
MAX_BYTES = 64 * 1024
NAME = r"[a-z][a-z0-9-]{0,31}"                      # service, plugin
CONNECTOR = r"[A-Za-z0-9_]{1,40}"                    # sign_in.connector, as in tool names
TOP = {"format", "service", "title", "job", "tier", "state", "held", "sign_in", "questions", "guard", "hosts",
       "pages", "reaches"}
TOP_REQUIRED = TOP - {"held"}
JOBS = {"tickets", "code", "mail", "chat"}
STATES = {"ready", "held"}
KINDS = {"plugin", "cli", "claude-ai"}
SIGN_IN = {"kind", "plugin", "cli", "connector", "admin"}
CLIS = {"gh"}
QUESTION = {"id", "ask", "to"}
TARGETS = {"gate"}
GUARD = {"prefixes", "read", "commands"}
PROGRAMS = {"gh", "git"}
LISTS = {"free", "deny"}
PAGES = {"docs", "revoke"}
LINE_MAX = 200                                       # held is 200 by the contract; every one-line text the same
TITLE_MAX = 40
PLUGIN_PREFIX = re.compile(rf"mcp__plugin_({NAME})_([A-Za-z0-9-]{{1,40}})__")
CLAUDE_AI_PREFIX = re.compile(rf"mcp__claude_ai_({CONNECTOR})__")
TOOL = re.compile(r"[A-Za-z][A-Za-z0-9_-]{0,127}")
WORD = re.compile(r"-{0,2}[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
HOST = re.compile(r"(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+")
URL = re.compile(r"https://([a-z0-9.-]+)(/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?")

def show(v):
    # A value as JSON, so 1, "1" and true read differently.
    try: return clean(json.dumps(v, ensure_ascii=False))
    except (TypeError, ValueError): return clean(v)

def one_of(v, allowed):
    return isinstance(v, str) and v in allowed

def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)

def obj(v, where, allowed, required=()):
    if not isinstance(v, dict): no(f"{where} is not an object")
    extra = sorted(set(v) - set(allowed))
    if extra: no(f"{where} has an unknown field {show(extra[0])}")
    for k in sorted(required):
        if k not in v: no(f"{where} has no {show(k)}")
    return v

def line(v, where, most=LINE_MAX):
    if not isinstance(v, str) or not v.strip(): no(f"{where} is not a non-empty string")
    if re.search(r"[\x00-\x1f\x7f-\x9f]", v): no(f"{where} is not one printable line")
    if len(v) > most: no(f"{where} is longer than {most} characters")
    return v

def names(v, where, pattern):
    if not isinstance(v, list): no(f"{where} is not a list")
    for x in v:
        if not isinstance(x, str) or not pattern.fullmatch(x): no(f"{where} has an entry that is not allowed: {show(x)}")
    if len(v) != len(set(v)): no(f"{where} names an entry twice")
    return v

def check(r, service_from_file, root):
    obj(r, "the recipe", TOP, TOP_REQUIRED)
    if not is_int(r["format"]) or r["format"] != 1: no(f"format is {show(r['format'])}; only 1 is known")
    if not isinstance(r["service"], str) or not re.fullmatch(NAME, r["service"]): no("service is not a name ^[a-z][a-z0-9-]{0,31}$")
    if r["service"] != service_from_file: no(f"service {show(r['service'])} is not the file name {show(service_from_file)}")
    line(r["title"], "title", TITLE_MAX)
    if not one_of(r["job"], JOBS): no(f"job {show(r['job'])} is not one of {sorted(JOBS)}")
    if not is_int(r["tier"]) or not 0 <= r["tier"] <= 4: no(f"tier {show(r['tier'])} is not 0 to 4")
    if not one_of(r["state"], STATES): no(f"state {show(r['state'])} is not one of {sorted(STATES)}")
    if r["state"] == "held": line(r.get("held"), "held")
    elif "held" in r: no("held is set, but state is not held")

    s = obj(r["sign_in"], "sign_in", SIGN_IN, {"kind"})
    kind = s["kind"]
    if not one_of(kind, KINDS): no(f"sign_in.kind {show(kind)} is not one of {sorted(KINDS)}")
    if "plugin" in s and (not isinstance(s["plugin"], str) or not re.fullmatch(NAME, s["plugin"])): no("sign_in.plugin is not a plugin name")
    if kind == "plugin" and "plugin" not in s: no("sign_in.plugin is required for kind plugin")
    if kind == "cli":
        if not one_of(s.get("cli"), CLIS): no(f"sign_in.cli {show(s.get('cli'))} is not one of {sorted(CLIS)}")
    elif "cli" in s: no("sign_in.cli is only for kind cli")
    if kind == "claude-ai":
        if not isinstance(s.get("connector"), str) or not re.fullmatch(CONNECTOR, s["connector"]): no("sign_in.connector is not a connector name ^[A-Za-z0-9_]{1,40}$")
    elif "connector" in s: no("sign_in.connector is only for kind claude-ai")
    if "admin" in s: line(s["admin"], "sign_in.admin")
    if r["tier"] == 4 and "admin" not in s: no("sign_in.admin is required for tier 4")

    q = r["questions"]
    if not isinstance(q, list): no("questions is not a list")
    if len(q) > 2: no("questions has more than 2 entries")
    ids = []
    for i, x in enumerate(q):
        obj(x, f"questions[{i}]", QUESTION, QUESTION)
        if not isinstance(x["id"], str) or not re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", x["id"]): no(f"questions[{i}].id is not a name")
        line(x["ask"], f"questions[{i}].ask")
        if not one_of(x["to"], TARGETS): no(f"questions[{i}].to {show(x['to'])} is not a known answer target ({sorted(TARGETS)})")
        ids.append(x["id"])
    if len(ids) != len(set(ids)): no("questions has an id twice")

    g = obj(r["guard"], "guard", GUARD, {"prefixes", "read"})
    pre = names(g["prefixes"], "guard.prefixes", re.compile(r".*"))
    for p in pre:
        if not (PLUGIN_PREFIX.fullmatch(p) or CLAUDE_AI_PREFIX.fullmatch(p)):
            no(f"guard.prefixes entry {show(p)} is not mcp__plugin_<p>_<s>__ or mcp__claude_ai_<Name>__")
    if kind == "plugin" and f"mcp__plugin_{s['plugin']}_{s['plugin']}__" not in pre:
        no(f"guard.prefixes does not hold the plugin's own mcp__plugin_{s['plugin']}_{s['plugin']}__")
    if kind == "claude-ai" and f"mcp__claude_ai_{s['connector']}__" not in pre:
        no(f"guard.prefixes does not hold the connector's own mcp__claude_ai_{s['connector']}__")
    read = names(g["read"], "guard.read", TOOL)
    if read and not pre: no("guard.read names tools, but guard.prefixes is empty")
    if kind == "cli":
        if "commands" not in g: no("guard.commands is required for kind cli")
        c = obj(g["commands"], "guard.commands", PROGRAMS)
        for prog, v in c.items():
            obj(v, f"guard.commands.{prog}", LISTS, LISTS)
            for lst in sorted(LISTS):
                if not isinstance(v[lst], list): no(f"guard.commands.{prog}.{lst} is not a list")
                for e in v[lst]:
                    if not isinstance(e, list) or not e: no(f"guard.commands.{prog}.{lst} has an entry that is not a non-empty argument list")
                    names(e, f"guard.commands.{prog}.{lst} entry", WORD)
    elif "commands" in g: no("guard.commands is only for kind cli")

    names(r["hosts"], "hosts", HOST)
    pg = obj(r["pages"], "pages", PAGES)
    for k, u in pg.items():
        if not isinstance(u, str) or not URL.fullmatch(u) or not HOST.fullmatch(URL.fullmatch(u).group(1)):
            no(f"pages.{k} is not a plain https address")
    line(r["reaches"], "reaches")

    # The plugin's shipped read list is the read list (only where the repo layout says which plugin folder it is).
    if kind == "plugin" and root is not None:
        rt = os.path.join(root, "plugins", s["plugin"], "hooks", "read-tools.txt")
        if os.path.isdir(os.path.join(root, "plugins", s["plugin"])):
            try: want = [l.split("#", 1)[0].strip() for l in open(rt, encoding="utf-8")]
            except OSError: no(f"plugins/{s['plugin']} has no hooks/read-tools.txt")
            want = [w for w in want if w]
            if sorted(read) != sorted(want): no(f"guard.read is not exactly the names in plugins/{s['plugin']}/hooks/read-tools.txt")
        else:
            if r["state"] != "held": no(f"state is ready, but plugins/{s['plugin']} does not exist")
            if read: no(f"guard.read names tools, but plugins/{s['plugin']} (and its read-tools.txt) does not exist")
# ---------------------------------------------------------------- end of RULES

def no_dupes(pairs):
    seen = {}
    for k, v in pairs:
        if k in seen: raise Refused(f"the key {show(k)} appears twice")
        seen[k] = v
    return seen

try:
    if not path.endswith(".json"): no("the file name does not end in .json")
    try:
        if os.path.getsize(path) > MAX_BYTES: no("the file is over 64 KiB")
        raw = open(path, "rb").read(MAX_BYTES + 1)
    except OSError: no("cannot be read")
    if len(raw) > MAX_BYTES: no("the file is over 64 KiB")
    try: text = raw.decode("utf-8")
    except UnicodeDecodeError: no("is not UTF-8")
    try: recipe = json.loads(text, object_pairs_hook=no_dupes,
                             parse_constant=lambda c: no(f"holds {c}, which is not JSON"))
    except ValueError as e: no(f"is not JSON ({clean(e)})")
    full = os.path.abspath(path)
    parts = full.split(os.sep)
    root = os.sep.join(parts[:-4]) if parts[-4:-1] == ["plugins", "guard", "connectors"] else None
    check(recipe, os.path.basename(path)[:-len(".json")], root)
except Refused as e:
    print(clean(f"{path}: refused: {e}", 1000))
    sys.exit(1)
except Exception as e:  # a rule that could not be applied refuses, it never passes
    print(clean(f"{path}: refused: it could not be checked ({type(e).__name__})", 1000))
    sys.exit(1)
PY
