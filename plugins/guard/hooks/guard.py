# The guard's helper (story K6), run by guard.sh as: python3 -I guard.py <plugin folder>, the hook's JSON on stdin.
# Prints PASS (no decision) or one JSON line with "ask" or "deny"; guard.sh passes on nothing else. It never allows,
# makes no network call and runs no program. The rules are .ade/context/connectors.md, section 4 (amendment 1); the
# comments name each rule. docs/connectors.md, "The guard (K6)", says what it does and does not see.
import json, os, re, shlex, stat, sys

# What a `ready` recipe gets where the record does not name it (rule 2: ask; rule 4d: no decision). One place each.
UNNAMED_MCP = "ask"
UNNAMED_CLI = "none"

MAX_INPUT = 4 * 1024 * 1024
MAX_RECORD = 64 * 1024
NAME = re.compile(r"[a-z][a-z0-9-]{0,31}")
PROGRAMS = ("gh", "git")
REMOTE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")        # rule 4e.8, "names"
COUNT_ENTRIES = {("git", "log"), ("git", "shortlog"), ("git", "rev-list")}   # also take -<n> (K6 fix round)
FILE_FLAGS = {"-F", "--file"}                                  # their values go through the path rule


class Unreadable(Exception):
    pass


def clean(s, most=300):
    s = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", str(s))
    return s if len(s) <= most else s[:most] + "..."


# ---------------------------------------------------------------- rule 1: the recipes, checked
def load_validator(root):
    try:
        text = open(os.path.join(root, "scripts", "check-recipe.sh"), encoding="utf-8").read()
    except OSError:
        raise Unreadable("scripts/check-recipe.sh cannot be read")
    m = re.search(r"^python3 -I - \"\$1\" <<'PY'\n(.*?)^PY$", text, re.S | re.M)
    if not m or "def check(" not in m.group(1):
        raise Unreadable("scripts/check-recipe.sh does not hold the recipe rules")
    return compile(m.group(1), "check-recipe.sh", "exec")


def validate(code, path):
    # Runs check-recipe.sh's own rules on a path, in this process: valid only if they finish and print nothing.
    said = []
    g = {"__name__": "check_recipe", "print": lambda *a, **k: said.append(" ".join(map(str, a)))}
    argv, sys.argv = sys.argv, ["check-recipe.sh", path]
    try:
        exec(code, g)
        rc = 0
    except SystemExit as e:
        rc = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
    finally:
        sys.argv = argv
    if rc != 0 or said:
        raise Unreadable(clean(said[0] if said else f"{path}: refused"))


def load_recipes(root):
    # The full check: check-recipe.sh in folder mode (every recipe, then the rules across files), run in this process.
    cdir = os.path.join(root, "connectors")
    if os.path.islink(cdir) or not os.path.isdir(cdir):
        raise Unreadable("the recipe folder cannot be read")
    validate(load_validator(root), os.path.abspath(cdir))
    out = []
    for n in sorted(os.listdir(cdir)):
        try:
            out.append(json.load(open(os.path.join(cdir, n), encoding="utf-8")))
        except (OSError, ValueError):
            raise Unreadable(f"{n} cannot be read")
    if not out:
        raise Unreadable("the recipe folder holds no recipe")
    return out


def declared_prefixes(root):
    # The prefixes hooks.json matches. A call under one that no ready recipe covers asks: its recipe is missing.
    try:
        h = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))
        return {g["matcher"][:-2] for g in h["hooks"]["PreToolUse"] if g["matcher"].endswith(".*")}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        raise Unreadable("hooks/hooks.json cannot be read")


# ---------------------------------------------------------------- terms: the project folder and the record
def folder_of(path):
    # The git top level (the nearest folder holding .git), else the folder itself (contract section 3).
    d = path
    while True:
        if os.path.lexists(os.path.join(d, ".git")):
            return d
        up = os.path.dirname(d)
        if up == d:
            return path
        d = up


def project_folder():
    # The folder Claude Code was started for: CLAUDE_PROJECT_DIR ("the project root where the session started",
    # exported to every hook), at its git top level. Not the input's cwd, which follows a cd.
    base = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if not os.path.isabs(base):
        raise Unreadable("CLAUDE_PROJECT_DIR is not set to an absolute path")
    return os.path.realpath(folder_of(os.path.realpath(base)))


def working_dir(data):
    # A shell command's working directory: the input's cwd, which "follows Claude" after a cd (To confirm 12).
    cwd = data.get("cwd")
    if not isinstance(cwd, str) or not os.path.isabs(cwd):
        raise Unreadable("the hook input has no absolute cwd")
    return os.path.realpath(cwd)


