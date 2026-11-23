#!/bin/bash
# Story K6 checks for the guard plugin's hook (plugins/guard/hooks). Files and local scripts only: no network, no model
# calls, and no command from the tables is ever run: each is passed to the hook as text. The hook is run exactly as
# hooks/hooks.json declares it. Called by tests/run.sh; exit 0 = pass. Each check is named as the story names it.
cd "$(dirname "$0")/.." || exit 1; R="$PWD"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
python3 -I - "$R" "$T" <<'PY'
import hashlib, importlib.util, json, os, re, shutil, subprocess, sys, time
sys.dont_write_bytecode = True
R, T = sys.argv[1], os.path.realpath(sys.argv[2])
G = f"{R}/plugins/guard"
bad = []
TEST = ["?"]
def fail(msg): bad.append(f"FAIL: {TEST[0]}: {msg}")

HOOK = {"type": "command", "command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"], "timeout": 10,
        "onFailure": "block"}
MODES = ["default", "plan", "acceptEdits", "auto", "dontAsk", "bypassPermissions"]

# ------------------------------------------------------------------ running the hook as hooks.json declares it
def groups(plugin):
    try: return json.load(open(f"{plugin}/hooks/hooks.json"))["hooks"]["PreToolUse"]
    except (OSError, ValueError, KeyError, TypeError): return []

def matches(matcher, name):
    # Claude Code's rule (hooks reference, "Matcher patterns"): letters, digits, _ - space , | only: exact names
    # (Bash also matches Monitor commands); anything else: a JavaScript regular expression, unanchored.
    if matcher in ("", "*"): return True
    if re.fullmatch(r"[A-Za-z0-9_\- ,|]+", matcher):
        alts = [a.strip() for a in re.split(r"[|,]", matcher)]
        return name in alts or ("Bash" in alts and name == "Monitor")
    return re.search(matcher, name) is not None

def run_hooks(plugin, data, name, env=None, path=None, direct=False):
    outs = []
    hs = [HOOK] if direct else [h for g in groups(plugin) if matches(g.get("matcher", ""), name) for h in g["hooks"]]
    for h in hs:
        argv = [h["command"]] + [a.replace("${CLAUDE_PLUGIN_ROOT}", plugin) for a in h.get("args", [])]
        e = {"PATH": path or os.environ.get("PATH", "/usr/bin:/bin"), "HOME": T, "CLAUDE_PLUGIN_ROOT": plugin}
        e.update(env or {})
        e = {k: v for k, v in e.items() if v is not None}
        p = subprocess.run(argv, input=data if isinstance(data, bytes) else data.encode(), capture_output=True,
                           env=e, cwd=T, timeout=60)
        outs.append((p.returncode, p.stdout.decode("utf-8", "replace"), h))
    return outs

def verdict(outs, label):
    """The strongest decision of the hooks that ran (deny > ask > none), and its reason. Every hook must exit 0 and
    print nothing or exactly one JSON object with ask or deny: never allow, never two objects."""
    best, why = "none", ""
    for rc, out, h in outs:
        if rc != 0: fail(f"{label}: the hook exited {rc}")
        if out == "": continue
        lines = out.splitlines()
        if len(lines) != 1 or not out.endswith("\n"): fail(f"{label}: output is not exactly one line: {out!r}"); continue
        try: j = json.loads(lines[0])
        except ValueError: fail(f"{label}: output is not JSON: {out!r}"); continue
        hs = j.get("hookSpecificOutput", {}) if isinstance(j, dict) else {}
        d = hs.get("permissionDecision")
        if set(j) != {"hookSpecificOutput"} or hs.get("hookEventName") != "PreToolUse" or d not in ("ask", "deny"):
            fail(f"{label}: not an ask or deny object: {out!r}"); continue
        if {"ask": 1, "deny": 2}[d] > {"none": 0, "ask": 1, "deny": 2}[best]:
            best, why = d, hs.get("permissionDecisionReason", "")
    return best, why

def call(plugin, tool, cwd, mode="default", project=None, tool_input=None, raw=None, env=None, path=None, direct=False):
    data = {"session_id": "s", "cwd": cwd, "permission_mode": mode, "hook_event_name": "PreToolUse",
            "tool_name": tool, "tool_input": tool_input if tool_input is not None else {}, "tool_use_id": "t"}
    if cwd is None: del data["cwd"]
    if mode is None: del data["permission_mode"]
    e = {"CLAUDE_PROJECT_DIR": project if project is not None else cwd}
    e.update(env or {})
    return verdict(run_hooks(plugin, raw if raw is not None else json.dumps(data), tool, e, path, direct),
                   f"{tool} {json.dumps(tool_input)[:80] if tool_input else ''} in {cwd}")

def bash(plugin, cmd, cwd, mode="default", **kw):
    return call(plugin, "Bash", cwd, mode, tool_input={"command": cmd, "description": "x"}, **kw)

# ------------------------------------------------------------------ fixtures
def recipe(service, **over):
    base = {"format": 1, "service": service, "title": service.title(), "job": "code", "tier": 2, "state": "ready",
            "sign_in": {"kind": "cli", "cli": "gh"}, "questions": [], "guard": {"prefixes": [], "read": []},
            "hosts": ["example.com"], "pages": {}, "reaches": "A test fixture."}
    base.update(over); return base

def ready_github():
    # The ready cli fixture is the shipped `github` recipe (amendment 1's shape, pinned by K5's test), set to ready.
    r = json.load(open(f"{G}/connectors/github.json")); r["state"] = "ready"; r.pop("held", None); return r

GITHUB = ready_github()
MAILBOX = recipe("mailbox", job="mail", sign_in={"kind": "claude-ai", "connector": "Mailbox"},
                 guard={"prefixes": ["mcp__claude_ai_Mailbox__"], "read": ["get_message", "search_threads"]})
CHATTER = recipe("chatter", job="chat", state="held", held="A test fixture that is held.",
                 sign_in={"kind": "claude-ai", "connector": "Chatter"},
                 guard={"prefixes": ["mcp__claude_ai_Chatter__"], "read": ["read_x"]})
OVERLAP = recipe("overlap", job="mail", sign_in={"kind": "claude-ai", "connector": "Mailbox__x"},
                 guard={"prefixes": ["mcp__claude_ai_Mailbox__x__"], "read": ["r"]})

