#!/bin/bash
# check-recipe.sh <recipe.json | connectors folder>: checks connector recipes against format 1 of the contract
# (.ade/context/connectors.md, section 1, with amendment 1).
#   <recipe.json>  one recipe: every single-file rule. When it sits at <root>/plugins/guard/connectors/<service>.json,
#                  a `plugin` recipe is also held to <root>/plugins/<plugin>/hooks/read-tools.txt.
#   <folder>       the connectors folder (<root>/plugins/guard/connectors): every recipe in it, then the rules
#                  "Across files". This is the full check; ade-cli and the guard run it on the folder.
# Exit 0 and no output: valid. Exit 1 and one line on stdout, "<path>: refused: <reason>": refused (a cross-file
# failure refuses the whole folder). Exit 2: usage. Every rule is in the RULES section below and nowhere else.
# Anything unknown (a field, a kind, an answer target, a format) is refused, never ignored; text that would need
# cleaning is refused, not cleaned, and a reason never prints such characters. Reads files only; needs bash, python3.
[ $# -eq 1 ] || { echo "usage: check-recipe.sh <recipe.json | connectors folder>"; exit 2; }
command -v python3 >/dev/null 2>&1 || {
  printf '%s: refused: python3 is needed to check a recipe\n' "$(printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]')"; exit 1; }
python3 -I - "$1" <<'PY'
import json, os, re, stat, sys, unicodedata

path = sys.argv[1]

class Refused(Exception):
    pass

def no(why):
    raise Refused(why)

def safe(v, most=200):
    # For reasons only: a string with every non-ASCII or control character escaped (json's \uXXXX), so a reason never
    # carries a control or invisible character.
    return re.sub(r"[^\x20-\x7e]", "?", json.dumps(str(v), ensure_ascii=True)[1:-1])[:most]

def show(v):
    # A value as JSON (so 1, "1" and true read differently), ASCII only: every other character is escaped.
    try: return re.sub(r"[^\x20-\x7e]", "?", json.dumps(v, ensure_ascii=True))[:120]
    except (TypeError, ValueError): return "?"

# ---------------------------------------------------------------- RULES (format 1, amendment 1)
MAX_BYTES = 64 * 1024
NAME = r"[a-z][a-z0-9-]{0,31}"                      # service, plugin
CONNECTOR = r"[A-Za-z0-9_]{1,40}"                    # sign_in.connector, as in tool names
TOP = {"format", "service", "title", "job", "tier", "state", "held", "sign_in", "questions", "guard", "hosts",
       "pages", "reaches"}
TOP_REQUIRED = TOP - {"held"}
JOBS = {"tickets", "code", "mail", "chat", "files"}
STATES = {"ready", "held"}
KINDS = {"plugin", "cli", "claude-ai"}
SIGN_IN = {"kind", "plugin", "cli", "connector", "admin"}
CLIS = {"gh"}
QUESTION = {"id", "ask", "to"}
TARGETS = {"gate"}
GUARD = {"prefixes", "read", "commands"}
PROGRAMS = {"gh", "git"}
LISTS = {"free", "deny"}
FREE_ENTRY = {"words", "flags", "args"}
ARGS = {"any", "none", "names"}
PAGES = {"docs", "revoke"}
LINE_MAX = 200                                       # held is 200 by the contract; every one-line text the same
TITLE_MAX = 40
BAD_CATEGORIES = {"Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"}
PLUGIN_PREFIX = re.compile(rf"mcp__plugin_({NAME})_([A-Za-z0-9-]{{1,40}})__")
TOOL = re.compile(r"[A-Za-z][A-Za-z0-9_-]{0,127}")
WORD = re.compile(r"[a-z][a-z0-9-]*")                # a free entry's words; a deny word
FLAG = re.compile(r"(-[A-Za-z0-9]+|--[a-z0-9][a-z0-9-]*)(=[A-Za-z0-9._,-]*)?")
DENY_ELEMENT = re.compile(r"[a-z][a-z0-9_-]*|-[A-Za-z0-9]|--[a-z0-9][a-z0-9-]*")   # _ for oauth_token (K6)
HOST = re.compile(r"(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+")
URL = re.compile(r"https://([a-z0-9.-]+)(/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?")
HOOK_FILES = ["plugins/guard/hooks/hooks.json", "plugins/guard/hooks/guard.sh"]

def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)

def one_of(v, allowed):
    return isinstance(v, str) and v in allowed