def inside(path, folder):
    return path == folder or path.startswith(folder.rstrip("/") + "/")


def no_dupes(pairs):
    seen = {}
    for k, v in pairs:
        if k in seen:
            raise ValueError("a key appears twice")
        seen[k] = v
    return seen


def record(folder):
    """<project folder>/.ade/connectors.json: the set of names it holds; an empty set when it is absent. Present but
    not valid by section 3's rules: Unreadable."""
    path = os.path.join(folder, ".ade", "connectors.json")
    if not os.path.lexists(path):
        return set()
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_RECORD:
                raise ValueError("not a regular file of at most 64 KiB")
            raw = os.read(fd, MAX_RECORD + 1)
        finally:
            os.close(fd)
        if len(raw) > MAX_RECORD:
            raise ValueError("over 64 KiB")
        r = json.loads(raw.decode("utf-8"), object_pairs_hook=no_dupes,
                       parse_constant=lambda c: (_ for _ in ()).throw(ValueError(c)))
        if not isinstance(r, dict) or set(r) != {"format", "connectors"}:
            raise ValueError("keys")
        f, c = r["format"], r["connectors"]
        if not isinstance(f, int) or isinstance(f, bool) or f != 1 or not isinstance(c, list) or len(c) > 64:
            raise ValueError("format or connectors")
        if not all(isinstance(x, str) and NAME.fullmatch(x) for x in c) or c != sorted(set(c)):
            raise ValueError("names")
    except (OSError, ValueError, UnicodeDecodeError):
        raise Unreadable(f"{clean(folder)}/.ade/connectors.json is not a valid record")
    return set(c)


# ---------------------------------------------------------------- noticing gh and git in a command line
SEP = re.compile(r"[^A-Za-z0-9_./-]+")       # rule 4b pieces: split on any character outside [A-Za-z0-9_./-]
DASHED_GIT = re.compile(r"(?:.*/)?git-[a-z0-9][a-z0-9._-]*")
MAX_FRAGS = 64                                # a word built from more parts than this counts as naming both


def pieces_of(text):
    # Rule 4b: drop ' " \ and split; $ { } = and the rest are split points, so ${IFS} leaves gh, IFS, auth, ...
    # git's dashed programs also give their name (git-credential-osxkeychain: credential-osxkeychain), for 4c.
    out = [p for p in SEP.split(re.sub(r"['\"\\\\]", "", text)) if p]
    return out + [m.group(1) for m in (re.fullmatch(r"(?:.*/)?git-(.+)", p, re.I) for p in out) if m]


def piece_names(p):
    """Rule 4b, compared in lower case (a case-insensitive file system runs GH and GIT): gh, .../gh, GH_*, GITHUB_*,
    gh's config files; git, .../git, GIT_*, git-<name>, and git's configuration and stored-credentials files (K6 fix
    round)."""
    q = p.lower()
    gh = (q == "gh" or q.endswith("/gh") or q.startswith("gh_") or q.startswith("github_")
          or q.endswith("gh/config.yml") or q.endswith("gh/hosts.yml"))
    git = (q == "git" or q.endswith("/git") or q.startswith("git_") or bool(DASHED_GIT.fullmatch(q))
           or ".git/" in q or q.endswith((".git", ".gitconfig", ".gitmodules", ".git-credentials"))
           or q == "git/credentials" or q.endswith("/git/credentials"))
    return gh, git


class LexError(Exception):
    pass


def ansi_c(body):
    simple = {"a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "n": "\n", "r": "\r", "t": "\t",
              "v": "\v", "\\": "\\", "'": "'", '"': '"', "?": "?"}
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c); i += 1; continue
        i += 1
        if i >= len(body):
            out.append("\\"); break
        e = body[i]
        if e in simple:
            out.append(simple[e]); i += 1
        elif e in "01234567":
            m = re.match(r"[0-7]{1,3}", body[i:]); out.append(chr(int(m.group(), 8) & 0xFF)); i += len(m.group())
        elif e in "xuU":
            m = re.match(r"[0-9A-Fa-f]{1,%d}" % {"x": 2, "u": 4, "U": 8}[e], body[i + 1:])
            if not m:
                out.append("\\" + e); i += 1; continue
            try:
                out.append(chr(int(m.group(), 16)))
            except (ValueError, OverflowError):
                raise LexError("escape")
            i += 1 + len(m.group())
        elif e == "c" and i + 1 < len(body):
            out.append(chr(ord(body[i + 1]) & 0x1F)); i += 2
        else:
            out.append("\\" + e); i += 1
    return "".join(out)