def make_plugin(name, recipes, shipped=("jira", "slack")):
    d = f"{T}/{name}/guard"
    shutil.copytree(G, d, ignore=shutil.ignore_patterns("connectors"))
    os.makedirs(f"{d}/connectors")
    for s in shipped: shutil.copy(f"{G}/connectors/{s}.json", f"{d}/connectors/")
    for r in recipes: json.dump(r, open(f"{d}/connectors/{r['service']}.json", "w"), indent=2)
    p = subprocess.run(["bash", f"{d}/scripts/make-hooks.sh", d], capture_output=True, text=True)
    if p.returncode == 0: open(f"{d}/hooks/hooks.json", "w").write(p.stdout)
    return d

def project(name, connectors, git=True, raw=None):
    d = f"{T}/{name}"
    os.makedirs(f"{d}/.ade", exist_ok=True); os.makedirs(f"{d}/sub/deeper", exist_ok=True); os.makedirs(f"{d}/src", exist_ok=True)
    if git: os.makedirs(f"{d}/.git", exist_ok=True)
    if raw is not None: open(f"{d}/.ade/connectors.json", "wb").write(raw)
    elif connectors is not None: json.dump({"format": 1, "connectors": connectors}, open(f"{d}/.ade/connectors.json", "w"))
    return os.path.realpath(d)

def services():
    return sorted(f[:-5] for f in os.listdir(f"{G}/connectors") if f.endswith(".json"))

def shipped(s): return json.load(open(f"{G}/connectors/{s}.json"))

os.makedirs(f"{T}/home", exist_ok=True)
FX = make_plugin("fx", [GITHUB, MAILBOX, CHATTER])           # with the cli fixture: the shell checks
FM = make_plugin("fm", [MAILBOX, CHATTER])                   # without it: the MCP, folder and fail-closed checks
P = project("proj", ["github", "jira", "mailbox"])           # names the fixtures' ready services
Q = project("bare", None, git=False)                         # no record, no git
os.symlink(Q, f"{P}/outlink")                                # a link inside the project to a folder outside it
ALL = project("all", services())                             # names every shipped service

def checker_takes_fixtures():
    p = subprocess.run(["bash", f"{FX}/scripts/check-recipe.sh", f"{FX}/connectors/github.json"], capture_output=True, text=True)
    if p.returncode != 0:
        fail(f"the repo's check-recipe.sh refuses amendment 1's github example ({p.stdout.strip()[:160]}); the table needs K5's fix round")
        return False
    return True

# ------------------------------------------------------------------ AC1
def guard_matchers_from_recipes():
    try: h = json.load(open(f"{G}/hooks/hooks.json"))
    except (OSError, ValueError): return fail("plugins/guard/hooks/hooks.json is missing or not JSON")
    if set(h) != {"hooks"} or set(h["hooks"]) != {"PreToolUse"}: fail("hooks.json holds more than PreToolUse hooks")
    gs = h.get("hooks", {}).get("PreToolUse", [])
    ms = [g.get("matcher") for g in gs]
    for g in gs:
        if set(g) != {"matcher", "hooks"} or g.get("hooks") != [HOOK]:
            fail(f"group {g.get('matcher')}: not exactly one hook {json.dumps(HOOK)}")
    if len(ms) != len(set(ms)): fail("a matcher appears twice")
    want = {p + ".*" for s in services() if shipped(s)["state"] == "ready" for p in shipped(s)["guard"]["prefixes"]} | {"Bash"}
    if set(ms) != want: fail(f"matchers {sorted(set(ms) ^ want)} differ from the ready recipes' prefixes plus Bash")
    p = subprocess.run(["bash", f"{G}/scripts/make-hooks.sh"], capture_output=True, text=True)
    if p.returncode != 0 or p.stdout != open(f"{G}/hooks/hooks.json").read():
        fail("hooks.json is not what scripts/make-hooks.sh generates from the recipes (run it and commit the result)")
    gen = [g["matcher"] for g in json.load(open(f"{FM}/hooks/hooks.json"))["hooks"]["PreToolUse"]]
    if "mcp__claude_ai_Mailbox__.*" not in gen: fail("a ready recipe added on a copy got no matcher")
    if "mcp__claude_ai_Chatter__.*" in gen or "mcp__plugin_slack_slack__.*" in gen: fail("a held recipe got a matcher")
    broken = make_plugin("broken", [dict(MAILBOX, extra=1)])
    p = subprocess.run(["bash", f"{broken}/scripts/make-hooks.sh", broken], capture_output=True, text=True)
    if p.returncode == 0: fail("make-hooks.sh generated hooks from a recipe the checker refuses")

# ------------------------------------------------------------------ AC2
def guard_asks():
    for s in ("clickup", "jira", "linear"):
        r = shipped(s); pre = r["guard"]["prefixes"][0]
        if r["state"] != "ready": continue
        for t in r["guard"]["read"]:
            d, _ = call(G, pre + t, ALL)
            if d != "none": fail(f"{s} read {t}: {d}, want no decision")
        for t in ("createSomething", "executeWrite", "delete_all"):
            d, why = call(G, pre + t, ALL)
            if d != "ask" or t not in why: fail(f"{s} {t}: {d} ({why[:60]}), want ask naming the tool")
            for m in MODES[:-1]:
                if call(G, pre + t, ALL, mode=m)[0] != "ask": fail(f"{s} {t} in {m}: want ask")
            d, why = call(G, pre + t, ALL, mode="bypassPermissions")
            if d != "deny" or "bypassPermissions" not in why or t not in why: fail(f"{s} {t} in bypass: {d}, want deny naming the mode")
    # the same from an installed copy's layout (<cache>/<marketplace>/guard/<version>/), not the repo's
    inst = f"{T}/cache/ade-skills/guard/0.2.0"
    if not os.path.isdir(inst): shutil.copytree(G, inst)
    pre = shipped("jira")["guard"]["prefixes"][0]
    if call(inst, pre + "getJiraIssue", ALL)[0] != "none": fail("an installed copy: a jira read wants no decision")
    if call(inst, pre + "createJiraIssue", ALL)[0] != "ask": fail("an installed copy: a jira change wants ask")
    # a ready claude.ai connector, from a fixture
    if call(FM, "mcp__claude_ai_Mailbox__get_message", P)[0] != "none": fail("Mailbox read: want no decision")
    d, why = call(FM, "mcp__claude_ai_Mailbox__send_message", P)
    if d != "ask" or "send_message" not in why: fail("Mailbox send_message: want ask naming it")
    if call(FM, "mcp__claude_ai_Mailbox__send_message", P, mode="bypassPermissions")[0] != "deny": fail("Mailbox send in bypass: want deny")
    # a held recipe never causes a decision, even run directly
    for tool in ("mcp__claude_ai_Chatter__post", "mcp__claude_ai_Chatter__read_x", "mcp__plugin_slack_slack__send"):
        for direct in (False, True):
            d, _ = call(FM, tool, P, direct=direct)
            if d != "none": fail(f"{tool} (held recipe{', run directly' if direct else ''}): {d}, want no decision")
    # prefixes never overlap: a folder of recipes that overlap is refused whole (rule 1)
    ov = make_plugin("overlap", [MAILBOX, OVERLAP], shipped=())
    if call(ov, "mcp__claude_ai_Mailbox__get_message", project("ovproj", ["mailbox", "overlap"]), direct=True)[0] != "ask":
        fail("overlapping prefixes: want ask for every call")

