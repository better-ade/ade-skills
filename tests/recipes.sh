#!/bin/bash
# Story K5 checks for the connector recipes (plugins/guard/connectors/<service>.json, format 1 of
# .ade/context/connectors.md). Files and local scripts only: no network, no model calls. Usage: tests/recipes.sh
# [repo-root] (default: this repo); called by tests/run.sh; exit 0 = pass. Each check is named as the story names it.
R="${1:-$(cd "$(dirname "$0")/.." && pwd)}"; rc=0
fail() { echo "FAIL: $*"; rc=1; }
C="$R/plugins/guard/connectors"; CHECK="$R/plugins/guard/scripts/check-recipe.sh"
SERVICES="clickup discord github gmail jira linear outlook slack teams"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# AC1: exactly the nine recipes, each passing every rule of format 1 (the checker), and no two sharing a prefix.
recipes_valid() {
  local s f out have
  have="$(cd "$C" 2>/dev/null && ls | sort | tr '\n' ' ')"
  [ "$have" = "$(for s in $SERVICES; do printf '%s.json ' "$s"; done)" ] || fail "recipes_valid: $C holds '$have', want the nine recipes and nothing else"
  [ -f "$CHECK" ] || { fail "recipes_valid: no checker at plugins/guard/scripts/check-recipe.sh"; return; }
  for s in $SERVICES; do
    f="$C/$s.json"; [ -f "$f" ] || continue
    out="$(bash "$CHECK" "$f")" || fail "recipes_valid: $s: $out"
    [ -z "$out" ] || fail "recipes_valid: $s: the checker printed '$out' for a valid recipe"
  done
  python3 -I - "$C" <<'PY' || rc=1
import glob, json, sys
seen = {}; bad = []
for f in sorted(glob.glob(sys.argv[1] + "/*.json")):
    try: r = json.load(open(f))
    except ValueError: continue
    for p in r.get("guard", {}).get("prefixes", []):
        if p in seen: bad.append(f"prefix {p} is in both {seen[p]} and {r.get('service')}")
        seen[p] = r.get("service")
for b in bad: print("FAIL: recipes_valid: " + b)
sys.exit(1 if bad else 0)
PY
}

# AC2: the checker refuses, with one line, an unknown field (at each level), an unknown sign_in.kind, an unknown answer
# target, a format other than 1, and the file-level faults; it runs on a lone file from anywhere; usage exits 2.
recipes_refuse_unknown() {
  local base="$T/refuse" name out n
  mkdir -p "$base"; cp "$C/gmail.json" "$base/gmail.json" 2>/dev/null || { fail "recipes_refuse_unknown: no gmail recipe to mutate"; return; }
  (cd / && bash "$CHECK" "$base/gmail.json" >/dev/null) || fail "recipes_refuse_unknown: the unchanged gmail recipe, as a lone file, is refused"
  # mutate <name> <python statement on r>: a copy of gmail.json with one change, which must be refused in one line.
  mutate() {
    mkdir -p "$base/$1"; python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); exec(sys.argv[3]); json.dump(r, open(sys.argv[2], "w"))' \
      "$base/gmail.json" "$base/$1/gmail.json" "$2" || { fail "recipes_refuse_unknown: fixture $1 broken"; return; }
    expect "$1" "$3"
  }
  expect() {
    out="$(bash "$CHECK" "$base/$1/gmail.json")" && { fail "recipes_refuse_unknown: the checker passed $1"; return; }
    n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
    [ "$n" = 1 ] && case "$out" in *"refused: "*"$2"*) true;; *) false;; esac \
      || fail "recipes_refuse_unknown: $1: want one line naming '$2', got: $out"
  }
  mutate unknown-field        'r["notes"] = "x"'                          "unknown field \"notes\""
  mutate unknown-sign-in      'r["sign_in"]["client_id"] = "x"'           "unknown field \"client_id\""
  mutate unknown-guard        'r["guard"]["allow"] = ["send_message"]'    "unknown field \"allow\""
  mutate unknown-question     'r["questions"][0]["default"] = "yes"'      "unknown field \"default\""
  mutate unknown-pages        'r["pages"]["home"] = "https://mail.google.com/"' "unknown field \"home\""
  mutate unknown-kind         'r["sign_in"]["kind"] = "proxy"'            "sign_in.kind \"proxy\""
  mutate unknown-target       'r["questions"][0]["to"] = "keychain"'      "to \"keychain\""
  mutate format-2             'r["format"] = 2'                           "format is 2"
  mutate format-string        'r["format"] = "1"'                         "format is \"1\""
  mutate format-true          'r["format"] = True'                        "format is true"
  mutate format-missing       'del r["format"]'                           "no \"format\""
  mutate wrong-type           'r["guard"]["read"] = "get_thread"'         "guard.read is not a list"
  mutate pattern-read         'r["guard"]["read"].append("send_*")'       "not allowed"
  mutate held-when-ready      'r["held"] = "x"'                           "held is set"
  mutate control-char         'r["reaches"] = "a\u001b[31mb"'             "not one printable line"
  mutate three-questions      'r["questions"] *= 3'                       "more than 2"
  mkdir -p "$base/dup-key"; sed 's/"format": 1,/"format": 1, "format": 1,/' "$base/gmail.json" > "$base/dup-key/gmail.json"
  expect dup-key "appears twice"
  mkdir -p "$base/too-big"; python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); s=json.dumps(r); open(sys.argv[2],"w").write(s[:-1] + " " * 70000 + "}")' "$base/gmail.json" "$base/too-big/gmail.json"
  expect too-big "over 64 KiB"
  mkdir -p "$base/not-json"; printf '{"format": 1,' > "$base/not-json/gmail.json"; expect not-json "not JSON"
  mkdir -p "$base/renamed"; cp "$base/gmail.json" "$base/renamed/gmail2.json"
  out="$(bash "$CHECK" "$base/renamed/gmail2.json")" && fail "recipes_refuse_unknown: the checker passed a recipe whose service is not its file name"
  out="$(bash "$CHECK" 2>&1)"; [ $? = 2 ] || fail "recipes_refuse_unknown: the checker without a file does not exit 2"
}