def match_close(s, i, open_c, close_c):
    # s[i] is just after an opening open_c; returns the index of its closing close_c (quotes skipped roughly). One
    # pass; an unbalanced line raises at once.
    depth, q = 1, None
    while i < len(s):
        c = s[i]
        if q:
            if c == "\\" and q == '"':
                i += 2; continue
            if c == q:
                q = None
        elif c == "\\":
            i += 2; continue
        elif c in "'\"":
            q = c
        elif c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise LexError("unbalanced")


PLAIN_PARAM = re.compile(r"#?(?:[A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*#?$!-])")
KEEP_COMMAND = {"then", "do", "else", "elif", "if", "while", "until", "!", "{", "time", "exec", "command", "builtin",
                "nohup", "nice", "sudo", "env", "xargs", "timeout", "eval", "watch", "doas"}
E_MARK = ("E",)
WORD_END = re.compile(r"[\s;&|()<>]")
SLASH = ("/",)
# A word on the line that reads quoted text again as a command line: with one of these, quoted text and
# here-documents count as words of the line for rule 4c (sh -c '...', eval "...", echo '...' | sh, an alias).
REREAD = {"sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh", "eval", "alias", "trap", "watch", "ssh", "su"}
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*", re.S)
GIT_FILES = (".git", ".gitconfig", ".gitmodules", ".git-credentials")
GH_FILES = ("config.yml", "hosts.yml")


def literal(f):
    # A fragment that is one literal character (re.escape of it), not a glob or a brace: that character, else None.
    if isinstance(f, str) and f != "." and (len(f) == 1 or (len(f) == 2 and f[0] == "\\")):
        return f[-1]
    return None


def can_be(frags, target, anycase=True):
    """Can a word's fragments (globs and braces included) become target? One pass over the fragments with the set of
    reachable positions, so no pattern makes it slow. A word holding an expansion or a slash cannot."""
    t = target.lower() if anycase else target
    n, pos = len(t), {0}
    for f in frags:
        ch = literal(f)
        if ch is not None:
            ch = ch.lower() if anycase else ch
            pos = {p + 1 for p in pos if p < n and t[p] == ch}
        elif f == ".*":
            pos = set(range(min(pos), n + 1))
        elif f == ".":
            pos = {p + 1 for p in pos if p < n}
        elif isinstance(f, str):                       # a brace list or a number range
            try:
                pos = {q for p in pos for q in range(p, n + 1) if re.fullmatch(f, t[p:q], re.S | (re.I if anycase else 0))}
            except re.error:
                return True
        else:
            return False
        if not pos:
            return False
    return n in pos


def config_path(frags):
    """A word with a glob or a brace that can be one of git's or gh's configuration files (.gi?/config, ~/.gitconf*,
    ~/.config/g?/hosts.yml). A part must hold literal characters, so `ls *` and `ls .*` name nothing. (gh, git)"""
    comps, cur = [], []
    for f in frags:
        if f == SLASH:
            comps.append(cur); cur = []
        else:
            cur.append(f)
    comps.append(cur)
    lits = [sum(1 for f in c if literal(f) is not None) for c in comps]
    git = any(c and literal(c[0]) == "." and k >= 2 and any(can_be(c, t) for t in GIT_FILES)
              for c, k in zip(comps, lits))
    gh = any(lits[i - 1] >= 1 and lits[i - 1] + lits[i] >= 2 and can_be(comps[i - 1], "gh")
             and any(can_be(comps[i], t) for t in GH_FILES) for i in range(1, len(comps)))
    return gh, git


class Notice:
    """What a line names, and its pieces for rule 4c: `hard`, from unquoted top-level words and substitutions (a deny
    run there is refused); `soft`, every piece, quoted text, here-documents and flag values included (a deny run found
    only there asks, so a person can approve a mention). `patterns`: the hard words that hold a glob or a brace, which
    the shell can turn into a word the line does not show (a file named token, or -t)."""
    def __init__(self):
        self.gh = self.git = False
        self.hard, self.soft = set(), set()
        self.patterns = {}                         # hard words holding a glob or a brace (4c)

    def both(self):
        self.gh = self.git = True