# ------------------------------------------------------------------ AC3
def guard_folder_rule():
    jira = "mcp__plugin_jira_jira__getJiraIssue"
    d, why = call(FM, jira, Q)
    if d != "ask" or "jira is not connected in this folder" not in why: fail(f"no record: {d} ({why[:80]}), want ask")
    pj = project("onlyjira", ["jira"])
    if call(FM, jira, pj)[0] != "none": fail("record names jira: jira read wants no decision")
    if call(FM, "mcp__claude_ai_Mailbox__get_message", pj)[0] != "ask": fail("record lacks mailbox: its read wants ask")
    if call(FM, jira, f"{pj}/sub/deeper", project=f"{pj}/sub")[0] != "none": fail("started in a subfolder: the git top level's record applies")
    if call(FM, jira, Q, project=pj)[0] != "none": fail("the project folder comes from CLAUDE_PROJECT_DIR, not cwd")
    if call(FM, jira, pj, project=Q)[0] != "ask": fail("cwd's record must not stand in for the project folder's")
    if call(FM, jira, pj, env={"CLAUDE_PROJECT_DIR": None})[0] != "ask": fail("no CLAUDE_PROJECT_DIR: want ask")
    big = json.dumps({"format": 1, "connectors": ["jira"]}).encode()[:-1] + b" " * (64 * 1024) + b"}"
    bad_records = {
        "not JSON": b"{", "an array": b"[]", "unknown key": b'{"format":1,"connectors":["jira"],"x":1}',
        "format 2": b'{"format":2,"connectors":["jira"]}', "format true": b'{"format":true,"connectors":["jira"]}',
        "format 1.0": b'{"format":1.0,"connectors":["jira"]}', "unsorted": b'{"format":1,"connectors":["linear","jira"]}',
        "a name twice": b'{"format":1,"connectors":["jira","jira"]}', "a bad name": b'{"format":1,"connectors":["Jira"]}',
        "a key twice": b'{"format":1,"format":1,"connectors":["jira"]}', "over 64 KiB": big,
        "connectors not a list": b'{"format":1,"connectors":"jira"}',
        "65 names": json.dumps({"format": 1, "connectors": sorted(["jira"] + [f"s{i:02d}" for i in range(64)])}).encode(),
        "not UTF-8": b'{"format":1,"connectors":["jira\xff"]}', "NaN": b'{"format":NaN,"connectors":["jira"]}',
        "no connectors": b'{"format":1}',
    }
    for i, (what, raw) in enumerate(bad_records.items()):
        f = project(f"badrec{i}", None, raw=raw)
        if call(FM, jira, f)[0] != "ask": fail(f"record with {what}: want ask")
    f = project("recdir", None); os.makedirs(f"{f}/.ade/connectors.json", exist_ok=True)
    if call(FM, jira, f)[0] != "ask": fail("record that is a folder: want ask")
    f = project("reclink", None); os.symlink(f"{pj}/.ade/connectors.json", f"{f}/.ade/connectors.json")
    if call(FM, jira, f)[0] != "ask": fail("record that is a link: want ask")
    for cwd in (None, "relative/dir", 7):
        if call(FM, jira, cwd, project=P)[0] != "ask": fail(f"cwd {cwd!r}: want ask")

# ------------------------------------------------------------------ AC4
def guard_unknown_server():
    for tool in ("mcp__other__delete_everything", "mcp__plugin_foo_foo__write", "mcp__claude_ai_Notion__create_page",
                 "mcp__claude_ai_Mailboxx__send", "mcp__x__mcp__plugin_jira_jira__createJiraIssue", "Read", "Write"):
        for direct in (False, True):
            d, _ = call(FM, tool, P, direct=direct)
            if d != "none": fail(f"{tool} ({'run directly' if direct else 'as declared'}): {d}, want no decision")