def text_ok(v, where):
    # Every string in a recipe (keys too): no control, format, surrogate, private-use or unassigned character, and no
    # line or paragraph separator. Refused, never stripped.
    if isinstance(v, dict):
        for k, x in v.items(): text_ok(k, f"{where} key"); text_ok(x, f"{where}.{safe(k, 40)}")
    elif isinstance(v, list):
        for i, x in enumerate(v): text_ok(x, f"{where}[{i}]")
    elif isinstance(v, str):
        for c in v:
            cat = unicodedata.category(c)
            if cat in BAD_CATEGORIES: no(f"{where} holds the character U+{ord(c):04X} (category {cat}), which a recipe may not hold")

def obj(v, where, allowed, required=()):
    if not isinstance(v, dict): no(f"{where} is not an object")
    extra = sorted(set(v) - set(allowed))
    if extra: no(f"{where} has an unknown field {show(extra[0])}")
    for k in sorted(required):
        if k not in v: no(f"{where} has no {show(k)}")
    return v

def line(v, where, most=LINE_MAX):
    if not isinstance(v, str) or not v.strip(): no(f"{where} is not a non-empty string")
    if len(v) > most: no(f"{where} is longer than {most} characters")
    return v

def names(v, where, pattern):
    if not isinstance(v, list): no(f"{where} is not a list")
    for x in v:
        if not isinstance(x, str) or not pattern.fullmatch(x): no(f"{where} has an entry that is not allowed: {show(x)}")
    if len(v) != len(set(v)): no(f"{where} names an entry twice")
    return v

def check_commands(c):
    obj(c, "guard.commands", PROGRAMS)
    for prog, v in c.items():
        obj(v, f"guard.commands.{prog}", LISTS, LISTS)
        if not isinstance(v["free"], list): no(f"guard.commands.{prog}.free is not a list")
        seen = set()
        for i, e in enumerate(v["free"]):
            where = f"guard.commands.{prog}.free[{i}]"
            obj(e, where, FREE_ENTRY, FREE_ENTRY)
            w = e["words"]
            if not isinstance(w, list) or not 1 <= len(w) <= 3: no(f"{where}.words is not a list of 1 to 3 words")
            names(w, f"{where}.words", WORD)
            if tuple(w) in seen: no(f"{where}.words {show(w)} is listed twice for {prog}")
            seen.add(tuple(w))
            f = e["flags"]
            if not isinstance(f, list): no(f"{where}.flags is not a list")
            for x in f:
                if not isinstance(x, str) or not (x == "-" or FLAG.fullmatch(x)): no(f"{where}.flags has an entry that is not a flag: {show(x)}")
            if len(f) != len(set(f)): no(f"{where}.flags names a flag twice")
            if not one_of(e["args"], ARGS): no(f"{where}.args {show(e['args'])} is not one of {sorted(ARGS)}")
        if not isinstance(v["deny"], list): no(f"guard.commands.{prog}.deny is not a list")
        for i, run in enumerate(v["deny"]):
            where = f"guard.commands.{prog}.deny[{i}]"
            if not isinstance(run, list) or not 1 <= len(run) <= 4: no(f"{where} is not a run of 1 to 4 elements")
            names(run, where, DENY_ELEMENT)

def check(r, service_from_file, root):
    text_ok(r, "the recipe")
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
    if kind == "claude-ai" and "plugin" in s and s["plugin"] != r["service"]: no("sign_in.plugin of a claude-ai recipe is not its service")
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
    pre = names(g["prefixes"], "guard.prefixes", re.compile(r".+"))
    read = names(g["read"], "guard.read", TOOL)
    if kind == "plugin":
        for p in pre:
            if not PLUGIN_PREFIX.fullmatch(p): no(f"guard.prefixes entry {show(p)} is not mcp__plugin_<p>_<s>__ (a plugin recipe carries plugin prefixes only)")
        if f"mcp__plugin_{s['plugin']}_{s['plugin']}__" not in pre:
            no(f"guard.prefixes does not hold the plugin's own mcp__plugin_{s['plugin']}_{s['plugin']}__")
    if kind == "claude-ai" and pre != [f"mcp__claude_ai_{s['connector']}__"]:
        no(f"guard.prefixes of a claude-ai recipe must be exactly [\"mcp__claude_ai_{s['connector']}__\"]")
    if kind == "cli":
        if pre: no("guard.prefixes of a cli recipe must be []")
        if read: no("guard.read of a cli recipe must be []")
        if "commands" not in g: no("guard.commands is required for kind cli")
        check_commands(g["commands"])
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