def notice(cmd, depth=0, n=None, hard=True):
    n = n or Notice()
    if depth > 4:
        n.both(); return n
    raw = pieces_of(cmd)
    for p in raw:
        a, b = piece_names(p); n.gh |= a; n.git |= b
    n.soft.update(raw)
    try:
        words, quoted, subs = lex(cmd)
    except LexError:
        n.both()
        if hard:
            n.hard.update(raw)
        return n
    for w in words:
        if w["opaque"]:
            n.both()
        if w["lone"]:
            if w["cmdpos"]:
                n.both()
            continue
        for prog in PROGRAMS:
            if could_be(w["frags"], prog):
                setattr(n, prog, True)
        if w["pattern"]:
            a, b = config_path(w["frags"]); n.gh |= a; n.git |= b
        if not hard:
            continue
        text = w["text"]
        if text.startswith("-") and "=" in text:
            n.hard.update(pieces_of(text.split("=", 1)[0]))   # the flag is a word of the line; its value is not
        elif not w["spaced_quote"] or (ASSIGNMENT.fullmatch(text) and w["literal_start"]):
            n.hard.update(pieces_of(text))             # a variable's value can be split into words later (x='..'; $x)
        if w["pattern"] and not w["spaced_quote"]:
            n.patterns[tuple(w["frags"])] = None
    n.soft.update(n.hard)
    reread = hard and any(not w["spaced_quote"] and os.path.basename(w["text"]).lower() in REREAD for w in words)
    for q in quoted:
        notice(q, depth + 1, n, hard=reread)
    for q in subs:
        notice(q, depth + 1, n, hard=hard)
    return n


def could_be(frags, prog):
    """frags: one word's regex fragments; E_MARK is an expansion, SLASH a literal slash. Can the word, or a literal
    run between unquoted expansions (the shell splits there), be prog or a path ending in it? Any case."""
    if len(frags) > MAX_FRAGS:
        return True
    runs, cur = [], []
    for f in frags:
        if f == E_MARK:
            runs.append(cur); cur = []
        else:
            cur.append(f)
    runs.append(cur)
    cands = [frags] + (runs if len(runs) > 1 else [])
    try:
        for c in cands:
            rx = "".join(".*" if f == E_MARK else "/" if f == SLASH else f for f in c)
            if c and re.fullmatch(rx, prog, re.S | re.I):
                return True
            if SLASH in c:
                last = len(c) - 1 - c[::-1].index(SLASH)
                tail = c[last + 1:]
                if tail and not all(f in (".*", E_MARK) for f in tail):
                    trx = "".join(".*" if f == E_MARK else f for f in tail)
                    if re.fullmatch(trx, prog, re.S | re.I):
                        return True
    except re.error:
        return True
    return False