# AC3: tier, state, kind and held reason per service, as the contract's section 2.
recipes_tiers() {
  python3 -I - "$C" <<'PY' || rc=1
import json, sys
C = sys.argv[1]; bad = []
#            tier state    kind         words the held reason must hold
WANT = {"clickup": (0, "ready", "plugin", []), "jira": (0, "ready", "plugin", []), "linear": (0, "ready", "plugin", []),
        "github": (2, "ready", "cli", []), "gmail": (2, "ready", "claude-ai", []),
        "slack": (1, "held", "plugin", ["client id"]), "discord": (3, "held", "plugin", ["K3"]),
        "outlook": (4, "held", "plugin", ["administrator", "legacy"]), "teams": (4, "held", "plugin", ["administrator", "legacy"])}
for s, (tier, state, kind, words) in WANT.items():
    try: r = json.load(open(f"{C}/{s}.json"))
    except (OSError, ValueError): bad.append(f"{s}: no readable recipe"); continue
    got = (r.get("tier"), r.get("state"), r.get("sign_in", {}).get("kind"))
    if got != (tier, state, kind): bad.append(f"{s}: tier, state, kind {got}, want {(tier, state, kind)}")
    for w in words:
        if w not in r.get("held", ""): bad.append(f"{s}: the held reason does not say {w!r}")
    if s == "github" and r.get("sign_in", {}).get("cli") != "gh": bad.append("github: sign_in.cli is not gh")
    if s == "gmail" and r.get("sign_in", {}).get("connector") != "Gmail": bad.append("gmail: sign_in.connector is not Gmail")
    if kind == "plugin" and r.get("sign_in", {}).get("plugin") != s: bad.append(f"{s}: sign_in.plugin is not {s}")
    if r.get("tier") == 4 and not r.get("sign_in", {}).get("admin"): bad.append(f"{s}: tier 4 without sign_in.admin")
for b in bad: print("FAIL: recipes_tiers: " + b)
sys.exit(1 if bad else 0)
PY
}

