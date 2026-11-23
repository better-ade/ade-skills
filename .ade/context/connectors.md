# Connectors: the contract between ade-skills and ade-cli

Decided in `.ade/context/decisions/0001-connect-and-guard.md` (2026-11-22), changed by its amendment 1 (2026-11-22).
ade-skills owns the recipes and the guard; ade-cli owns `ade connect` and the project record. Facts about Claude Code
and vendors come from `docs/connectors.md`; anything else is under "To confirm before building", and a builder checks it
first. Nothing built on this contract is released yet, so amendment 1 changes format 1 itself; there is no format 2.

## What changed in amendment 1

Each line names the story that acts on it. Sections below hold the exact rule.
1. (K6) `gh` and `git` are checked against an allow-list. A `free` entry is now an object `{"words", "flags", "args"}`;
   "later flags and arguments are free" is gone. Any word starting with `-` that the entry does not list asks; a
   positional asks when the entry says `"args": "none"`, and with `"args": "names"` each positional must be a plain
   name that is not an existing path (section 4, rule 4e.8). The shell-character check is now quote-aware: `( ) ; & |
   < >` may sit inside quotes (so `-m "feat(x): y"` passes), while an unquoted glob, brace, `~` or `!`, and `$`, `` ` ``
   or `\` outside single quotes, ask (rule 4e.1).
2. (K5) The `github` recipe's `free` lists are replaced in full (section 1 example). The principle: a `gh` or `git`
   command gets no decision when it matches a listed shape that cannot reach the service with a change, cannot print a
   credential and carries only flags the entry lists; everything else that names `gh` or `git` asks. So reading
   commands and ordinary local git work are free (`add`, `commit`, `switch`, `checkout`, `restore`, `reset`, `mv`,
   `rm`, `clean`, `branch`, `tag`, `stash`, `merge`, `rebase`, `cherry-pick`, `revert`, `worktree`, `init`, each with
   its own flags), `fetch` and `pull` are free with plain remote names only, and `push`, `clone`, `ls-remote`,
   `config`, `submodule`, `remote` changes and the rest of the "Asks" list ask. `gh` keeps reading shapes only.
3. (K6) A `deny` entry matches when each of its elements matches some piece of the command, in any order; a long flag
   also matches its `=` form, a one-letter flag also matches a cluster or attached form containing it (rule 4c).
   `gh auth status -t`, `-at`, `--show-token`, `--show-token=true` are refused. The `gh` deny list gains
   `["auth","status","--show-token"]` and `["auth","status","-t"]`, in place of `["--show-token"]`; the `git` deny
   list is `["credential","fill"]`, in place of `["credential"]`.
4. (K6) `git` global options: only `--no-pager` and `-C <dir>`, each at most once, and `<dir>` must resolve to the
   project folder or inside it; `-c` and every other global option ask. The command's working directory must be the
   project folder or inside it, for `gh` and `git` alike (rule 4e).
5. (K6) Noticing `gh` and `git` also catches a piece that starts with `GH_`, `GITHUB_` (names `gh`) or `GIT_` (names
   `git`), so `export GIT_PAGER=...` is seen (rule 4b).
6. (K6) When the guard speaks: only for a `ready` recipe. A `held` recipe never causes a decision. A `ready` recipe's
   MCP tools still ask in a folder whose record does not name it. The `gh`/`git` allow-list applies only where the
   record names a `ready` `cli` service; elsewhere `gh` and `git` get no decision. `deny` entries are refused wherever
   the guard is installed, whatever the state or the record. An absent record names nothing; a record that is present
   but not valid makes those decisions ask (section 4, terms and rules 2, 4d).
7. (K6) `hooks/hooks.json` carries a matcher only for the prefixes of `ready` recipes (the test compares with those).
8. (K5, A16) The checker refuses, where it used to strip: every string in a recipe refuses Unicode control, format,
   surrogate, private-use and unassigned characters and line or paragraph separators. A recipe must be a regular file.
   New per-kind rules and cross-file rules (section 1, "Checks"). "Longest prefix wins" is gone: prefixes never overlap.
9. (K5, K6, K7) `github` and `gmail` ship `held` ("Not available until the guard's hook and the ... skill ship in
   ade-skills."); K7 flips them to `ready` and adds `sign_in.plugin`. K5 and K6 are released together, so `clickup`,
   `jira` and `linear` are `ready` in the first release that ships recipes. The rule "no recipe is `ready` in a checkout
   without the guard's hook" stays as the safety net (a checker rule).
10. (A16) The card (section 2, step 3) has fixed sentences per kind; a `plugin`-kind card says that a claude.ai
    connector for the same service is not covered by the guard.
11. (A16) `ade connect status`: a named service whose recipe is `held` is `missing (held: <held>)`.
12. (A17) The doctor check reports only for services the folder's record names. `ade setup` offers to set git's
    `safe.bareRepository=explicit` (section 4, stated limits).
13. (K5, K6, A17) To confirm 4, 6 and 9 changed; 12 to 17 are new.

## Recorded by the K6 fix round (2026-11-23), for the architect to confirm

The adversarial review of the guard (pull request #18) changed what was built against this contract in the places
below. The sections that follow still hold amendment 1's text; where they differ, this list is what ships, until the
architect folds it in or settles it otherwise. ade-cli (A16) must take points 1 and 2 before it checks a recipe.
1. **A `deny` element** may hold `_`: a word is `^[a-z][a-z0-9_-]*$` (for `oauth_token`). Flags are unchanged.
2. **The `github` recipe's `deny` lists** are, for `gh`: `["auth","token"]`, `["auth","status","--show-token"]`,
   `["auth","status","-t"]`, `["auth","git-credential"]`, `["config","get","oauth_token"]`; for `git`:
   `["credential","fill"]` and `["credential-<helper>","get"]` for `osxkeychain`, `store`, `cache`, `manager`,
   `manager-core`, `libsecret`, `oauth`, `wincred`. Its `branch` entry no longer lists `-u=` and
   `--set-upstream-to=` (they ask). The shipped recipe is the reference; the example in section 1 is amendment 1's.
3. **The hook object** carries `"timeout": 10` (seconds), next to `"onFailure": "block"`.
4. **Rule 4b** notices more: pieces are split on every character outside `[A-Za-z0-9_./-]` and compared in lower
   case; `gh`'s `config.yml` and `hosts.yml`, and git's `.git/`, `.git`, `.gitconfig`, `.gitmodules`,
   `.git-credentials` and `git/credentials` paths name the program, also through a glob or a brace.
5. **Rule 4c** refuses on the words of the line: unquoted words, substitutions, a flag before a quoted value, an
   assignment's value, and quoted text or a here-document when a shell, `eval`, `alias`, `trap`, `watch`, `ssh` or
   `su` is on the line; a word compares in any case; one element of a run may be what a glob or a brace can become.
   A run found only in other quoted text, a here-document or a flag's value **asks**, in every folder (deny under
   `bypassPermissions`). This narrows "left open" point 12 of the decision record: a commit message that mentions a
   run is a question, no longer a refusal.
6. **Rule 4e**: a word may not start with `=` (zsh's `=cmd`); `-<n>` is accepted on `git log`, `shortlog` and
   `rev-list`; the values of `-F` and `--file` go through the path rule; the path rule itself (a positional outside
   the project folder, or starting with `~`, asks) is still not in section 4's text.
The exact rules and their tests: `docs/connectors.md`, "The guard (K6)", and `tests/guard.sh`.

## 1. Recipes

One file per service: `plugins/guard/connectors/<service>.json` in ade-skills. The `guard` plugin carries them, because
its hook reads them at run time (a plugin sees only its own folder); ade-cli reads the same files from its pinned
checkout. A recipe is data: no field is run, and no field holds a secret, a client id or anything that differs per user.

| Field | Format 1 rule |
|---|---|
| `format` | `1` |
| `service` | `^[a-z][a-z0-9-]{0,31}$`, the file name without `.json` |
| `title` | the vendor's product name, at most 40 characters |
| `job` | `tickets`, `code`, `mail` or `chat` |
| `tier` | `0` to `4` (section 2) |
| `state` | `ready` or `held` |
| `held` | when `state` is `held`: one line, why, in words a person can read (at most 200 characters); absent otherwise |
| `sign_in.kind` | `plugin` (the server is declared in an ade-skills plugin), `cli` (an existing CLI sign-in) or `claude-ai` (a claude.ai connector). Any other value is refused |
| `sign_in.plugin` | the ade-skills plugin `ade connect` installs (its skill; for `plugin` also its server). Required for `plugin`; optional for `cli`; optional for `claude-ai`, and then equal to `service` |
| `sign_in.cli` | for `cli`: `gh` (the only one in format 1) |
| `sign_in.connector` | for `claude-ai`: the connector name as it appears in tool names, `^[A-Za-z0-9_]{1,40}$` |
| `sign_in.admin` | optional: what an administrator must do, one line; required when `tier` is `4` |
| `questions` | at most 2 objects `{"id", "ask", "to"}`; `id` a name, `ask` one line, `to` is `gate` (a yes/no that must be yes to go on; the answer is stored nowhere) |
| `guard.prefixes` | the tool-name prefixes this service's tools carry. `plugin`: only `mcp__plugin_<p>_<s>__` forms, and `mcp__plugin_<plugin>_<plugin>__` must be one. `claude-ai`: exactly one, `mcp__claude_ai_<connector>__`. `cli`: `[]` |
| `guard.read` | exact tool names (no patterns) that get no decision; for `plugin`, exactly the names in `plugins/<plugin>/hooks/read-tools.txt`; for `cli`, `[]` |
| `guard.commands` | for `cli` only, required there: `{"gh": {"free": [<entry>, ...], "deny": [<run>, ...]}, "git": {...}}`, keys only `gh` and `git` (section 4, rule 4) |
| `hosts` | the vendor host names its server answers at (the doctor check uses them) |
| `pages` | `{"docs": "https://...", "revoke": "https://..."}`, each a vendor page read on the day; either may be absent |
| `reaches` | one line: what it can read and change, shown before sign-in |

### Checks

K5's test and ade-cli (A16) apply all of these; the guard applies them too (a failure is rule 1: ask). Any failure
rejects the recipe; a cross-file failure rejects the whole folder.
- **The file.** A regular file, checked on the open file (opened without following a link, then `fstat`): no
  symlink, FIFO, device or socket. `plugins/guard/connectors` itself is a directory, not a symlink. At most 64 KiB.
- **The JSON.** Unknown keys (in the recipe and in every object inside it, `free` entries included), wrong types or a
  second copy of a key reject the recipe.
- **Text.** Every string value refuses characters in the Unicode categories Cc (control), Cf (format, which includes
  the direction-changing marks), Cs (surrogate), Co (private use), Cn (unassigned), Zl and Zp (line and paragraph
  separators). Refused, not stripped: a recipe whose text needs cleaning is wrong. K5's test also holds the shipped
  recipes to ASCII, so checkers on different Unicode versions never disagree about them.
- **Per kind.** `claude-ai`: the one prefix is `mcp__claude_ai_<connector>__` with `<connector>` equal to
  `sign_in.connector`; `sign_in.plugin`, when present, equals `service`. `cli`: `guard.prefixes` and `guard.read` are
  `[]`, `guard.commands` is present. `plugin` and `claude-ai`: no `guard.commands`.
- **`guard.commands` entries.** `words`: 1 to 3 words, each `^[a-z][a-z0-9-]*$`; no two `free` entries of one program
  have the same `words`. `flags`: `-` alone, or items matching
  `^(-[A-Za-z0-9]+|--[a-z0-9][a-z0-9-]*)(=[A-Za-z0-9._,-]*)?$`, no duplicates. `args`: `any`, `none` or `names`. `deny`: runs of 1 to 4 elements, each `^[a-z][a-z0-9-]*$`, `^-[A-Za-z0-9]$` or
  `^--[a-z0-9][a-z0-9-]*$`.
- **Across files.** No prefix of one recipe equals or starts with a prefix of another recipe. No two recipes share a
  `sign_in.connector` or a `sign_in.plugin`. At most one recipe carries `guard.commands.gh`, and at most one
  `guard.commands.git`. If the checkout has no `plugins/guard/hooks/hooks.json` or no `plugins/guard/hooks/guard.sh`,
  every recipe is `held` (a recipe is never `ready` in a release without the guard's hook).

**Client ids.** A vendor's published client id for public clients is not a secret, but it is per vendor app, so it
goes only where Claude Code documents it, the plugin's `.mcp.json` `oauth.clientId`, and only after the owner allows it
(Slack, open). It is never in a recipe, an environment variable or a command line. Format 1 has no field for one.

**Pinning and verification (ade-cli).** Recipes are read only from the ade-skills checkout at `ADE_SKILLS_REF`, which
must be a `vX.Y.Z` tag (another ref is refused for `ade connect`). From the first ade-skills release that ships recipes
(`CONNECT_SINCE`, hard-coded in `ade`), that release's `release.json` (component `ade-skills`, version the pin) names a
`sha256` for each recipe as `connector-<service>.json`; ade compares the checked-out file with it. No manifest, a wrong
component or version, or a mismatch: nothing runs, exit 2. ade-skills' `release.yml` publishes each recipe under that
name. This proves integrity, not authenticity (the residual risk A12 states).

### Example: `jira` (tier 0)
```json
{
  "format": 1, "service": "jira", "title": "Jira", "job": "tickets", "tier": 0, "state": "ready",
  "sign_in": { "kind": "plugin", "plugin": "jira" },
  "questions": [],
  "guard": {
    "prefixes": ["mcp__plugin_jira_jira__"],
    "read": ["atlassianUserInfo", "getAccessibleAtlassianResources", "discover", "getJiraIssue", "listJiraProjects",
             "listJiraProjectIssueTypesMetadata", "getJiraIssueTypeMetaWithFields", "listJiraIssueTransitions",
             "listJiraIssueLinkTypes", "listJiraIssueRemoteIssueLinks", "listJiraIssueWorklogs", "lookupJiraAccountId",
             "listJiraIssueAssignableUsers", "listJiraIssueComments", "listJiraIssueChangelogs", "getJiraCurrentUser",
             "getJiraUser", "listJiraStatuses", "listJiraProjectComponents", "getJiraProjectVersions",
             "getJiraProjectVersionRelatedWork", "listJiraBoards", "getJiraBoardConfig", "getJiraBoardIssueData",
             "getJiraBoardSprintData", "listJiraBoardSprints", "listJiraFilters", "listJiraDashboards",
             "getJiraEntityProperty", "downloadJiraIssueAttachment", "searchJiraIssuesUsingJql"]
  },
  "hosts": ["mcp.atlassian.com"],
  "pages": { "docs": "https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/",
             "revoke": "https://id.atlassian.com/manage-profile/apps" },
  "reaches": "Every Atlassian app you can reach on the sites you allow, with your permissions; changes ask each time."
}
```
K5 and K6 are released together, so `jira`, `clickup` and `linear` are `ready` in the first release that ships
recipes. In a checkout without the guard's hook the checker refuses a `ready` recipe (section 1, "Across files").

### Example: `github` (tier 2, through `gh`)
```json
{
  "format": 1, "service": "github", "title": "GitHub", "job": "code", "tier": 2, "state": "held",
  "held": "Not available until the guard's hook and the GitHub skill ship in ade-skills.",
  "sign_in": { "kind": "cli", "cli": "gh" },
  "questions": [],
  "guard": {
    "prefixes": [], "read": [],
    "commands": {
      "gh": {
        "free": [
          {"words": ["pr", "view"],        "flags": ["--repo=", "-R=", "--json=", "--comments"], "args": "any"},
          {"words": ["pr", "list"],        "flags": ["--repo=", "-R=", "--json=", "--limit=", "-L=", "--state=", "--label=",
                                                     "--author=", "--assignee=", "--base=", "--head=", "--search="], "args": "none"},
          {"words": ["pr", "diff"],        "flags": ["--repo=", "-R=", "--name-only", "--patch"], "args": "any"},
          {"words": ["pr", "checks"],      "flags": ["--repo=", "-R=", "--required"], "args": "any"},
          {"words": ["pr", "status"],      "flags": ["--repo=", "-R=", "--json="], "args": "none"},
          {"words": ["issue", "view"],     "flags": ["--repo=", "-R=", "--json=", "--comments"], "args": "any"},
          {"words": ["issue", "list"],     "flags": ["--repo=", "-R=", "--json=", "--limit=", "-L=", "--state=", "--label=",
                                                     "--author=", "--assignee=", "--search="], "args": "none"},
          {"words": ["issue", "status"],   "flags": ["--repo=", "-R=", "--json="], "args": "none"},
          {"words": ["repo", "view"],      "flags": ["--json=", "--branch="], "args": "any"},
          {"words": ["repo", "list"],      "flags": ["--json=", "--limit=", "-L="], "args": "any"},
          {"words": ["run", "view"],       "flags": ["--repo=", "-R=", "--json=", "--log", "--log-failed", "--job=", "--attempt="], "args": "any"},
          {"words": ["run", "list"],       "flags": ["--repo=", "-R=", "--json=", "--limit=", "-L=", "--workflow=", "--branch=",
                                                     "--status="], "args": "none"},
          {"words": ["workflow", "view"],  "flags": ["--repo=", "-R=", "--yaml", "--ref="], "args": "any"},
          {"words": ["workflow", "list"],  "flags": ["--repo=", "-R=", "--json=", "--limit=", "-L=", "--all"], "args": "none"},
          {"words": ["release", "view"],   "flags": ["--repo=", "-R=", "--json="], "args": "any"},
          {"words": ["release", "list"],   "flags": ["--repo=", "-R=", "--json=", "--limit=", "-L="], "args": "none"},
          {"words": ["label", "list"],     "flags": ["--repo=", "-R=", "--json=", "--limit=", "-L=", "--search="], "args": "none"},
          {"words": ["search", "repos"],   "flags": ["--json=", "--limit=", "-L=", "--owner="], "args": "any"},
          {"words": ["search", "issues"],  "flags": ["--json=", "--limit=", "-L=", "--repo=", "-R=", "--state="], "args": "any"},
          {"words": ["search", "prs"],     "flags": ["--json=", "--limit=", "-L=", "--repo=", "-R=", "--state="], "args": "any"},
          {"words": ["search", "code"],    "flags": ["--json=", "--limit=", "-L=", "--repo=", "-R=", "--language="], "args": "any"},
          {"words": ["search", "commits"], "flags": ["--json=", "--limit=", "-L=", "--repo=", "-R=", "--author="], "args": "any"},
          {"words": ["auth", "status"],    "flags": [], "args": "none"}
        ],
        "deny": [["auth", "token"], ["auth", "status", "--show-token"], ["auth", "status", "-t"]]
      },
      "git": {
        "free": [
          {"words": ["status"],          "flags": ["-s", "--short", "-b", "--branch", "--porcelain", "--porcelain=v1",
                                                   "--porcelain=v2"], "args": "any"},
          {"words": ["log"],             "flags": ["--oneline", "--graph", "--decorate", "--all", "--stat", "--name-only",
                                                   "--name-status", "-p", "--patch", "--reverse", "--merges", "--no-merges",
                                                   "--first-parent", "--follow", "--no-ext-diff", "--no-textconv", "-n=",
                                                   "--max-count=", "--since=", "--until=", "--author=", "--grep=",
                                                   "--format=", "--pretty=", "--date="], "args": "any"},
          {"words": ["diff"],            "flags": ["--stat", "--name-only", "--name-status", "--cached", "--staged",
                                                   "--check", "--no-ext-diff", "--no-textconv"], "args": "any"},
          {"words": ["show"],            "flags": ["--stat", "--name-only", "--name-status", "--oneline", "--no-patch", "-s",
                                                   "--no-ext-diff", "--no-textconv", "--format=", "--pretty="], "args": "any"},
          {"words": ["blame"],           "flags": ["-w", "-e", "--porcelain", "-L="], "args": "any"},
          {"words": ["rev-parse"],       "flags": ["--show-toplevel", "--git-dir", "--abbrev-ref", "--short", "--verify",
                                                   "--symbolic-full-name", "--is-inside-work-tree"], "args": "any"},
          {"words": ["ls-files"],        "flags": ["-c", "--cached", "-m", "--modified", "-o", "--others", "-d", "--deleted",
                                                   "--exclude-standard"], "args": "any"},
          {"words": ["describe"],        "flags": ["--tags", "--always", "--long"], "args": "any"},
          {"words": ["grep"],            "flags": ["-n", "--line-number", "-i", "--ignore-case", "-l", "--files-with-matches",
                                                   "-w", "--word-regexp", "-E", "-F", "--cached", "-e="], "args": "any"},
          {"words": ["rev-list"],        "flags": ["--count", "--all", "--reverse", "--first-parent", "--merges", "--no-merges",
                                                   "--left-right", "-n=", "--max-count="], "args": "any"},
          {"words": ["merge-base"],      "flags": ["--is-ancestor", "--all", "--fork-point"], "args": "any"},
          {"words": ["cat-file"],        "flags": ["-t", "-s", "-p", "-e"], "args": "any"},
          {"words": ["ls-tree"],         "flags": ["-r", "-t", "-d", "-l", "--name-only", "--full-tree"], "args": "any"},
          {"words": ["shortlog"],        "flags": ["-s", "-n", "-e", "-sn", "--summary", "--numbered", "--email"], "args": "any"},
          {"words": ["reflog"],          "flags": ["-n=", "--date="], "args": "none"},
          {"words": ["reflog", "show"],  "flags": ["-n=", "--date="], "args": "any"},
          {"words": ["show-ref"],        "flags": ["--heads", "--tags", "--verify", "--hash", "-s"], "args": "any"},
          {"words": ["for-each-ref"],    "flags": ["--format=", "--sort=", "--count="], "args": "any"},
          {"words": ["diff-tree"],       "flags": ["-r", "--name-only", "--name-status", "--no-commit-id", "--stat",
                                                   "--no-ext-diff", "--no-textconv"], "args": "any"},
          {"words": ["name-rev"],        "flags": ["--name-only", "--tags"], "args": "any"},
          {"words": ["check-ignore"],    "flags": ["-v", "--verbose", "-n", "--non-matching", "--no-index"], "args": "any"},
          {"words": ["stash", "list"],   "flags": [], "args": "none"},
          {"words": ["stash", "show"],   "flags": ["-p", "--patch", "--stat", "--name-only"], "args": "any"},
          {"words": ["worktree", "list"],"flags": ["--porcelain", "-v", "--verbose"], "args": "none"},
          {"words": ["remote"],          "flags": ["-v", "--verbose"], "args": "none"},
          {"words": ["remote", "get-url"],"flags": ["--push", "--all"], "args": "any"},

          {"words": ["add"],             "flags": ["-A", "--all", "-u", "--update", "-N", "--intent-to-add"], "args": "any"},
          {"words": ["commit"],          "flags": ["-m=", "--message=", "-F=", "--file=", "-a", "--all", "--amend", "--no-edit",
                                                   "--allow-empty", "-s", "--signoff"], "args": "any"},
          {"words": ["switch"],          "flags": ["-c=", "--create=", "--detach", "-"], "args": "any"},
          {"words": ["checkout"],        "flags": ["-b=", "-B=", "--detach", "-"], "args": "any"},
          {"words": ["restore"],         "flags": ["--staged", "--worktree", "--source="], "args": "any"},
          {"words": ["reset"],           "flags": ["--soft", "--mixed", "--hard", "--keep"], "args": "any"},
          {"words": ["mv"],              "flags": ["-f", "-k"], "args": "any"},
          {"words": ["rm"],              "flags": ["-r", "-f", "--cached"], "args": "any"},
          {"words": ["clean"],           "flags": ["-n", "--dry-run", "-f", "--force", "-d", "-fd", "-df", "-nd", "-dn"], "args": "any"},
          {"words": ["branch"],          "flags": ["-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "--show-current",
                                                   "--list", "-d", "--delete", "-D", "-m", "--move", "-M", "-c", "--copy",
                                                   "-u=", "--set-upstream-to=", "--unset-upstream"], "args": "any"},
          {"words": ["tag"],             "flags": ["-l", "--list", "-a", "--annotate", "-m=", "--message=", "-d", "--delete"], "args": "any"},
          {"words": ["stash"],           "flags": ["-u", "--include-untracked", "-m=", "--message="], "args": "none"},
          {"words": ["stash", "push"],   "flags": ["-u", "--include-untracked", "--staged", "-m=", "--message="], "args": "any"},
          {"words": ["stash", "pop"],    "flags": ["--index"], "args": "any"},
          {"words": ["stash", "apply"],  "flags": ["--index"], "args": "any"},
          {"words": ["stash", "drop"],   "flags": [], "args": "any"},
          {"words": ["merge"],           "flags": ["--no-ff", "--ff-only", "--squash", "--no-edit", "--abort", "--continue",
                                                   "-m=", "--message="], "args": "any"},
          {"words": ["rebase"],          "flags": ["--continue", "--abort", "--skip", "--onto="], "args": "any"},
          {"words": ["cherry-pick"],     "flags": ["--continue", "--abort", "--skip", "--no-edit", "--no-commit"], "args": "any"},
          {"words": ["revert"],          "flags": ["--continue", "--abort", "--skip", "--no-edit", "--no-commit"], "args": "any"},
          {"words": ["worktree", "add"], "flags": ["-b=", "-B=", "--detach"], "args": "any"},
          {"words": ["worktree", "remove"],"flags": ["-f", "--force"], "args": "any"},
          {"words": ["worktree", "prune"],"flags": ["-n", "--dry-run", "-v", "--verbose"], "args": "none"},
          {"words": ["init"],            "flags": ["-b=", "--initial-branch=", "-q", "--quiet"], "args": "any"},

          {"words": ["fetch"],           "flags": ["--all", "--prune", "--tags", "--no-tags"], "args": "names"},
          {"words": ["pull"],            "flags": ["--ff-only", "--rebase", "--no-rebase", "--prune", "--tags"], "args": "names"}
        ],
        "deny": [["credential", "fill"]]
      }
    }
  },
  "hosts": ["api.githubcopilot.com"],
  "pages": {},
  "reaches": "Every repository your gh sign-in can reach; pushing and every change on GitHub ask each time."
}
```
The `git` list has three groups, separated by a blank line: reading, ordinary local work, and `fetch`/`pull`.
K7 sets `state` to `ready`, removes `held`, adds `"plugin": "github"` (a skill-only plugin) and the `gh` and revoke
pages from GitHub's own documentation. `hosts` lets the doctor find GitHub's hosted server added by hand. The flag
lists are a starting point: the K5 builder checks each against `gh <cmd> --help` and `git <cmd> -h` on the day (To
confirm 15) and drops any flag that writes a file outside the repository's own state, opens a browser, runs a
program, is interactive, prints a token, reads the environment, or, for `git`, pushes or names another place to fetch
from. A flag left off only asks.

**The principle.** A `gh` or `git` command gets no decision when it matches a listed shape that cannot reach the
service with a change, cannot print a credential and carries only flags the entry lists; everything else that names
`gh` or `git` asks. *Reason:* the guard's promise is about GitHub and tokens ("every change through this service
asks"). Local work never reaches the service, and the guard is not a sandbox: the shell tool can already run any
program and write any file under Claude Code's own permission rules, so a question on `git commit` would protect
nothing and, since a hook's `ask` overrides the project's allow rules, would make builders switch the guard off. What
the review showed dangerous was a flag riding on a free word; the per-entry flag list closes that. Hooks in
`.git/hooks` that local commands run are the project's own (stated limits, section 4).

Flags left off on purpose, so they ask: `--web`/`-w` (starts the browser); `--jq`/`-q` (gh's jq can read the
environment, tokens included); `--template`/`-t` (a template language the guard cannot vet, and `-t` prints the token
on `gh auth status`); every `git` flag that writes a file outside the repository's own state (`--output`), runs a
program (`-O`, `--open-files-in-pager`, `--ext-diff`, `--textconv`, `-x`, `--exec`, `--upload-pack`, `-s`/`--strategy`
on `merge`, which names a `git-merge-<name>` program), is interactive (`-p`, `-i`, `--interactive`, `--edit-description`)
or has another meaning elsewhere and is not needed (`-x` on `cherry-pick` and `clean`: one meaning per letter);
`--no-verify` on `commit` (it skips the project's own checks, often a secret scan; rare enough that a question costs
little); `--recurse-submodules` (it reaches URLs named in a committed file).

**Asks** (no entry), because it reaches the remote with a change, changes where the remote is, changes configuration
that later runs a program, discards history beyond the reflog, or is too open to list: `git push`, `clone`,
`ls-remote`, `remote` with `add`, `set-url`, `remove`, `rename`, `set-head`, `prune`, `update` or `show` (only
`remote -v` and `remote get-url` are free), `submodule`, `config`, `archive`, `bundle`, `send-email`, `request-pull`,
`filter-branch`, `bisect`, `difftool`, `mergetool`, `gui`, `daemon`, `instaweb`, `svn`, `p4`, `fast-import`,
`update-ref` (writes any ref with no checks; rare), `notes` (rare, with subcommands of its own), `gc` (its prune is the
one local step that makes lost work unrecoverable), `maintenance` (`start` registers a scheduled job outside the
repository), `stash clear` (drops every stash at once), `worktree move` and `lock`, any alias, any external
`git-<name>` command, and every `gh` command that is not a listed reading shape (`gh api`, `pr create`, `pr merge`,
extensions, ...). `git credential fill` is denied (rule 4c).

**`fetch` and `pull`.** Free, with `"args": "names"`: each positional must be a plain name (rule 4e.8), so no URL, no
path and no refspec rides along, and the program-running options are not on the list. *Reason:* they change nothing on
the service and agents use them constantly. `pull` then merges or rebases locally, which is local work. `push` always
asks.

### Example: `gmail` (tier 2, a claude.ai connector)
```json
{
  "format": 1, "service": "gmail", "title": "Gmail", "job": "mail", "tier": 2, "state": "held",
  "held": "Not available until the guard's hook and the Gmail skill ship in ade-skills.",
  "sign_in": { "kind": "claude-ai", "connector": "Gmail" },
  "questions": [{ "id": "added", "to": "gate",
                  "ask": "Have you added the Gmail connector to your Claude account and signed in to it there?" }],
  "guard": {
    "prefixes": ["mcp__claude_ai_Gmail__"],
    "read": ["get_message", "get_thread", "search_threads", "list_labels", "list_drafts", "get_draft"]
  },
  "hosts": ["gmailmcp.googleapis.com"],
  "pages": {},
  "reaches": "The mail of the Google account signed in to the connector; drafting, labels, trash and spam ask each time."
}
```
The read names are Google's server's; the builder replaces them with the connector's own read tools, and adds the
connector's own pages (To confirm 6, 7). K7 sets `state` to `ready`, removes `held` and adds `"plugin": "gmail"`.
`hosts` lets the doctor find Google's server added by hand.

## 2. Tiers

The tier is the most the person must do before sign-in works. `ade connect` prints it in plain words.

| Tier | Means | Services today |
|---|---|---|
| 0 | nothing to set up: the vendor registers the client itself | `clickup`, `jira`, `linear` (ready from the release that ships the guard's hook, K6) |
| 1 | the vendor's published app id sits in the plugin | `slack` (held: the owner decides on the client id) |
| 2 | a sign-in the person already has | `github` through `gh`, `gmail` through the claude.ai connector (held until the guard's hook, K6, and their skills, K7, ship; K7 flips them) |
| 3 | the person's own app (client id and secret) | `discord` (held: K3's question; and step 3 is not built) |
| 4 | an administrator must act first | `outlook`, `teams` (held: tenant administrator, legacy servers) |

`ade connect <service>`, step by step:
1. Refuse unless a person is at a terminal: inside a Claude Code session, piped or without a terminal, exit 2, nothing
   changed (ade's `tty_ready`).
2. Fetch ade-skills at the pin; check the recipes (section 1, all checks, across files too). Unknown service: exit 2
   with the closest names.
3. Print the card: title, job, tier in words, `reaches`, the sentences for its kind below, and `pages.docs` when present.
   - `plugin`: `Reading needs no question; every change asks.` and `If you also add <title> as a connector to your
     Claude account, the guard does not cover that connector's tools: Claude Code's own permission settings decide for
     them, in every folder.`
   - `cli`: `Reading, fetching and ordinary local git work need no question; pushing and every other change on GitHub
     asks in this folder.`
   - `claude-ai`: `Reading needs no question; every change asks, in folders where ade installed the guard. In other
     folders, Claude Code's own permission settings decide.`