def lex(s):
    """Splits a line into shell words, each a dict: frags (regex fragments), lone (a single expansion), cmdpos,
    opaque, text (its literal text, an expansion as a space), spaced_quote (a quoted part holds white space) and
    pattern (it holds a glob or a brace).
    Also returns the quoted texts and here-document bodies (read again as soft), and the substitutions (read again
    as top-level)."""
    words, quoted, subs, heredocs = [], [], [], []
    st = {"frags": [], "text": [], "kinds": [], "opaque": False, "spaced": False, "pattern": False}
    cmdpos = True
    i, n = 0, len(s)

    def reset():
        st.update(frags=[], text=[], kinds=[], opaque=False, spaced=False, pattern=False)

    def L(text, quoted_part=False):
        if quoted_part and re.search(r"\s", text):
            st["spaced"] = True
        for ch in text:
            st["frags"].append(SLASH if ch == "/" else re.escape(ch)); st["text"].append(ch); st["kinds"].append("L")

    def E():
        st["frags"].append(E_MARK); st["text"].append(" "); st["kinds"].append("E")

    def G(frag, text):
        # a glob or a brace: a fragment that is not literal text
        st["frags"].append(frag); st["text"].append(text); st["kinds"].append("L"); st["pattern"] = True

    def end(sep):
        nonlocal cmdpos
        k = st["kinds"]
        if k:
            text = "".join(st["text"])
            lone = len(k) == 1 and k[0] == "E"
            words.append({"frags": st["frags"], "lone": lone, "cmdpos": cmdpos, "opaque": st["opaque"],
                          "text": text, "spaced_quote": st["spaced"], "pattern": st["pattern"],
                          "literal_start": k[0] == "L"})
            assign = bool(ASSIGNMENT.fullmatch(text)) and k[0] == "L"
            cmdpos = (cmdpos and assign) or text in KEEP_COMMAND
        reset()
        if sep is not None and sep in ";&|(\n\r":
            cmdpos = True

    def dollar(i, in_dq):
        nxt = s[i + 1] if i + 1 < n else ""
        if nxt == "'" and not in_dq:
            j = i + 2
            while j < n and s[j] != "'":
                j += 2 if s[j] == "\\" else 1
            if j >= n:
                raise LexError("unterminated $'")
            text = ansi_c(s[i + 2:j]); L(text, True); quoted.append(text); return j + 1
        if nxt == "{":
            j = match_close(s, i + 2, "{", "}")
            if not PLAIN_PARAM.fullmatch(s[i + 2:j]):
                st["opaque"] = True
            E(); return j + 1
        if nxt == "(":
            j = match_close(s, i + 2, "(", ")")
            subs.append(s[i + 2:j]); E(); return j + 1
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-]", s[i + 1:])
        if m:
            E(); return i + 1 + len(m.group())
        L("$"); return i + 1

    def heredoc_start(i):
        # s[i:i+2] is an unquoted << (not <<<): note its delimiter; the body starts after the next newline.
        j = i + 2
        strip = j < n and s[j] == "-"
        j += 1 if strip else 0
        while j < n and s[j] in " \t":
            j += 1
        k = j
        while k < n and s[k] not in " \t\n\r;&|()<>":
            k += 1
        delim = re.sub(r"['\"\\\\]", "", s[j:k])
        heredocs.append((delim, strip, delim == s[j:k]))  # an unquoted delimiter: the body's substitutions run
        return k

    def body_subs(b):
        # The substitutions of an unquoted here-document's body: the shell runs them, so they are read as top-level.
        i = 0
        while i < len(b):
            if b[i] == "\\":
                i += 2
            elif b.startswith("$(", i):
                j = match_close(b, i + 2, "(", ")")
                subs.append(b[i + 2:j]); i = j + 1
            elif b[i] == "`":
                k = b.find("`", i + 1)
                if k < 0:
                    raise LexError("unterminated `")
                subs.append(b[i + 1:k]); i = k + 1
            else:
                i += 1

    def heredoc_bodies(i):
        # s[i] is just after a newline: consume each pending body up to its delimiter line.
        while heredocs:
            delim, strip, expands = heredocs.pop(0)
            body = []
            while i < n:
                e = s.find("\n", i)
                line = s[i:] if e < 0 else s[i:e]
                i = n if e < 0 else e + 1
                if (line.lstrip("\t") if strip else line) == delim:
                    break
                body.append(line)
            quoted.append("\n".join(body))
            if expands:
                body_subs("\n".join(body))
        return i

    while i < n:
        c = s[i]
        if c == "#" and not st["kinds"]:
            # A comment runs to the end of the line. It is read on its own, as words of the line, so that a quote
            # or a << inside it cannot hide the lines after it.
            e = s.find("\n", i)
            e = n if e < 0 else e
            subs.append(s[i + 1:e]); i = e
        elif s.startswith("((", i) and not st["kinds"] and s.find("))", i + 2) >= 0:
            # Arithmetic: << is a shift there, not a here-document. Its text is read on its own.
            j = s.find("))", i + 2)
            end(c); subs.append(s[i + 2:j]); i = j + 2
        elif s.startswith("<<<", i):
            end(c); i += 3                               # a here-string: the next word is its text, not a delimiter
        elif s.startswith("<<", i):
            end(c); i = heredoc_start(i)
        elif c in " \t\n\r;&|()<>":
            end(c); i += 1
            if c == "\n" and heredocs:
                i = heredoc_bodies(i)
        elif c == "\\":
            if i + 1 < n and s[i + 1] == "\n":
                i += 2
            elif i + 1 < n:
                L(s[i + 1]); i += 2
            else:
                i += 1
        elif c == "'":
            j = s.find("'", i + 1)
            if j < 0:
                raise LexError("unterminated '")
            L(s[i + 1:j], True); quoted.append(s[i + 1:j]); i = j + 1
        elif c == '"':
            j, start, lit = i + 1, i + 1, []
            while True:
                if j >= n:
                    raise LexError('unterminated "')
                d = s[j]
                if d == '"':
                    break
                if d == "\\" and j + 1 < n:
                    ch = s[j + 1] if s[j + 1] in '$`"\\\n' else "\\" + s[j + 1]
                    L(ch, True); lit.append(ch); j += 2
                elif d == "$":
                    j = dollar(j, True)
                elif d == "`":
                    k = s.find("`", j + 1)
                    if k < 0:
                        raise LexError("unterminated `")
                    subs.append(s[j + 1:k]); E(); j = k + 1
                else:
                    L(d, True); lit.append(d); j += 1
            if re.search(r"\s", "".join(lit)):
                st["spaced"] = True
            quoted.append(s[start:j]); i = j + 1
        elif c == "$":
            i = dollar(i, False)
        elif c == "`":
            k = s.find("`", i + 1)
            if k < 0:
                raise LexError("unterminated `")
            subs.append(s[i + 1:k]); E(); i = k + 1
        elif c in "*?":
            G(".*" if c == "*" else ".", c); i += 1
        elif c == "[":
            k = s.find("]", i + 1, i + 258)
            if k < 0 or re.search(r"[\s;&|()<>]", s[i + 1:k]):
                L("["); i += 1
            else:
                G(".", s[i:k + 1]); i = k + 1
        elif c == "{":
            limit = min(n, i + 128)                      # bounded, so a long run of { stays linear
            m = WORD_END.search(s, i + 1, limit)
            stop = m.start() if m else limit
            k, depth = i + 1, 1
            if s.find("}", i + 1, stop) >= 0:
                while k < stop and depth:
                    depth += {"{": 1, "}": -1}.get(s[k], 0); k += 1
            body = s[i + 1:k - 1] if depth == 0 else None
            if body is None:
                if stop == limit and limit < n and not m:
                    st["opaque"] = True
                L("{"); i += 1
            elif re.fullmatch(r"-?\d+\.\.-?\d+(\.\.-?\d+)?", body):
                G(r"-?\d+", s[i:k]); i = k
            elif re.fullmatch(r".\.\..(\.\.-?\d+)?", body):
                G(".", s[i:k]); i = k
            elif "," in body and not re.search(r"[{}$`'\"\\*?\[]", body):
                G("(?:" + "|".join(re.escape(a) for a in body.split(",")) + ")", s[i:k]); i = k
            elif "," in body or ".." in body:
                G(".*", s[i:k]); i = k
            else:
                L("{"); i += 1
        else:
            L(c); i += 1
    end(None)
    return words, quoted, subs