# AC4: a plugin recipe's read list is exactly its plugin's hooks/read-tools.txt and its prefixes hold the plugin's own;
# every plugin with a read-tools.txt has a recipe; a recipe whose plugin is not in the repo is held with no reads.
# Then, on a copy, changing either side alone (or dropping the prefix) must be refused.
recipes_match_plugins() {
  python3 -I - "$R" <<'PY' || rc=1
import glob, json, os, sys
R = sys.argv[1]; bad = []
recipes = {}
for f in glob.glob(f"{R}/plugins/guard/connectors/*.json"):
    try: r = json.load(open(f)); recipes[r["service"]] = r
    except (ValueError, KeyError): pass
by_plugin = {r["sign_in"].get("plugin"): r for r in recipes.values() if r.get("sign_in", {}).get("kind") == "plugin"}
for rt in glob.glob(f"{R}/plugins/*/hooks/read-tools.txt"):
    p = rt.split(os.sep)[-3]
    if p not in by_plugin: bad.append(f"plugins/{p} has a read list but no plugin recipe names it")
for p, r in by_plugin.items():
    read = r["guard"]["read"]; pre = r["guard"]["prefixes"]
    if f"mcp__plugin_{p}_{p}__" not in pre: bad.append(f"{r['service']}: prefixes {pre} lack mcp__plugin_{p}_{p}__")
    rt = f"{R}/plugins/{p}/hooks/read-tools.txt"
    if os.path.isdir(f"{R}/plugins/{p}"):
        want = [l.split("#", 1)[0].strip() for l in open(rt)]; want = [w for w in want if w]
        if sorted(read) != sorted(want) or len(read) != len(set(read)):
            bad.append(f"{r['service']}: guard.read differs from plugins/{p}/hooks/read-tools.txt "
                       f"(only in recipe {sorted(set(read) - set(want))}, only in plugin {sorted(set(want) - set(read))})")
    elif read or r["state"] != "held":
        bad.append(f"{r['service']}: plugins/{p} is not in the repo, so the recipe must be held with no reads")
for b in bad: print("FAIL: recipes_match_plugins: " + b)
sys.exit(1 if bad else 0)
PY
  # The checker holds the same rule. On a copy of the repo layout: unchanged passes; each one-sided change is refused.
  local M="$T/match" p out
  for p in clickup jira linear; do
    rm -rf "$M"; mkdir -p "$M/plugins/guard/connectors" "$M/plugins/$p/hooks"
    cp "$C/$p.json" "$M/plugins/guard/connectors/"; cp "$R/plugins/$p/hooks/read-tools.txt" "$M/plugins/$p/hooks/"
    bash "$CHECK" "$M/plugins/guard/connectors/$p.json" >/dev/null || fail "recipes_match_plugins: $p: the checker refused an unchanged copy"
    echo "brand_new_write_tool" >> "$M/plugins/$p/hooks/read-tools.txt"
    out="$(bash "$CHECK" "$M/plugins/guard/connectors/$p.json")" && fail "recipes_match_plugins: $p: the checker passed a read-tools.txt with a name the recipe lacks"
    cp "$R/plugins/$p/hooks/read-tools.txt" "$M/plugins/$p/hooks/"
    python3 -I -c 'import json,sys; f=sys.argv[1]; r=json.load(open(f)); r["guard"]["read"].append("brand_new_write_tool"); json.dump(r,open(f,"w"))' "$M/plugins/guard/connectors/$p.json"
    out="$(bash "$CHECK" "$M/plugins/guard/connectors/$p.json")" && fail "recipes_match_plugins: $p: the checker passed a recipe read name the plugin lacks"
    cp "$C/$p.json" "$M/plugins/guard/connectors/"
    python3 -I -c 'import json,sys; f=sys.argv[1]; r=json.load(open(f)); r["guard"]["read"].pop(); json.dump(r,open(f,"w"))' "$M/plugins/guard/connectors/$p.json"
    out="$(bash "$CHECK" "$M/plugins/guard/connectors/$p.json")" && fail "recipes_match_plugins: $p: the checker passed a recipe missing one of the plugin's reads"
    cp "$C/$p.json" "$M/plugins/guard/connectors/"
    python3 -I -c 'import json,sys; f=sys.argv[1]; r=json.load(open(f)); r["guard"]["prefixes"]=["mcp__plugin_other_other__"]; json.dump(r,open(f,"w"))' "$M/plugins/guard/connectors/$p.json"
    out="$(bash "$CHECK" "$M/plugins/guard/connectors/$p.json")" && fail "recipes_match_plugins: $p: the checker passed a recipe without the plugin's own prefix"
  done
}