def across(recipes, root, plugin=None):
    # recipes: {service: recipe}, each already valid on its own. A failure here refuses the whole folder. root: the
    # checkout, in the repo layout; plugin: the guard plugin folder holding connectors/ (an installed copy, K6).
    for key in ["connector", "plugin"]:
        seen = {}
        for s, r in sorted(recipes.items()):
            v = r["sign_in"].get(key)
            if v is None: continue
            if v in seen: no(f"sign_in.{key} {show(v)} is in both {seen[v]} and {s}")
            seen[v] = s
    pre = [(p, s) for s, r in sorted(recipes.items()) for p in r["guard"]["prefixes"]]
    for p, s in pre:
        for q, t in pre:
            if s != t and q.startswith(p): no(f"the prefix {p} of {s} equals or starts the prefix {q} of {t}")
    for prog in sorted(PROGRAMS):
        have = [s for s, r in sorted(recipes.items()) if prog in r["guard"].get("commands", {})]
        if len(have) > 1: no(f"guard.commands.{prog} is in more than one recipe: {', '.join(have)}")
    if root is not None:
        missing = [f for f in HOOK_FILES if not os.path.isfile(os.path.join(root, f))]
    elif plugin is not None:   # outside the repo layout (an installed plugin): its own hooks/ folder
        missing = [f for f in ("hooks/hooks.json", "hooks/guard.sh") if not os.path.isfile(os.path.join(plugin, f))]
    else:
        missing = HOOK_FILES
    ready = [s for s, r in sorted(recipes.items()) if r["state"] == "ready"]
    if missing and ready:
        no(f"{', '.join(ready)} {'is' if len(ready) == 1 else 'are'} ready, but this checkout has no {missing[0]} "
           "(a recipe is never ready without the guard's hook)")
# ---------------------------------------------------------------- end of RULES

def no_dupes(pairs):
    seen = {}
    for k, v in pairs:
        if k in seen: raise Refused(f"the key {show(k)} appears twice")
        seen[k] = v
    return seen

def load(p):
    # A regular file, opened without following a link and without blocking (a FIFO), checked on the open file.
    if not p.endswith(".json"): no("the file name does not end in .json")
    try: fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
    except OSError as e: no("is a symlink" if os.path.islink(p) else f"cannot be opened ({safe(e.strerror or '', 60)})")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode): no("is not a regular file")
        if st.st_size > MAX_BYTES: no("the file is over 64 KiB")
        with os.fdopen(fd, "rb", closefd=False) as f: raw = f.read(MAX_BYTES + 1)
    finally:
        os.close(fd)
    if len(raw) > MAX_BYTES: no("the file is over 64 KiB")
    try: text = raw.decode("utf-8")
    except UnicodeDecodeError: no("is not UTF-8")
    try: return json.loads(text, object_pairs_hook=no_dupes, parse_constant=lambda c: no(f"holds {c}, which is not JSON"))
    except RecursionError: no("is nested too deeply")
    except ValueError as e: no(f"is not JSON ({safe(str(e), 80)})")

def layout_root(full_dir):
    parts = full_dir.split(os.sep)
    return os.sep.join(parts[:-3]) if parts[-3:] == ["plugins", "guard", "connectors"] else None

def check_file(p, root):
    try:
        r = load(p)
        check(r, os.path.basename(p)[:-len(".json")], root)
        return r
    except Refused as e:
        raise Refused(f"{safe(p, 400)}: refused: {e}")

try:
    try:
        full = os.path.abspath(path)
        if os.path.isdir(full) and not os.path.islink(full):
            root = layout_root(full)
            if os.path.islink(os.path.dirname(full)) or (root and os.path.islink(os.path.join(root, "plugins", "guard"))): no("the folder is reached through a symlink")
            entries = sorted(os.listdir(full))
            if not entries: no("holds no recipe")
            recipes = {}
            for n in entries:
                f = os.path.join(full, n)
                if not n.endswith(".json"): no(f"{show(n)} is not a recipe (only <service>.json belongs here)")
                recipes[n[:-5]] = check_file(f, root)
            across(recipes, root, os.path.dirname(full))
        elif os.path.islink(full) and os.path.isdir(full):
            no("the folder is a symlink")
        else:
            d = os.path.dirname(full)
            root = layout_root(d)
            if root is not None and os.path.islink(d): no("plugins/guard/connectors is a symlink")
            check_file(full, root)
    except Refused as e:
        m = str(e)
        raise Refused(m if ": refused: " in m else f"{safe(path, 400)}: refused: {m}")
except Refused as e:
    print(e)
    sys.exit(1)
except Exception as e:  # a rule that could not be applied refuses, it never passes
    print(f"{safe(path, 400)}: refused: it could not be checked ({type(e).__name__})")
    sys.exit(1)
PY