# ---------------------------------------------------------------- rule 4c: deny, everywhere
def element_hit(e, pieces):
    if e.startswith("--"):
        return e in pieces                     # --x=<v> was split at = into --x
    if re.fullmatch(r"-[A-Za-z0-9]", e):        # a one-letter flag: alone, in a cluster, or with an attached value
        return any(p == e or (re.fullmatch(r"-[A-Za-z0-9]+", p) and e[1] in p[1:]) for p in pieces)
    return e in {p.lower() for p in pieces}     # a word, in any case (GIT CREDENTIAL can run on macOS)


def pattern_hit(e, n):
    # Can a glob or brace word of the line become element e? (touch token; gh auth t*   or a file named -t)
    for frags in n.patterns:
        if len(frags) > MAX_FRAGS:
            return True
        if re.fullmatch(r"-[A-Za-z0-9]", e):        # a one-letter flag: a pattern word that can be - and letters
            lits = [literal(f) for f in frags]
            if lits[0] in ("-", None) and E_MARK not in frags and SLASH not in frags \
                    and all(c is None or c.isalnum() for c in lits[1:]):
                return True
        elif can_be(frags, e, anycase=not e.startswith("-")):
            return True
    return False


def deny_hit(run, pieces, n=None):
    """Each element of the run matches some piece, in any order and position. With n (the line's Notice): one element,
    at most, may instead be what a glob or brace word of the line can become; a pattern alone is never a run (git
    add * stays a question)."""
    missing = [e for e in run if not element_hit(e, pieces)]
    if not missing:
        return True
    return n is not None and len(run) > 1 and len(missing) == 1 and pattern_hit(missing[0], n)


# ---------------------------------------------------------------- rule 4e: the allow-list
def chars_ok(s):
    """Rule 4e.1: read left to right with POSIX quoting. No newline or carriage return anywhere; outside quotes none of
    ; & | < > ( ) { } [ ] * ? ~ ! $ ` \\ ; inside double quotes none of $ ` \\ ! ; inside single quotes, anything."""
    if "\n" in s or "\r" in s:
        return False
    q, prev = None, " "
    for c in s:
        start, prev = prev in " \t" and q is None, c
        if q == "'":
            if c == "'":
                q = None
        elif q == '"':
            if c in "$`\\!":
                return False
            if c == '"':
                q = None
        elif c in "'\"":
            q = c
        elif c in ";&|<>(){}[]*?~!$`\\" or (c == "=" and start):   # and zsh's =cmd at a word's start
            return False
    return q is None