4. `held`: print `<service> is not available yet: <held>` and exit 3. Tier 4: print `Your administrator must first:
   <admin>` and `ade sends nothing; forward this yourself.`, then exit 3.
5. Ask each `questions` entry; any answer but yes stops, exit 1, nothing changed.
6. Ask `Connect <service> in <folder>? [y/N]`.
7. Install `guard@ade-skills` (and `sign_in.plugin`, when given) with `claude plugin install <name>@ade-skills --scope
   project`, recorded in `.ade/connections.json` as `ade skills add` does today.
8. By kind. `plugin` (tiers 0, 1): print the sign-in steps: open Claude Code in this folder, run `/mcp`, pick
   `plugin:<p>:<p>`, choose Authenticate, sign in in the browser; tier 1 adds the `admin` line when present.
   `cli` (`gh`): `gh` missing, exit 1 with `ade setup --tools`; not signed in, ask `Sign in to GitHub with gh now?` and
   run `gh auth login` on the terminal (ade never sees the token). `claude-ai`: nothing to run; the gate question
   covered it, and ade prints that this connector is shared by every folder of that Claude account (section 6).
9. Add the name to `.ade/connectors.json`; one journal line, `ade connect: <service> connected in <folder>`; run the
   doctor check (section 5) for this service; print `next: ade connect test <service>`. Exit 0.