# ------------------------------------------------------------------ AC5, AC6, AC7: the command table
X = "\x00"  # stands for the project folder in a command
TABLE = [
    # a listed shape, with listed flags (the contract's github example)
    ("gh pr view 12", "free"), ("gh pr view 12 --comments", "free"), ("gh pr view 12 --json title", "free"),
    ("gh pr view --json=title,body 12", "free"), ("gh pr list --state open --limit 5", "free"), ("gh pr list -L 5", "free"),
    ("gh issue view 7 -R o/r", "free"), ("gh auth status", "free"), ('gh search issues "label:bug"', "free"),
    ("gh run view 123 --log-failed", "free"), ("'gh' pr view 12", "free"), ('g"h" pr list', "free"),
    ("git status", "free"), ("git status -s", "free"), ("git status --porcelain=v2", "free"), ("git\tstatus", "free"),
    ("git log --oneline -n 5", "free"), ('git log --format="%h %s" -n 3', "free"), ("git log -- src/a.py", "free"),
    ('git log --grep="fix(x)"', "free"), ("git diff --cached", "free"), ('git diff "HEAD~1"', "free"),
    ("git show HEAD --stat", "free"), (f"git -C {X} status", "free"), ("git -C sub status", "free"),
    ("git --no-pager log --oneline", "free"), ("git remote -v", "free"), ("git stash list", "free"),
    ("git rev-parse --show-toplevel", "free"), ("git blame -L 10,20 a.py", "free"), ("git log '*'", "free"),
    ("git add -A", "free"), ("git add src/a.py", "free"), ('git commit -m "feat(x): y"', "free"),
    ("git commit -m 'a; b && c | d > e'", "free"), ("git commit -m 'hi!'", "free"), ('git commit -m "x" -m "y"', "free"),
    ("git commit --amend --no-edit", "free"), ("git switch -c feature/x", "free"), ("git checkout -b k6", "free"),
    ("git restore --staged a.py", "free"), ("git reset --soft HEAD^", "free"), ("git branch -D old", "free"),
    ('git tag -a v1 -m "v1"', "free"), ('git stash push -m "wip"', "free"), ("git stash pop 'stash@{1}'", "free"),
    ("git merge --no-ff feature", "free"), ("git rebase main", "free"), ("git cherry-pick abc123", "free"),
    ("git revert --no-edit abc", "free"), ("git init -b main", "free"), ("git fetch origin", "free"),
    ("git fetch --prune origin", "free"), ("git pull origin main", "free"), ("git pull --ff-only", "free"),
    # the review's reproductions: a flag or a word riding on a free shape
    ("git remote -v add evil https://example.com/x", "ask"), ('git grep -O"vim" x', "ask"), ("git grep -Ovim x", "ask"),
    ("git grep --open-files-in-pager=vim x", "ask"), ("git log --output=.git/hooks/post-checkout", "ask"),
    ("git diff --output x", "ask"), ('git fetch "--upload-pack=touch x" origin', "ask"), ("git fetch --upload-pa=x origin", "ask"),
    ('git rebase -x"gh pr merge 1" main', "ask"), ("git rebase --exec=true main", "ask"), ("gh pr list --json n --jq env", "ask"),
    ("gh pr view --web", "ask"), ("gh pr view -w", "ask"), ("git diff --ext-diff", "ask"), ("git merge -s ours x", "ask"),
    ("git cherry-pick -x abc", "ask"), ("git clean -x", "ask"), ("git commit --no-verify -m x", "ask"), ("git rebase -i main", "ask"),
    ("git add -p", "ask"), ("git fetch --recurse-submodules origin", "ask"),
    # no abbreviation, no cluster, values as listed
    ("git status -sb", "ask"), ("git log --onel", "ask"), ("gh pr list --lim 5", "ask"), ("gh pr list -L5", "ask"),
    ("gh pr list -L=5", "ask"), ("gh pr list --limit=-1", "ask"), ("gh pr list --limit", "ask"), ("gh pr view 1 --json", "ask"),
    ("gh pr list --limit -1", "ask"),
    # arguments: none, names
    ("gh pr list foo", "ask"), ("git stash list x", "ask"), ("git remote show origin", "ask"), ("git stash clear", "ask"),
    ("git fetch origin feature/x", "ask"), ("git fetch https://example.com/x", "ask"), ("git fetch ../other", "ask"),
    ("git pull origin main:main", "ask"), ("git fetch origin src", "ask"), ("git fetch -- origin", "ask"), ("git fetch .", "ask"),
    ("git pull user@host", "ask"),
    # not listed at all
    ("git push origin main", "ask"), ("git clone https://example.com/x", "ask"), ("git config user.name x", "ask"),
    ("git submodule update", "ask"), ("git remote add x y", "ask"), ("git ls-remote origin", "ask"), ("git gc", "ask"),
    ("gh pr merge 12", "ask"), ("gh repo delete x/y --yes", "ask"), ("gh my-extension", "ask"), ("gh", "ask"), ("git", "ask"),
    ("gh --version", "ask"), ("gh api repos/x/y", "ask"), ("gh api graphql -f query=x", "ask"), ("gh api -X DELETE repos/x/y", "ask"),
    # global options and directories
    ("git -c core.pager=sh log", "ask"), ("git -c alias.st='!gh pr merge 1' st", "ask"), ("git -C /tmp status", "ask"),
    ("git -C .. status", "ask"), ('git -C "" status', "ask"), ("git -Csub status", "ask"), ("git --git-dir=x status", "ask"),
    ("git -p status", "ask"), ("git --exec-path=x status", "ask"), ("git --no-pager --no-pager log", "ask"),
    ("git -C sub -C sub status", "ask"), ("gh -R o/r pr view 1", "ask"), ("git -c core.pager=sh status", "ask"),
    ("git -C outlink status", "ask"), ("git log -- gh", "ask"), ("git show gh", "ask"), ("git add ./gh", "ask"),
    ("git log --author=git", "ask"),
    # the path rule: a positional outside the project folder asks; revisions and paths inside are untouched
    ("git diff /etc/passwd /dev/null", "ask"), ("git diff ../../outside/file x", "ask"), ("git show HEAD:README.md", "free"),
    ("git diff -- src/a.c", "free"), (f"git log -- {X}/src/a.c", "free"), ("git blame ~/x", "ask"), ('git blame "~/x"', "ask"), ("git grep pat ../..", "ask"),
    ("git diff /dev/null src/a.c", "ask"), ("git log -- /etc/passwd", "ask"), ("git diff outlink/token", "ask"),
    ("git diff sub/../src/a.c", "free"), ("git show main..feature", "free"), ("git log origin/main", "free"),
    ("gh repo view /etc/passwd", "ask"), ("git -C sub diff ../src/a.c", "free"), ("git -C sub diff ../../x", "ask"),
    # the shell characters, both sides of the quotes
    ("git diff HEAD~1", "ask"), ("git log *", "ask"), ("git stash pop stash@{1}", "ask"), ("git log [a]", "ask"),
    ('git commit -m "$(cat f)"', "ask"), ('git commit -m "hi!"', "ask"), ('git commit -m "a\\"b"', "ask"), ("git show HEAD\\~1", "ask"),
    ("git commit -m 'a\nb'", "ask"), ("git status; ls", "ask"), ("git status && ls", "ask"), ("git status | cat", "ask"),
    ("git status > f", "ask"), ("git status 2>/dev/null", "ask"), ("gh pr view < in.txt", "ask"), ("git log ?", "ask"),
    ("git commit -m `date`", "ask"), ("git log !x", "ask"), ("git commit -m 'unterminated", "ask"),
    # compound lines, substitutions, other shells
    ("gh pr view && gh pr merge 1", "ask"), ("gh pr view || gh pr merge 1", "ask"), ("gh pr view; gh pr merge 1", "ask"),
    ("gh pr view & gh pr merge 1", "ask"), ("gh pr view\ngh pr merge 1", "ask"), ("gh pr view\rgh pr merge 1", "ask"),
    ("gh pr list | grep x", "ask"), ("(gh pr merge 1)", "ask"), ("{ gh pr merge 1; }", "ask"),
    ("echo $(gh pr merge 1)", "ask"), ("echo `gh pr merge 1`", "ask"), ("sh -c 'gh pr merge 1'", "ask"),
    ('bash -c "gh pr merge 1"', "ask"), ("zsh -c 'git push'", "ask"), ("eval gh pr merge 1", "ask"),
    ("eval 'g''h pr merge 1'", "ask"), ("exec gh pr merge 1", "ask"), ("command gh pr merge 1", "ask"),
    ("builtin command gh pr view", "ask"), ("env gh pr merge 1", "ask"), ("env -i PATH=/usr/bin gh pr view", "ask"),
    ("nice gh pr merge 1", "ask"), ("time gh pr view", "ask"), ("nohup git push &", "ask"), ("timeout 5 gh pr merge 1", "ask"),
    ("sudo gh pr merge 1", "ask"), ("echo 1 | xargs gh pr merge", "ask"), ("xargs -I{} gh pr merge {} < ids", "ask"),
    ("find . -name x -exec gh pr merge 1 \\;", "ask"), ("watch gh pr view", "ask"), ("cd repo && git status", "ask"),
    ("true || git push", "ask"),
    # the name hidden in a variable, a path, quotes, escapes or expansions
    ("x=gh; $x pr merge 1", "ask"), ("x=g y=h; $x$y pr merge 1", "ask"), ('G=gh; "$G" pr merge 1', "ask"),
    ("$GH pr merge 1", "ask"), ("${x:-gh} pr merge 1", "ask"), ("${x/q/g}h pr merge 1", "ask"),
    ("/opt/homebrew/bin/gh pr view", "ask"), ("./gh pr merge 1", "ask"), ("../bin/git push", "ask"), ("~/bin/gh pr view", "ask"),
    ('g"h" pr merge 1', "ask"), ("g\\h pr merge 1", "ask"), ("'g'it push", "ask"), ("$'gh' pr merge 1", "ask"),
    ("$'\\x67h' pr merge 1", "ask"), ("$'\\147\\150' pr view", "ask"), ("{g,}h pr merge 1", "ask"), ("gi{t,} push", "ask"),
    ("/opt/homebrew/bin/g? pr merge 1", "ask"), ("/usr/bin/gi[t] push", "ask"), ("=gh pr merge 1", "ask"),
    ("git-receive-pack .", "ask"), ("/usr/libexec/git-core/git-push origin", "ask"),
    # here-documents, here-strings, process substitution
    ("sh <<EOF\ngh pr merge 1\nEOF", "ask"), ("sh <<< 'gh pr merge 1'", "ask"), ("bash <(echo gh pr merge 1)", "ask"),
    # aliases and functions defined on the line, leading assignments, exported variables
    ("alias g=gh; g pr merge 1", "ask"), ("f() { gh pr merge 1; }; f", "ask"), ("function f { git push; }; f", "ask"),
    ("GH_HOST=x gh pr view 1", "ask"), ("GIT_PAGER=x git log", "ask"), ("GIT_DIR=/x git status", "ask"),
    ("export GIT_PAGER=cat", "ask"), ("export GH_TOKEN=x", "ask"), ("export GITHUB_TOKEN=x", "ask"),
    # the letters alone: no decision (AC7)
    ("echo ghost", "none"), ("light", "none"), ("cat github.txt", "none"), ("cat ./gh-notes.md", "none"),
    ("cat .gitignore", "none"), ("ls -la .github/workflows", "none"), ("grep -rn digit src", "none"),
    ("npm test", "none"), ("python3 -m pytest -q", "none"), ("make build", "none"), ('echo "legit" > notes.txt', "none"),
    ("ls src/*.py", "none"), ("for i in {1..3}; do echo $i; done", "none"), ("cat <<'EOF' > a.txt\nhello\nEOF", "none"),
    ("echo $HOME", "none"), ('cd "$HOME/x" && ls', "none"), ("awk '{print $1}' f", "none"),
    ("find . -name '*.md' -exec wc -l {} +", "none"), ("ls ~/Project", "none"), ("echo ${HOME}", "none"),
    ("docker ps | grep web", "none"), ("cat ghost.txt | wc -l", "none"), ("export X=1; echo $X", "none"),
    ("ls -la", "none"), ("cargo build --release", "none"), ("rg -n 'digit' src", "none"),
    # a piece that is exactly gh or git asks, even in echo (rule 4b)
    ("echo gh", "ask"), ("which git", "ask"), ("ls /usr/bin/git", "ask"),
    # fix round, review of PR #18. 1: names in any case (macOS file systems ignore case)
    ("GIT push", "ask"), ("Git push", "ask"), ("/usr/bin/GIT push", "ask"), ("/USR/BIN/GIT push", "ask"),
    ("GH pr merge 1", "ask"), ("./GH pr merge 1", "ask"), ("Gh_HOST=x gh pr view 1", "ask"),
    # 2: an unquoted expansion splits a word
    ("git${IFS}push", "ask"), ("git$IFS'push'", "ask"), ('git$IFS"push"', "ask"), ("git${IFS}push${IFS}origin", "ask"),
    ("x=' '; git${x}push", "ask"), ("git${=IFS}push", "ask"),
    # 3: shell commands that rewrite git or gh configuration
    ('sed -i "" s/github.com/evil.example/ .git/config', "ask"), ('echo "[core] fsmonitor = ./x.sh" >> .git/config', "ask"),
    ("printf '[alias]' >> .git/config", "ask"), ("cp /tmp/c .git/config", "ask"), ("tee -a .git/config < f", "ask"),
    ("ln -sf /tmp/hooks .git/hooks", "ask"), ("echo x >> ~/.gitconfig", "ask"), ("cat f >> ~/.config/gh/config.yml", "ask"),
    ("cp x ~/.config/gh/hosts.yml", "ask"), ("echo x > .gitmodules", "ask"), ("ls .git", "ask"), ("cat sub/.GIT/config", "ask"),
    # 7: commit's file values, zsh's =cmd, the branch upstream flags, -<n> counts
    ("git commit -F /etc/passwd", "ask"), ("git commit --file=/etc/passwd", "ask"), ("git commit -F ../../x", "ask"),
    ("git commit -F msg.txt", "free"), ("git log =x", "ask"), ("git log --format='a=b' -n 1", "free"),
    ("git branch -u origin/main", "ask"), ("git branch --set-upstream-to=origin/main", "ask"),
    ("git log -5", "free"), ("git log --oneline -20", "free"), ("git rev-list -3 HEAD", "free"), ("git shortlog -3", "free"),
    ("git show -5", "ask"), ("git log -5x", "ask"),
    # 8: found only by reading quoted text again as a command line
    ("sh -c '$x pr merge 1'", "ask"), ("bash -c '$GIT push'", "ask"),
    # 9: a here-string is not a here-document; git's stored credentials; a glob in a configuration path; a glob alone
    # is not a deny run (git add * must stay a question, not a refusal)
    ("cat <<< 'a b'", "none"), ('wc -l <<< "it is fine"', "none"), ("ls */*.yml", "none"), ("ls src/.??*", "none"),
    ("cat ~/.git-credentials", "ask"), ("cat ~/.config/git/credentials", "ask"), ("echo x >> .gi[t]/config", "ask"), ("echo x >> .g*/config", "ask"),
    ("echo x >> ~/.gitconf*", "ask"), ("cat ~/.config/g?/hosts.yml", "ask"), ("cat ~/.config/gh/*", "ask"),
    ("git add *", "ask"), ("git add c* f*", "ask"), ("gh auth status && ls *.md", "ask"), ("gh pr view $n", "ask"),
]
REFUSED = [  # AC6: refused in every mode, in every folder
    "gh auth token", "gh auth token --hostname example.com", "gh auth status --show-token", "gh auth status -t",
    "gh auth status -at", "gh auth status --show-token=true", "gh auth status --hostname x -t", "gh auth -t status",
    "gh auth status -tfoo", 'gh auth tok"en"', "echo $(gh auth token)", "x=$(gh auth token); echo $x",
    "git credential fill", "echo url=https://example.com | git credential fill", "/usr/bin/git credential fill",
    "gh auth $'\\x74oken'", "GH_HOST=x gh auth token",
    # fix round, review of PR #18. 1: any case
    "GH auth token", "Gh auth token", "GH auth status --show-token", "GIT credential fill", "echo $(GH auth token)",
    # 2: an unquoted expansion splits words
    "gh${IFS}auth${IFS}token", "gh${IFS}auth token", "gh$IFS'auth'$IFS'token'", "gh${=IFS}auth${=IFS}token",
    # 4: credential helpers and a token kept in gh's config
    "gh auth git-credential get", "git credential-osxkeychain get", "git credential-store get", "git credential-cache get",
    "git credential-manager get", "git-credential-osxkeychain get", "gh config get oauth_token", "gh config get -h github.com oauth_token",
    "git credential-manager-core get", "git credential-libsecret get", "git credential-oauth get", "git credential-wincred get",
    # 6: quoted text that a shell on the line reads again as a command line is not a mention
    "sh -c 'gh auth token'", "bash -c 'g${x}h auth token'", 'eval "gh auth token"', "echo 'gh auth token' | sh",
    "sh <<EOF\ngh auth token\nEOF", "bash <<< 'gh auth token'", "alias t='gh auth token'; t", "trap 'gh auth token' EXIT",
    "watch 'gh auth token'", "ssh host 'gh auth token'",
    "x='gh auth token'; $x", "a='auth token'; gh $a", "export T='gh auth token'; $T", 'bash -c "sh -c \'gh auth token\'"',
    # 9: a glob or a brace that can become the missing element (a file named token, or -t); a flag before a quoted value
    "gh auth t*", "gh auth tok?n", "gh auth [t]oken", "gh auth tok{en,}", "gh auth *", "gh auth status -?", "gh auth status *",
    "gh auth status -[a-z]", "gh auth status {-t,}",
    "git credential f*", "git credential-osx* get", 'gh auth status --show-token="a b"',
    # 9: text the shell does not read as a here-document or as a quote must not hide the next line; an unquoted
    # here-document still runs its substitutions
    "cat <<< x\ngh auth token", "((1<<2))\ngh auth token", "echo hi # <<X\ngh auth token", "echo # it's\ngh auth token\n# it's",
    "cat <<EOF\n$(gh auth token)\nEOF", "cat <<EOF\n`gh auth token`\nEOF", "cat <<-EOF\n\t$(git credential fill)\n\tEOF",
]
SOFT = [  # 6: a deny run found only inside quotes, a here-document or a flag's value: ask (deny in bypass), everywhere
    'echo "gh auth token"', 'git commit -m "credential fill"', 'git commit -m "docs: never run gh auth token"',
    'git log --grep="credential fill"', 'rg "gh auth token" docs', "cat <<'EOF' > n.md\nnever run gh auth token\nEOF",
    "cat <<EOF > n.md\nnever run gh auth token\nEOF", "vim -c '!gh auth token'", "ruby -e 'system %q{gh auth token}'",
    "git log --grep=credential -- fill", "bash -c \"echo 'never run gh auth token'\"",
    'git commit -m "fix bash completion for gh auth token"', "python3 -c 'print(\"gh auth token\")'",
    "echo 'auth token' | xargs gh", "cat <<'EOF'\n$(gh auth token)\nEOF", "cat <<\\EOF\n$(gh auth token)\nEOF", "find . -name '*.sh' | xargs grep -l 'gh auth token'",
]