# AC5: no secret, client id, tenant, account, workspace or person name. Format 1 has no field for one (the checker
# refuses unknown keys, recipes_refuse_unknown); here every value is scanned for the shapes they take.
recipes_no_secret() {
  if command -v gitleaks >/dev/null; then
    gitleaks dir "$C" --no-banner --redact --log-level warn >/dev/null 2>&1 || fail "recipes_no_secret: gitleaks found a secret in plugins/guard/connectors"
  else echo "note: gitleaks not installed, recipes_no_secret relies on its own patterns"; fi
  python3 -I - "$C" <<'PY' || rc=1
import glob, json, re, sys
PATTERNS = [
    ("a GitHub token", r"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})"),
    ("a Linear key", r"\blin_(api|oauth)_[A-Za-z0-9]{20,}"),
    ("a ClickUp token", r"\bpk_\d+_[A-Z0-9]{20,}"),
    ("an Atlassian token", r"\bATATT[A-Za-z0-9_\-=]{20,}"),
    ("a Slack token", r"\bxox[abposr]-[A-Za-z0-9-]{10,}"),
    ("a Google client id or key", r"\.apps\.googleusercontent\.com|\bAIza[0-9A-Za-z_\-]{20,}|\bGOCSPX-"),
    ("a bearer value", r"(?i)bearer\s+[A-Za-z0-9._\-]{16,}"),
    ("a long secret-like string", r"\b(?=[A-Za-z0-9+/]*\d)[A-Za-z0-9+/]{40,}"),
    ("a GUID (a tenant or client id)", r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"),
    ("a Slack app or client id", r"\b\d{6,}\.\d{6,}\b|\bA0[A-Z0-9]{8,}\b"),
    ("a long number (an account, workspace or app id)", r"\b\d{7,}\b"),
    ("a tenant in an address", r"(?i)/tenants?/|\{tenant"),
    ("an email address", r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+\.[A-Za-z]{2,}\b"),
    ("an Atlassian site", r"\b[a-z0-9\-]+\.atlassian\.net\b"),
    ("a Slack workspace", r"\b(?!mcp\b|docs\b|api\b|app\b)[a-z0-9\-]+\.slack\.com\b"),
    ("a ClickUp workspace link", r"app\.clickup\.com/(t/)?\d"),
    ("a Linear workspace link", r"linear\.app/(?!docs\b)[a-z0-9\-]+/"),
    ("a GitHub owner or repo link", r"github\.com/(?!settings\b|login\b)[A-Za-z0-9\-]+/"),
    ("a personal or local path", r"(?i)/Users/|/home/|~/"),
]
def scan(text): return [what for what, pat in PATTERNS if re.search(pat, text)]
for sample, want in [("gh" + "p_" + "a" * 36, "a GitHub token"), ("x@" + "example.org", "an email address"),
                     ("3f2a" + "9b1c-0d4e-4f5a-8b6c-7d8e9f0a1b2c", "a GUID (a tenant or client id)"),
                     ("1234567" + "890.98765" + "43210", "a Slack app or client id"), ("acme" + ".slack.com", "a Slack workspace"),
                     ("/agents/" + "tenants/x", "a tenant in an address"), ("acme" + ".atlassian.net", "an Atlassian site")]:
    if want not in scan(sample): print(f"FAIL: recipes_no_secret: the scanner misses {want}"); sys.exit(1)
def strings(v):
    if isinstance(v, dict):
        for k, x in v.items(): yield k; yield from strings(x)
    elif isinstance(v, list):
        for x in v: yield from strings(x)
    else: yield str(v)
bad = []
for f in sorted(glob.glob(sys.argv[1] + "/*.json")):
    text = open(f, errors="ignore").read()
    for what in scan(text): bad.append(f"{f.split('/')[-1]}: holds {what}")
    try: r = json.load(open(f))
    except ValueError: continue
    for s in strings(r):
        if re.fullmatch(r"(?i)client.?id|client.?secret|tenant.?id|secret|password|api.?key|account|workspace|user(name)?", s):
            bad.append(f"{f.split('/')[-1]}: has a field or value named {s!r}")
for b in bad: print("FAIL: recipes_no_secret: " + b)
sys.exit(1 if bad else 0)
PY
}

# AC6: every host and page address is on that vendor's own domain.
recipes_hosts() {
  python3 -I - "$C" <<'PY' || rc=1
import json, sys
from urllib.parse import urlparse
C = sys.argv[1]; bad = []
DOMAINS = {"clickup": ["clickup.com"], "jira": ["atlassian.com"], "linear": ["linear.app"],
           "github": ["github.com", "githubcopilot.com"], "gmail": ["googleapis.com", "google.com"],
           "slack": ["slack.com", "slack.dev"], "discord": ["discord.com"],
           "outlook": ["cloud.microsoft", "microsoft.com"], "teams": ["cloud.microsoft", "microsoft.com"]}
def own(h, doms): return any(h == d or h.endswith("." + d) for d in doms)
for s, doms in DOMAINS.items():
    try: r = json.load(open(f"{C}/{s}.json"))
    except (OSError, ValueError): bad.append(f"{s}: no readable recipe"); continue
    for h in r.get("hosts", []):
        if not own(h, doms): bad.append(f"{s}: host {h} is not on {doms}")
    for k, u in r.get("pages", {}).items():
        p = urlparse(u)
        if p.scheme != "https" or not own(p.hostname or "", doms): bad.append(f"{s}: pages.{k} {u} is not https on {doms}")
    if r.get("state") == "ready" and r.get("sign_in", {}).get("kind") != "cli" and not r.get("hosts"):
        bad.append(f"{s}: ready, but names no host for the doctor check")
for b in bad: print("FAIL: recipes_hosts: " + b)
sys.exit(1 if bad else 0)
PY
}

# AC7: the guard plugin carries the recipes, validates, is listed, says it holds the recipes, and has no hook yet (K6).
recipes_plugin_valid() {
  local G="$R/plugins/guard"
  if command -v claude >/dev/null; then
    claude plugin validate "$G" >/dev/null 2>&1 || fail "recipes_plugin_valid: claude plugin validate plugins/guard (run it for details)"
  else fail "recipes_plugin_valid: claude is not installed, so plugins/guard cannot be validated"; fi
  python3 -I - "$R" <<'PY' || rc=1
import json, os, sys
R = sys.argv[1]; bad = []
G = f"{R}/plugins/guard"
try: j = json.load(open(f"{G}/.claude-plugin/plugin.json"))
except (OSError, ValueError): j = {}; bad.append("plugins/guard/.claude-plugin/plugin.json: missing or not JSON")
if j and (j.get("name") != "guard" or not j.get("version")): bad.append("plugins/guard plugin.json: name is not guard, or no version")
if "recipes" not in j.get("description", ""): bad.append("plugins/guard plugin.json: the description does not say it holds the recipes")
if set(j) - {"name", "description", "version"}: bad.append(f"plugins/guard plugin.json: unexpected keys {sorted(set(j) - {'name', 'description', 'version'})}")
m = [x for x in json.load(open(f"{R}/.claude-plugin/marketplace.json"))["plugins"] if x["name"] == "guard"]
if not m or m[0].get("source") != "./plugins/guard": bad.append("marketplace.json does not list guard at ./plugins/guard")
elif "recipes" not in m[0].get("description", ""): bad.append("marketplace.json: the guard description does not say it holds the recipes")
for d in ["hooks", "skills", "commands", "agents", "bin"]:
    if os.path.exists(f"{G}/{d}"): bad.append(f"plugins/guard/{d}: not part of K5 (the hook is story K6)")
for f in [".mcp.json", "hooks.json"]:
    if os.path.exists(f"{G}/{f}"): bad.append(f"plugins/guard/{f}: not part of K5")
for n in os.listdir(f"{G}/connectors") if os.path.isdir(f"{G}/connectors") else []:
    if not n.endswith(".json"): bad.append(f"plugins/guard/connectors/{n}: only recipes belong here")
for b in bad: print("FAIL: recipes_plugin_valid: " + b)
sys.exit(1 if bad else 0)
PY
}

# AC8: release.yml publishes each recipe as connector-<service>.json. The shared workflow (better-ade/.github v1) hashes
# each asset in release.json under its file name, so setup copies each recipe to that name. Checked without a release:
# the copy step, run on a copy of the recipes, gives exactly the assets listed, byte for byte the recipes.
recipes_release_assets() {
  python3 -I - "$R" "$T/release" <<'PY' || rc=1
import glob, hashlib, json, os, re, shutil, subprocess, sys
R, W = sys.argv[1], sys.argv[2]; bad = []
y = open(f"{R}/.github/workflows/release.yml").read()
if "uses: better-ade/.github/.github/workflows/release.yml@v1" not in y: bad.append("release.yml does not use the shared workflow at v1")
def value(key):
    m = re.findall(rf'^\s+{key}: "((?:[^"\\]|\\.)*)"\s*$', y, re.M)
    return m[0].replace('\\"', '"') if len(m) == 1 else None
setup, assets = value("setup"), value("assets")
COPY = 'mkdir -p .release-assets && for f in plugins/guard/connectors/*.json; do cp "$f" ".release-assets/connector-${f##*/}"; done'
if not setup or not setup.endswith(" && " + COPY): bad.append("release.yml: setup does not end with the step that copies each recipe to .release-assets/connector-<service>.json")
if assets is None: bad.append("release.yml: no assets input")
recipes = sorted(os.path.basename(f)[:-5] for f in glob.glob(f"{R}/plugins/guard/connectors/*.json"))
want = [f".release-assets/connector-{s}.json" for s in recipes]
if assets is not None and sorted(assets.split()) != want: bad.append(f"release.yml: assets {assets.split()} are not the recipes on disk {want}")
if not bad:
    shutil.rmtree(W, ignore_errors=True); os.makedirs(f"{W}/plugins/guard")
    shutil.copytree(f"{R}/plugins/guard/connectors", f"{W}/plugins/guard/connectors")
    subprocess.run(["bash", "-c", COPY], cwd=W, check=True)
    for a in assets.split():
        name = os.path.basename(a)  # what the shared release-manifest.sh writes as the file's name in release.json
        s = name[len("connector-"):-len(".json")]
        try: got = hashlib.sha256(open(f"{W}/{a}", "rb").read()).hexdigest()
        except OSError: bad.append(f"the copy step made no {a}"); continue
        if got != hashlib.sha256(open(f"{R}/plugins/guard/connectors/{s}.json", "rb").read()).hexdigest():
            bad.append(f"{a} is not byte for byte plugins/guard/connectors/{s}.json")
    made = sorted(os.listdir(f"{W}/.release-assets"))
    if made != sorted(os.path.basename(a) for a in assets.split()): bad.append(f"the copy step made {made}, not the assets list")
for b in bad: print("FAIL: recipes_release_assets: " + b)
sys.exit(1 if bad else 0)
PY
}

# AC9: docs/connectors.md lists each recipe with its tier and state; README points to them; CHANGELOG records them
# under the raised VERSION.
recipes_listed() {
  python3 -I - "$R" "$SERVICES" <<'PY' || rc=1
import json, re, sys
R, services = sys.argv[1], sys.argv[2].split(); bad = []
d = open(f"{R}/docs/connectors.md").read(); rd = open(f"{R}/README.md").read(); ch = open(f"{R}/CHANGELOG.md").read()
v = open(f"{R}/VERSION").read().strip()
m = re.search(r"^## Recipes \(K5\)\n(.*?)(?=^## |\Z)", d, re.S | re.M)
if not m: bad.append("docs/connectors.md: no '## Recipes (K5)' section")
for s in services:
    try: r = json.load(open(f"{R}/plugins/guard/connectors/{s}.json"))
    except (OSError, ValueError): continue
    if m:
        l = re.search(rf"^- `{s}`: tier (\d), (ready|held)\b", m.group(1), re.M)
        if not l: bad.append(f"docs/connectors.md Recipes: no '- `{s}`: tier N, state' line")
        elif (int(l.group(1)), l.group(2)) != (r["tier"], r["state"]): bad.append(f"docs/connectors.md Recipes: `{s}` says tier {l.group(1)}, {l.group(2)}; the recipe says {r['tier']}, {r['state']}")
if m and "seen in a live Claude Code session on 2026-11-22" not in m.group(1): bad.append("docs/connectors.md Recipes: does not record where the Gmail connector's tool names were seen")
if "plugins/guard/connectors/" not in rd or not re.search(r"^\| `guard` \|", rd, re.M): bad.append("README.md: no `guard` row or no pointer to plugins/guard/connectors/")
if tuple(map(int, v.split("."))) <= (0, 6, 0): bad.append(f"VERSION {v} is not raised above 0.6.0")
c = re.search(rf"^## {re.escape(v)}\n(.*?)(?=^## |\Z)", ch, re.S | re.M)
if not c: bad.append(f"CHANGELOG.md: no '## {v}' entry")
else:
    for s in services + ["guard"]:
        if f"`{s}`" not in c.group(1): bad.append(f"CHANGELOG.md '## {v}' does not record `{s}`")
for b in bad: print("FAIL: recipes_listed: " + b)
sys.exit(1 if bad else 0)
PY
}

recipes_valid; recipes_refuse_unknown; recipes_tiers; recipes_match_plugins; recipes_no_secret; recipes_hosts
recipes_plugin_valid; recipes_release_assets; recipes_listed
exit $rc