## 3. Commands and the record

| Command | Where it runs | Does | Exit |
|---|---|---|---|
| `ade connect` | anywhere | one row per recipe: `service job tier state here` (`here` = `connected` or `-`), then the tier key | 0; 2 pin not verified |
| `ade connect <service>` | terminal only | section 2 | 0, 1, 2, 3 |
| `ade connect status [<service>]` | anywhere, reads only | one line per connector in the record | 0 all ready; 1 a gap |
| `ade connect test <service>` | terminal only | one harmless read (below) | 0 passed; 1 failed; 2 refused |
| `ade connect disconnect <service>` | terminal only | sign out here (below) | 0; 1 failed; 2 refused |
| `ade connect --check` | anywhere, reads only | `this folder expects <names>`, then the status lines and the doctor lines | 0 no gap; 1 a gap; 2 record invalid |

Status lines: `connector <service>[ in <folder>]: <state>[ (<detail>)]`, `<state>` one of `ready`, `missing` (plugin,
guard or `gh` sign-in absent; or the recipe is `held`, detail `held: <held>`, because the guard says nothing for a held
service), `unknown` (ade cannot read the sign-in: plugin servers and claude.ai connectors) or `outside` (a server of
this vendor sits outside the guard). `missing` and `outside` are gaps; `unknown` is not.