def cmd_of(c): return c.replace(X, P)

def table_rows(want_set):
    for c, tag in TABLE:
        if tag not in want_set: continue
        want = "none" if tag == "free" else tag
        cmd = cmd_of(c)
        d, why = bash(FX, cmd, P)
        if d != want: fail(f"{cmd!r}: {d}, want {want} ({why[:120]})")
        elif d == "ask" and clean_line(cmd)[:40] not in why: fail(f"{cmd!r}: the reason does not name the command")
        if want == "ask":
            d, why = bash(FX, cmd, P, mode="bypassPermissions")
            if d != "deny" or "bypassPermissions" not in why: fail(f"{cmd!r} in bypass: {d}, want deny naming the mode")

def clean_line(s): return re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", s)

def guard_gh_git():
    if len(TABLE) + len(REFUSED) + len(SOFT) < 60: fail(f"the table has {len(TABLE) + len(REFUSED) + len(SOFT)} rows, want at least 60")
    if not checker_takes_fixtures(): return
    table_rows({"free", "ask"})
    d, _ = call(FX, "Monitor", P, tool_input={"command": "gh pr merge 1"})
    if d != "ask": fail(f"Monitor 'gh pr merge 1': {d}, want ask")
    # the working directory (cwd) must be the project folder or inside it
    if bash(FX, "git status", f"{P}/sub")[0] != "none": fail("git status in a subfolder of the project: want no decision")
    for c in ("git status", "gh pr view 1"):
        if bash(FX, c, Q, project=P)[0] != "ask": fail(f"{c!r} with cwd outside the project folder: want ask")
    lk = f"{T}/link-out"; os.symlink(Q, lk)
    if bash(FX, f"git -C {lk} status", P)[0] != "ask": fail("git -C through a link to outside: want ask")
    # 4d: free-or-ask only where the record names a ready cli service; an unreadable record asks
    if bash(FX, "gh pr merge 1", Q)[0] != "none": fail("a folder with no record: gh pr merge wants no decision")
    if bash(FX, "git push", project("onlyjira", ["jira"]))[0] != "none": fail("a folder that does not name github: git push wants no decision")
    if bash(FX, "git status", project("badrec0", None, raw=b"{"))[0] != "ask": fail("an unreadable record: git status wants ask")
    # a held cli recipe: no decision, but its deny entries still refuse
    held = make_plugin("heldcli", [dict(GITHUB, state="held", held="A held fixture.")], shipped=())
    if bash(held, "gh pr merge 1", P)[0] != "none": fail("a held cli recipe: gh pr merge wants no decision")
    if bash(held, "gh auth token", P)[0] != "deny": fail("a held cli recipe's deny entries still refuse")