class Entry:
    """A free entry {"words", "flags", "args"}: exact leading words, the flags it lists (an item ending in "=" takes a
    value), and its positionals: "any", "none" or "names"."""
    def __init__(self, e):
        if not isinstance(e, dict) or set(e) != {"words", "flags", "args"}:
            raise Unreadable("a free entry is not an object with words, flags and args")
        self.words, self.args = list(e["words"]), e["args"]
        self.exact = {f for f in e["flags"] if not f.endswith("=")}
        self.valued = {f[:-1] for f in e["flags"] if f.endswith("=")}
        if self.args not in ("any", "none", "names"):
            raise Unreadable("a free entry's args is not any, none or names")


def outside(word, rundir, project):
    """The path rule (K6, from the K5 sign-off): a positional starting with ~, or one that, joined to the directory the
    command runs in and resolved (links followed where they exist, the rest judged by its text), lies outside the
    project folder. Revisions, branch names and patterns resolve inside and are untouched."""
    if word.startswith("~"):
        return True
    return not inside(os.path.realpath(os.path.join(rundir, word)), project)


def accepts(entry, words, rundir, project, prog=""):
    """Rule 4e.8 and the path rule: every word after the entry's words, left to right. None if accepted, else the
    reason to ask."""
    i = 0
    while i < len(words):
        w = words[i]
        if w in entry.exact:
            i += 1; continue
        if (prog, " ".join(entry.words)) in COUNT_ENTRIES and re.fullmatch(r"-[0-9]+", w):
            i += 1; continue
        if w in entry.valued:
            if i + 1 >= len(words) or words[i + 1].startswith("-"):
                return f"{w} needs a value"
            if w in FILE_FLAGS and outside(words[i + 1], rundir, project):
                return f"{words[i + 1]} is a path outside the project folder"
            i += 2; continue
        if w.startswith("--") and "=" in w:
            f, v = w.split("=", 1)
            if f in entry.valued and v and not v.startswith("-"):
                if f in FILE_FLAGS and outside(v, rundir, project):
                    return f"{v} is a path outside the project folder"
                i += 1; continue
            return f"{w.split('=', 1)[0]} is not a flag this entry lists with a value"
        if w == "--":
            if entry.args != "any":
                return "-- is not accepted here"
            for x in words[i + 1:]:
                if outside(x, rundir, project):
                    return f"{x} is a path outside the project folder"
            return None
        if w.startswith("-"):
            return f"{w} is not a flag this entry lists"
        if entry.args == "none":
            return f"{w}: this entry takes no arguments"
        if outside(w, rundir, project):
            return f"{w} is a path outside the project folder"
        if entry.args == "names":
            if not REMOTE_NAME.fullmatch(w) or w in (".", ".."):
                return f"{w} is not a plain remote or branch name"
            if os.path.lexists(os.path.join(rundir, w)):
                return f"{w} is also a path here"
        i += 1
    return None


def allowed(cmd, commands, project, cwd):
    """Rule 4e. None when the command passes with no decision, else the reason it asks."""
    if not chars_ok(cmd):
        return "it holds a newline, or a shell character outside the quotes that allow it"
    try:
        w = shlex.split(cmd, posix=True)
    except ValueError:
        return "it cannot be split into words"
    if not w or w[0] not in PROGRAMS or w[0] not in commands:
        return "it is not one plain gh or git command"
    prog, rest = w[0], w[1:]
    for x in rest:
        if any(any(piece_names(p)) for p in pieces_of(x)):
            return "a later word names gh or git"
    if not inside(cwd, project):
        return "its working directory is outside the project folder"
    rundir, seen = cwd, set()
    if prog == "git":
        while rest and rest[0].startswith("-"):
            g = rest[0]
            if g in seen:
                return f"git's global option {g} is given twice"
            if g == "--no-pager":
                rest = rest[1:]
            elif g == "-C" and len(rest) > 1 and rest[1]:
                d = os.path.realpath(os.path.join(cwd, rest[1]))
                if not inside(d, project):
                    return "git -C names a folder outside the project folder"
                rundir, rest = d, rest[2:]
            else:
                return f"git's global option {g} is not permitted"
            seen.add(g)
    entries = [Entry(e) for e in commands[prog].get("free", [])]
    best = None
    for e in entries:
        if rest[:len(e.words)] == e.words and (best is None or len(e.words) > len(best.words)):
            best = e
    if best is None:
        return f"it is not on the free list for {prog}"
    why = accepts(best, rest[len(best.words):], rundir, project, prog)
    return None if why is None else f"{why} ({prog} {' '.join(best.words)})"