`test`: `cli` runs `gh auth status`. `plugin` and `claude-ai` run Claude Code once with `-p` in the folder, asking it
to call one tool from `guard.read` (the first) and report only whether it answered; prompts cannot show in `-p`, so a
change cannot go ahead. ade prints `<service>: test passed` or `<service>: test failed (<reason>)`, never content.

`disconnect`: `plugin` runs `claude mcp logout plugin:<p>:<p>` and prints `pages.revoke`. `cli` and `claude-ai` change
nothing (that sign-in is shared beyond this folder) and print how to sign out at its source (`gh auth logout`, the
claude.ai connector settings). The record is not changed: it says what the project uses, for everyone; dropping a
connector from a project is a reviewed edit of `.ade/connectors.json`.

**The record**: `<folder>/.ade/connectors.json`, committed, names only, kept apart from `.ade/connections.json` so an
older `ade` (which rejects a connections record with an unknown key) keeps working:
```json
{ "format": 1, "connectors": ["github", "jira"] }
```
`connectors` sorted, unique, at most 64 names `^[a-z][a-z0-9-]{0,31}$`; at most 64 KiB; anything else rejects the
whole file, as A10's record. `<folder>` is the git top level, else the current folder (as `ade skills`).

- `ade restore`: reads `.ade/connectors.json` in each folder `conn_dirs` finds (which also accepts a folder that has
  only this file); a `missing` connector is a gap; with a yes it runs section 2 from step 3 for it, after the plugins.