def guard_gh_refused():
    if not checker_takes_fixtures(): return
    for c in ("gh api repos/x/y", "gh api user"):
        for mode in MODES[:-1]:
            if bash(FX, c, P, mode=mode)[0] != "ask": fail(f"{c!r} in {mode}: want ask")
    for c in REFUSED:
        for mode in MODES:
            d, why = bash(FX, c, P, mode=mode)
            if d != "deny" or "credential" not in why: fail(f"{c!r} in {mode}: {d}, want deny")
        for folder in (Q, project("onlyjira", ["jira"])):
            if bash(FX, c, folder)[0] != "deny": fail(f"{c!r} in a folder that does not name github: want deny")
    for c in SOFT:
        for mode in MODES:
            d, why = bash(FX, c, P, mode=mode)
            want = "deny" if mode == "bypassPermissions" else "ask"
            if d != want: fail(f"{c!r} in {mode}: {d}, want {want} (a quoted mention, approvable)")
        for folder in (Q, project("onlyjira", ["jira"])):
            if bash(FX, c, folder)[0] != "ask": fail(f"{c!r} in a folder that does not name github: want ask")

def guard_other_commands():
    if not checker_takes_fixtures(): return
    table_rows({"none"})
    cmd = "ls -la"
    for _ in range(3): bash(FX, cmd, P)        # warm the file cache
    n, times = 30, []
    for _ in range(n):
        t0 = time.perf_counter(); d, _ = bash(G, cmd, ALL); times.append(time.perf_counter() - t0)
        if d != "none": fail(f"{cmd!r}: {d}, want no decision")
    times.sort(); median, worst = times[n // 2], times[-1]
    LIMIT = 0.25   # seconds per shell command, the whole hook process; measured about 0.05 on the build Mac
    print(f"note: guard_other_commands: the hook took {median * 1000:.0f} ms (median of {n}), {worst * 1000:.0f} ms at most, per shell command")
    if median > LIMIT: fail(f"the hook took {median:.3f} s (median of {n}) per shell command; the limit is {LIMIT} s")

# ------------------------------------------------------------------ AC8
def guard_fail_closed():
    jira = "mcp__plugin_jira_jira__getJiraIssue"
    for label, raw in [("not JSON", b"{"), ("empty", b""), ("an array", b"[]"), ("not UTF-8", b"\xff\xfe"),
                       ("no tool_name", json.dumps({"cwd": P}).encode()),
                       ("tool_name a number", json.dumps({"cwd": P, "tool_name": 3}).encode()),
                       ("permission_mode a list", json.dumps({"cwd": P, "tool_name": "Bash", "permission_mode": [],
                                                             "tool_input": {"command": "ls"}}).encode())]:
        d, _ = verdict(run_hooks(FX, raw, "Bash", {"CLAUDE_PROJECT_DIR": P}, direct=True), label)
        if d != "ask": fail(f"input {label}: {d}, want ask")
    for ti in ({}, {"command": 7}, {"command": ["gh"]}, "gh pr view"):
        if call(FX, "Bash", P, tool_input=ti)[0] != "ask": fail(f"Bash tool_input {ti!r}: want ask")
    def broken(name, change):
        d = make_plugin(name, [GITHUB, MAILBOX]); change(d); return d
    cases = {
        "an invalid recipe": lambda d: json.dump(dict(MAILBOX, extra=1), open(f"{d}/connectors/mailbox.json", "w")),
        "a recipe that is not JSON": lambda d: open(f"{d}/connectors/github.json", "w").write("{"),
        "a missing recipe": lambda d: os.remove(f"{d}/connectors/jira.json"),
        "no recipe folder": lambda d: shutil.rmtree(f"{d}/connectors"),
        "an empty recipe folder": lambda d: [os.remove(f"{d}/connectors/{f}") for f in os.listdir(f"{d}/connectors")],
        "no checker": lambda d: os.remove(f"{d}/scripts/check-recipe.sh"),
        "a checker without its rules": lambda d: open(f"{d}/scripts/check-recipe.sh", "w").write("#!/bin/bash\nexit 0\n"),
        "no helper": lambda d: os.remove(f"{d}/hooks/guard.py"),
        "a helper that fails": lambda d: open(f"{d}/hooks/guard.py", "w").write("raise SystemExit(3)\n"),
        "a helper that allows": lambda d: open(f"{d}/hooks/guard.py", "w").write(
            'import json\nprint(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "x"}}))\n'),
        "a helper that prints two objects": lambda d: open(f"{d}/hooks/guard.py", "w").write(
            'import json\no = json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "x"}})\nprint(o); print(o)\n'),
        "a helper that prints text": lambda d: open(f"{d}/hooks/guard.py", "w").write('print("hello")\n'),
        "a helper that prints PASS and fails": lambda d: open(f"{d}/hooks/guard.py", "w").write('print("PASS"); raise SystemExit(1)\n'),
    }
    for i, (what, change) in enumerate(cases.items()):
        d = broken(f"fc{i}", change)
        for tool, ti in ((jira, {}), ("Bash", {"command": "ls"}), ("Bash", {"command": "gh pr view"})):
            if what == "a missing recipe" and tool == "Bash": continue
            got, _ = call(d, tool, P, tool_input=ti)
            if got != "ask": fail(f"{what}: {tool} {ti}: {got}, want ask")
    d = broken("fcmiss", lambda d: os.remove(f"{d}/connectors/jira.json"))
    if call(d, jira, P)[0] != "ask": fail("a missing recipe: a tool under its declared prefix wants ask")
    # 5: nothing hangs: a FIFO record, pathological lines (each within a limit, the hook's own process)
    fifo = project("fiforec", None); os.mkfifo(f"{fifo}/.ade/connectors.json")
    for label, run in [("a FIFO record", lambda: call(FM, jira, fifo)),
                       ("'{' x 20000", lambda: bash(FX, "{" * 20000, P)), ("'$(' x 5000", lambda: bash(FX, "$(" * 5000, P)),
                       ("'${' x 5000", lambda: bash(FX, "${" * 5000, P)), ("'`' x 20001", lambda: bash(FX, "`" * 20001, P)),
                       ("'[' x 20000", lambda: bash(FX, "[" * 20000, P)), ("quotes x 20000", lambda: bash(FX, "'a'\"b\"" * 10000, P)),
                       ("200 KiB of words", lambda: bash(FX, "echo " + "word " * 40000, P)),
                       ("20000 globs", lambda: bash(FX, "gh auth " + "*a?b*c?[d]*e{f,g}* " * 20000, P)),
                       ("3000 different globs", lambda: bash(FX, "gh auth " + " ".join("?*" * 30 + str(i) for i in range(3000)), P)),
                       ("a comment per line", lambda: bash(FX, "# it's <<X ((\n" * 5000, P)),
                       ("one long glob", lambda: bash(FX, "git credential " + "*a" * 30000, P))]:
        t0 = time.perf_counter(); d, _ = run(); took = time.perf_counter() - t0
        if took > 5: fail(f"{label}: the hook took {took:.1f} s (limit 5 s)")
        if label == "a FIFO record" and d != "ask": fail(f"{label}: {d}, want ask")
    nopy = f"{T}/nopy"; os.makedirs(nopy, exist_ok=True)
    bash_path = shutil.which("bash")
    if not os.path.exists(f"{nopy}/bash"): os.symlink(bash_path, f"{nopy}/bash")
    for tool, ti in ((jira, {}), ("Bash", {"command": "ls"})):
        if call(FX, tool, P, tool_input=ti, path=nopy)[0] != "ask": fail(f"no python3 on PATH: {tool} wants ask")

# ------------------------------------------------------------------ AC9
SHIPPED = {  # sha256 of the shipped per-plugin hook files on main (story K1); the guard must not change them
    "clickup/hooks/hooks.json": "16a2c08c61c0cb652ec1c110e8a8738ba789135ef2161c29c0916281c8c976dc",
    "clickup/hooks/ask-unless-read.sh": "02db20c4e783cdb0d922a10106105ecb785d011685438d04658e1afabc9b1e02",
    "clickup/hooks/read-tools.txt": "e9f9801b957f9f46234903641db19234fd5f13c54eb67cabb62012a6ebc4d343",
    "jira/hooks/hooks.json": "e2ce6b2ecf19eea154ed821a039c5e1afd91e8ae3abfed38ef6a8c224d18a564",
    "jira/hooks/ask-unless-read.sh": "02db20c4e783cdb0d922a10106105ecb785d011685438d04658e1afabc9b1e02",
    "jira/hooks/read-tools.txt": "afb334d1b8defcd3222a6796a6cd3ce948d509f754b007a872caaa92823b76f9",
    "linear/hooks/hooks.json": "f4d03768826652c8e7d27a21d25cb0a75e529810850465889b5b0da43589a47f",
    "linear/hooks/ask-unless-read.sh": "02db20c4e783cdb0d922a10106105ecb785d011685438d04658e1afabc9b1e02",
    "linear/hooks/read-tools.txt": "6c74eb3ef5a353c3e6140f9429f0383414a39623f2b6e051f5c988276c12f5b8",
}
def guard_with_plugin_hooks():
    for f, h in SHIPPED.items():
        try: got = hashlib.sha256(open(f"{R}/plugins/{f}", "rb").read()).hexdigest()
        except OSError: got = None
        if got != h: fail(f"plugins/{f} changed")
    for s in ("clickup", "jira", "linear"):
        r = shipped(s); pre = r["guard"]["prefixes"][0]; pl = f"{R}/plugins/{s}"
        for t in r["guard"]["read"][:5] + ["createSomething", "executeWrite"]:
            for mode in ("default", "bypassPermissions"):
                a, _ = call(pl, pre + t, ALL, mode=mode)   # the plugin's own hook, as its hooks.json declares it
                b, _ = call(G, pre + t, ALL, mode=mode)    # the guard, in a folder that names the service
                if a != b: fail(f"{s} {t} in {mode}: the plugin's hook says {a}, the guard {b}; they must agree")
    d = open(f"{R}/docs/connectors.md").read()
    for need in ("precedence is `deny` > `defer` > `ask` > `allow`", "When both hooks ask about one call"):
        if need not in d: fail(f"docs/connectors.md does not record {need!r}")

# ------------------------------------------------------------------ AC10
def guard_docs():
    d = open(f"{R}/docs/connectors.md").read()
    m = re.search(r"^## The guard \(K6\)\n(.*?)(?=^## |\Z)", d, re.S | re.M)
    if not m: return fail("docs/connectors.md has no '## The guard (K6)' section")
    s = m.group(1)
    for need in ("What the guard does not see", "a script", "git hook", "MCP resources", "The PowerShell tool",
                 "When the owner is not the one answering", "CLAUDE_PROJECT_DIR", "`cwd`", "onFailure", "ms",
                 "aliases and functions", "amendment 1"):
        if need not in s: fail(f"the guard section does not mention {need!r}")
    w = re.search(r"^## When the owner is not the one answering\n(.*?)(?=^## |\Z)", d, re.S | re.M)
    if not w or "guard" not in w.group(1): fail("'When the owner is not the one answering' does not cover the guard")

for t in (guard_matchers_from_recipes, guard_asks, guard_folder_rule, guard_unknown_server, guard_gh_git,
          guard_gh_refused, guard_other_commands, guard_fail_closed, guard_with_plugin_hooks, guard_docs):
    TEST[0] = t.__name__
    try: t()
    except Exception as e: fail(f"the check could not run ({type(e).__name__}: {e})")
for b in bad[:200]: print(b)
if len(bad) > 200: print(f"FAIL: ... and {len(bad) - 200} more")
sys.exit(1 if bad else 0)
PY