# ---------------------------------------------------------------- decisions
def decide(decision, reason, mode):
    if decision == "ask" and mode == "bypassPermissions":
        decision = "deny"
        reason += (" The session is in bypassPermissions mode, so no one would be asked; it is refused. Run it in a "
                   "mode that prompts.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                             "permissionDecisionReason": reason}}))


def mcp(name, recipes, mode, root):
    ready = [(p, r) for r in recipes if r["state"] == "ready" for p in r["guard"]["prefixes"] if name.startswith(p)]
    if not ready:
        held = any(name.startswith(p) for r in recipes for p in r["guard"]["prefixes"])
        if not held and any(name.startswith(p) for p in declared_prefixes(root)):
            return decide("ask", f"{clean(name)} matches a prefix this guard declares, but no recipe covers it; "
                                 "approve only if you asked for it.", mode)
        return print("PASS")                         # rule 3: a held recipe's tool, or a server no recipe names
    prefix, r = ready[0]                             # prefixes never overlap (the checker's rule)
    service, tool = r["service"], name[len(prefix):]
    project = project_folder()
    if service not in record(project):               # an unreadable record raises: ask
        if UNNAMED_MCP == "none":
            return print("PASS")
        return decide("ask", f"{service} is not connected in this folder ({clean(project)}/.ade/connectors.json does "
                             f"not name it); {clean(tool)} asks, reads included.", mode)
    if tool in r["guard"]["read"]:
        return print("PASS")
    return decide("ask", f"{clean(tool)} is not on the {service} recipe's read list, so it may change something; "
                         "approve only if you asked for it.", mode)


def shell(cmd, recipes, data, mode):
    n = notice(cmd)                                  # 4b
    named = [p for p in PROGRAMS if getattr(n, p)]
    if not named:
        return print("PASS")
    soft = None
    for r in recipes:                                # 4c: every recipe, any state, any record, every mode
        for prog in named:
            for run in r["guard"].get("commands", {}).get(prog, {}).get("deny", []):
                if deny_hit(run, n.hard, n):
                    return decide("deny", f"This command can print a credential ({clean(' '.join(run))}, "
                                          f"{r['service']} recipe); the guard refuses it in every mode: {clean(cmd)}",
                                  "default")
                if soft is None and deny_hit(run, n.soft):
                    soft = run
    if soft is not None:                             # a mention in quotes, a here-document or a flag's value
        return decide("ask", f"This command mentions a credential-printing command ({clean(' '.join(soft))}) inside "
                             f"quotes, a here-document or a flag's value: {clean(cmd)}; approve only if it does not run it.",
                      mode)
    project = project_folder()
    names = record(project)                          # 4d: unreadable raises, so it asks
    commands = {}
    for r in recipes:
        if r["state"] == "ready" and r["sign_in"]["kind"] == "cli" and r["service"] in names:
            commands.update({p: c for p, c in r["guard"].get("commands", {}).items() if p in named})
    if not commands:
        if UNNAMED_CLI == "none":
            return print("PASS")
        return decide("ask", f"No gh or git service is connected in this folder; this command can run gh or git: "
                             f"{clean(cmd)}", mode)
    why = allowed(cmd, commands, project, working_dir(data))     # 4e
    if why is None:
        return print("PASS")
    return decide("ask", f"This command can run gh or git and does not pass with no question ({why}): {clean(cmd)}; "
                         "approve only if you asked for it.", mode)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else ""
    mode = "default"
    try:
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            raise Unreadable("the hook input is too large")
        data = json.loads(raw.decode("utf-8"))
        if not isinstance(data, dict):
            raise Unreadable("the hook input is not an object")
        m = data.get("permission_mode", "default")
        if not isinstance(m, str):
            raise Unreadable("permission_mode is not a string")
        mode, name = m, data.get("tool_name")
        if not isinstance(name, str):
            raise Unreadable("tool_name is not a string")
        working_dir(data)
        recipes = load_recipes(root)
        if name.startswith("mcp__"):
            return mcp(name, recipes, mode, root)
        if name in ("Bash", "Monitor"):
            ti = data.get("tool_input")
            cmd = ti.get("command") if isinstance(ti, dict) else None
            if not isinstance(cmd, str):
                raise Unreadable("tool_input.command is not a string")
            return shell(cmd, recipes, data, mode)
        return print("PASS")
    except Unreadable as e:
        return decide("ask", f"The guard could not check this call ({clean(e)}); approve only if you asked for it.",
                      mode)
    except Exception as e:
        return decide("ask", f"The guard could not check this call ({type(e).__name__}); approve only if you asked "
                             "for it.", mode)


if __name__ == "__main__":
    main()