- `ade doctor`: runs the `--check` lines for every such folder before the hub's `bin/doctor`, plus one line when
  `claude --version` is below 2.1.295 (`onFailure` absent: a failing guard would let the call go ahead).
- `ade setup`: `setup_check` prints `connectors: <n> expected, <m> ready`; the setup guide's prompt tells the person
  which `ade connect <service>` to run at their terminal and never runs it. It also offers, with a yes, to set
  `safe.bareRepository=explicit` in the person's global git config, and `setup_check` reports whether it is set
  (A17; section 4, stated limits; To confirm 16).

## 4. The guard

One plugin, `guard@ade-skills`: `hooks/hooks.json`, `hooks/guard.sh` (bash and python3, the shipped script's
hardening: exactly one JSON object or nothing, never `allow`, no network), and `connectors/*.json`. Groups on
`PreToolUse`, each `{"type": "command", "command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"],
"onFailure": "block"}`:
- one matcher `<prefix>.*` for every prefix of every `ready` recipe (a test checks the set equals the `ready` recipes'
  prefixes). A `held` recipe has no matcher, so a guard that fails never blocks a tool it makes no claim on;
- one matcher `Bash`.

Terms. The **project folder**: the folder Claude Code was started for, from the hook input (To confirm 4). The
**record**: `<project folder>/.ade/connectors.json`. Absent, it names nothing. Present but not valid by section 3's
rules, it is **unreadable**. A service is **connected here** when its recipe is `ready` and the record names it.

Decisions, in order. "Ask" means `permissionDecision` `ask`, or `deny` naming the mode when `permission_mode` is
`bypassPermissions`; the reason names the tool or command.
1. Input it cannot read, or a recipe folder that fails any check of section 1 (one file or across files): ask.
2. (a, b) A tool whose name starts with a prefix of a `ready` recipe (prefixes never overlap, so at most one matches):
   - record unreadable: ask;
   - the record does not name that service: ask (`<service> is not connected in this folder`). *Reason:* a claude.ai
     connector or a vendor's own plugin is shared by every folder; where the guard is installed, it keeps such tools to
     the folders that chose them (customer separation);
   - the record names it: a name on `guard.read` gets no decision, any other asks.
   This covers plugin-declared servers (ade-skills' and a vendor's own) and claude.ai connectors alike.
3. Any other MCP tool, including one under a `held` recipe's prefix: no decision. *Reason:* the guard claims nothing
   for a service that cannot be connected; a person's own vendor plugin keeps working. For an unknown server, the guard
   cannot tell a vendor's server from any other by name, and asking for every tool of every server would be approved
   by habit; a vendor server added by hand is the doctor check's to find (section 5).
4. (c) `Bash`:
   - **4a.** The command is `tool_input.command`; not a string: ask.
   - **4b. Noticing.** Remove `'`, `"`, `\` and `$`; split on white space and on each of `;` `&` `|` `(` `)` `<` `>`
     `=` `` ` ``; the results are the **pieces**. The command names `gh` when a piece is `gh`, ends in `/gh`, or starts
     with `GH_` or `GITHUB_`; it names `git` when a piece is `git`, ends in `/git`, or starts with `GIT_`. Names
     neither: no decision.
   - **4c. Deny, everywhere.** For each program the command names, every `deny` run of every recipe, whatever its
     `state` and whatever the record, is checked; a match gets `deny` in every mode (it prints a credential). A run
     matches when each of its elements matches some piece, in any order and position:
     a word (no leading `-`) matches an equal piece; a long flag `--x` matches an equal piece (so `--x=<v>`, split at
     `=`, matches too); a one-letter flag `-x` matches the piece `-x` and any piece that is `-` followed only by
     letters and digits and contains `x` (a cluster such as `-at`, an attached value such as `-tfoo`).
     Refused, for example: `gh auth token`, `gh auth status -t`, `gh auth status -at`, `gh auth status --show-token`,
     `gh auth status --show-token=true`, `gh auth status <another flag> -t`, `git credential fill`.
     *Reason for "any order":* a flag can sit between or before the words; a run that matches too much
     (a `git commit` whose message holds both `credential` and `fill` is refused) costs a rephrase, one that matches too little prints a token.
   - **4d. Scope.** Record unreadable: ask. No recipe connected here, of kind `cli`, has `guard.commands` for a program
     the command names: no decision. *Reason:* in a folder that did not connect GitHub, the guard claims nothing for
     `gh` and `git` beyond 4c.
   - **4e. The allow-list.** No decision only when all of these hold, else ask:
     1. the raw string, read left to right with POSIX quoting, has no newline or carriage return anywhere; outside
        quotes, none of `; & | < > ( ) { } [ ] * ? ~ ! $` `` ` `` `\`; inside double quotes, none of `$` `` ` `` `\`
        `!`; inside single quotes, anything. *Reason:* quoted text reaches the program as written, except those
        characters inside double quotes; unquoted globs, braces and `~` expand into words the guard never sees (a file
        named `-Ofoo` matched by `*`), and the rest make a compound or a substitution. So `git commit -m "feat(x): y"`
        passes, and `git stash pop stash@{1}` asks unless the ref is quoted;
     2. `shlex.split` (POSIX) succeeds; its words are W;
     3. W's first word is exactly `gh` or `git`, and the recipe of 4d has `guard.commands` for it; its `free` entries
        are the ones used below;
     4. no later word names `gh` or `git` (4b's test, applied to the word);
     5. the command's working directory (To confirm 12), with links resolved, is the project folder or inside it.
        *Reason:* outside it, a repository's own config (which came in with a clone) can run programs (`core.pager`,
        `core.fsmonitor`, `diff.external`, `include.path`), and `gh` works on that directory's repository too;
     6. global options: `gh` has none (its next word must begin an entry's `words`). For `git`, while the next word
        starts with `-`: `--no-pager` is taken; `-C` is taken with the word after it as `<dir>`; anything else asks
        (`-c`, `--git-dir`, `--work-tree`, `--exec-path`, `-p`, `-C<dir>`, ...). Each at most once. `<dir>` must not be
        empty, and resolved against the working directory with links followed it must be the project folder or inside
        it. *Reason:* `-C` is how an agent reaches a sub-folder without `cd`, and the same rule as 5 applies;
     7. an entry matches: its `words` equal the next words; of several, the one with the most words. None: ask;
     8. every later word is accepted by that entry, read left to right:
        - a word equal to an item of `flags` that does not end in `=`: accepted (so `--porcelain=v2`, `-fd` and `-`
          alone can be listed);
        - an item `F=` (a flag that takes a value): the word `F` is accepted with the next word as its value, which
          must exist and must not start with `-`. When `F` starts with `--`, the single word `F=<value>` is accepted
          too, with `<value>` not empty and not starting with `-`. A one-letter `F` has no other form (`-R=x` and
          `-Rx` ask). No abbreviation, no cluster: `--rep`, `-av` ask unless listed exactly;
        - `--`: accepted only when the entry says `"args": "any"`; every later word is then a positional, even one
          starting with `-`. *Reason:* `git log -- <path>` is the plain way to name a path;
        - any other word starting with `-`, `-` alone included: ask;
        - any other word is a positional: accepted when the entry says `"args": "any"`; ask when `"none"`; when
          `"names"`, accepted only if it matches `^[A-Za-z0-9][A-Za-z0-9._-]*$` (no `/`, `:` or `@`; not `.` or `..`)
          and no file or folder of that name exists in the directory git runs in (the `-C` `<dir>` when given, else
          the working directory). *Reason:* a word that is not a configured remote is read as a path or a URL, and
          that is how a hostile repository would be reached. So `git pull origin main` passes and
          `git pull origin feature/x` asks.

   Rules for writing entries (K5's builder; a reviewer checks them): an entry for a command that has subcommands of its
   own says `"args": "none"` or names the subcommand in `words`, so a word after it is a positional and asks
   (`git remote -v add x <url>`: `add` is a positional of `remote`, which says `none`). In an `"args": "none"` entry,
   `F=` is used only for a flag whose value is required; a flag whose value is optional is listed only as exact words
   (else the guard would take the next word as a value while the program reads it as a positional or a subcommand).
   In an `"args": "any"` entry that mismatch is harmless, since a positional is accepted anyway. `"names"` is for
   commands whose positionals name a remote and a branch (`fetch`, `pull`); `--` is never accepted there.

So, in a folder where GitHub is connected, a pipeline, `&&`, `sh -c`, `xargs`, an environment prefix or a
substitution that names `gh` or `git` asks; `gh api` asks (one command reaches every endpoint); a `gh` extension asks;
`cd x && git status` asks and `git -C x status` passes when `x` is inside the project folder.

**Stated limits.** The guard is exact about what it lets through and best-effort about noticing; the fence against a
determined agent is the scope of the credential.
- A script or a git hook that calls `gh` is not seen in the command line. Free local commands (`commit`, `merge`,
  `rebase`, `pull`, `checkout`, ...) run the project's own `.git/hooks` and config; those are the project's business,
  and a hook that pushes is not seen.
- A repository nested inside the project folder whose config came in with a clone (for example a bare repository
  committed inside the project) still runs its config's programs for a free `git` command pointed into it with `-C`,
  or run from a working directory inside it. `ade setup`'s `safe.bareRepository=explicit` (A17) narrows this; it is a
  mitigation, not a guarantee.
- Config written with a file tool, not a shell command (the project's `.git/config`, the person's global git config,
  `gh`'s config), is not seen; the person's file-write permissions are the fence.
- Variables exported in an earlier call (To confirm 13) are seen only when the exporting command names a `GIT_`,
  `GH_` or `GITHUB_` variable (4b); a variable set another way is not.

The shipped per-plugin hooks (`ask-unless-read.sh` in `clickup`, `jira`, `linear`) stay as they are: a plugin stands
alone. For their prefixes the guard decides from the same list (a test checks `guard.read` equals `read-tools.txt`),
so two hooks give one answer where the folder names the service. If To confirm 3 shows two questions for one call, the
guard leaves out the prefixes of ade-skills plugins that carry their own hook, and nothing else changes.

## 5. The doctor check

Reads files only (no network, no model, no command that connects to a server). For a folder, for each service its
record names (none when the record is absent; the record unreadable is `--check`'s exit 2), it lists every MCP server
whose `url` host is in that service's recipe's `hosts`, from: `<folder>/.mcp.json` (project scope), and the user- and
local-scope servers in `${HUB_CLAUDE_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-~}}/.claude.json` (To confirm 8). A server whose
tools would not start with one of that recipe's prefixes is outside the guard:
`connector jira: outside (a server named <name>, user scope, at mcp.atlassian.com; remove it and use the plugin, or add
"mcp__<name>__*" to permissions.ask in .claude/settings.json)`. Server names are printed with control characters
removed. claude.ai connectors are not in local files; the doctor says nothing about them (the guard covers those a
`ready` recipe names).

## 6. Per folder, per user

| Sign-in | Where it lives | What the folder commits |
|---|---|---|
| `plugin` (tiers 0, 1) | the plugin is installed in project scope; Claude Code keeps the OAuth sign-in (To confirm 1) | `enabledPlugins`, `.ade/connections.json` plugins, `.ade/connectors.json` |
| `cli` (`gh`) | `gh`'s own store, one per machine user | `.ade/connectors.json` |
| `claude-ai` | the Claude account, every folder it is used in | `.ade/connectors.json` |

Nothing per user is committed or written by `ade connect` into a folder. Tier 2 sign-ins are shared by nature; in a
folder where the guard is installed, it keeps a `ready` connector's MCP tools to folders that name it (section 4, rule
2); in a folder without the guard, nothing does. If To confirm 1 shows that Claude Code keeps a plugin server's sign-in
per config folder and not per project, `ade connect` keeps `~/.config/ade/connect` (`service<TAB>config
folder<TAB>folder`, 0600, paths only) and refuses a tier 0 or 1 connect in a second folder under the same config folder,
printing that a customer folder needs its own `HUB_CLAUDE_CONFIG_DIR`.

## 7. Step 3 (the local proxy) must stay possible

Format 1 refuses unknown `kind`, `to` and `format` values, so a later `proxy` kind and a `keychain` answer (a hidden
prompt, stored by ade-secrets, never a file or variable) arrive as format 2 without an old `ade` half-running them. The
guard keys on tool-name prefixes, not server type, so a plugin whose server is a local command is covered unchanged.

## To confirm before building

Each in Claude Code's, GitHub's, git's or the vendor's own documentation, before the story that needs it.
- [ ] 1. Where Claude Code keeps a plugin server's OAuth sign-in: per config folder, per project, or both (section 6; A16).
- [ ] 2. Whether any `claude` command reads or starts a server's sign-in without the `/mcp` screen (A16 `status`).
- [ ] 3. Two `PreToolUse` hooks that both answer `ask` for one call: one question or two; `deny` over `ask` (K6).
- [ ] 4. How a hook learns the project folder: the input's `cwd`, a project-directory field or `CLAUDE_PROJECT_DIR`;
      and whether it is the git top level when Claude Code starts in a sub-folder (K6, rules 2, 4d, 4e).
- [ ] 5. claude.ai connector tool names when the connector's name has spaces or punctuation; whether they load in `-p`
      runs and agent sessions; whether a project can switch one off (K6, K7).
- [ ] 6. The Gmail claude.ai connector's full tool list, and whether any tool sends mail (K7). (Amendment 1: `plugin`
      recipes carry no claude.ai prefix, so the connector names of ClickUp, Atlassian, Linear and Slack are not needed.)
- [ ] 7. Where a person adds a claude.ai connector, in words `ade connect` can print (A16).
- [ ] 8. The keys of user- and local-scope MCP servers in `.claude.json`, and where a vendor plugin's `.mcp.json` sits
      once installed (A17).
- [ ] 9. `gh auth status` exit codes; `gh auth login` on a terminal; the names `gh auth token`, `--show-token` and
      `-t`; whether `gh` accepts abbreviated long flags or flags before the subcommand words (if abbreviations work,
      the `deny` runs gain those forms); whether `gh` can keep its token in a plain file, and how `ade` can tell (then
      `connect` warns, `status` says `missing`) (A16, K6). For `git`: that `git credential fill` is the form that
      prints a stored password, and whether another (`credential-<helper> get`) also does, to add to `deny` (K5).
- [ ] 10. `claude -p` options to limit a run to one tool and to read whether the call failed (A17 `test`).
- [ ] 11. The shared `release.yml`: an `assets` entry can publish a file from a sub-folder under the name
      `connector-<service>.json`, with its sha256 in `release.json` (K5).
- [ ] 12. Which `PreToolUse` input field gives a `Bash` command's working directory after a `cd` in an earlier call.
      If none does, the working directory is unknown and every `gh` and `git` command in a folder where GitHub is
      connected asks; K6 reports it to the architect (K6, rule 4e.5).
- [ ] 13. Whether variables exported in one `Bash` call are present in later calls (K6, stated limits).
- [ ] 14. That neither `gh` nor `git` lets an alias or an extension replace a built-in command named in `free` (K5).
- [ ] 15. Each flag in the `github` recipe's `free` lists, against `gh <cmd> --help` and `git <cmd> -h` on the day,
      with the drop rule under the example; that `--` ends options for those commands; which values are required
      (section 4, rules for writing entries); that no listed local command reaches a remote or runs a program from a
      listed flag; that `fetch` and `pull` read a positional that is not a configured remote as a path or URL (K5).
- [ ] 16. What `safe.bareRepository=explicit` stops (a bare repository found by discovery, not one named with
      `--git-dir`) and the command that sets it in the global config (A17).
- [ ] 17. Whether `fetch`, `pull`, `checkout`, `switch` or `worktree add` can reach a URL named in a committed file
      (`.gitmodules`) without an option on the command line; if yes, those entries ask unless `--no-recurse-submodules`
      is given, and the flag is added to them (K5, K6).
