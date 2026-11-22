# Connectors: the contract between ade-skills and ade-cli

Decided in `.ade/context/decisions/0001-connect-and-guard.md` (2026-11-22). ade-skills owns the recipes and the guard;
ade-cli owns `ade connect` and the project record. Facts about Claude Code and vendors come from `docs/connectors.md`;
anything else is under "To confirm before building", and a builder checks it first.

## 1. Recipes

One file per service: `plugins/guard/connectors/<service>.json` in ade-skills. The `guard` plugin carries them, because
its hook reads them at run time (a plugin sees only its own folder); ade-cli reads the same files from its pinned
checkout. A recipe is data: no field is run, and no field holds a secret, a client id or anything that differs per user.

| Field | Format 1 rule |
|---|---|
| `format` | `1` |
| `service` | `^[a-z][a-z0-9-]{0,31}$`, the file name without `.json` |
| `title` | the vendor's product name, printable, at most 40 characters |
| `job` | `tickets`, `code`, `mail` or `chat` |
| `tier` | `0` to `4` (section 2) |
| `state` | `ready` or `held` |
| `held` | when `state` is `held`: one line, why (at most 200 characters); absent otherwise |
| `sign_in.kind` | `plugin` (the server is declared in an ade-skills plugin), `cli` (an existing CLI sign-in) or `claude-ai` (a claude.ai connector). Any other value is refused |
| `sign_in.plugin` | the ade-skills plugin `ade connect` installs (its skill; for `plugin` also its server). Required for `plugin`, optional otherwise |
| `sign_in.cli` | for `cli`: `gh` (the only one in format 1) |
| `sign_in.connector` | for `claude-ai`: the connector name as it appears in tool names, `^[A-Za-z0-9_]{1,40}$` |
| `sign_in.admin` | optional: what an administrator must do, one line; required when `tier` is `4` |
| `questions` | at most 2 objects `{"id", "ask", "to"}`; `id` a name, `ask` one line, `to` is `gate` (a yes/no that must be yes to go on; the answer is stored nowhere) |
| `guard.prefixes` | every tool-name prefix this service's tools can carry: `mcp__plugin_<p>_<s>__` or `mcp__claude_ai_<Name>__`. For `plugin`, `mcp__plugin_<plugin>_<plugin>__` must be one |
| `guard.read` | exact tool names (no patterns) that get no decision; for `plugin`, exactly the names in `plugins/<plugin>/hooks/read-tools.txt` |
| `guard.commands` | for `cli` only: `{"gh": {"free": [...], "deny": [...]}, "git": {...}}`, each entry an argument list (section 4c) |
| `hosts` | the vendor host names its server answers at (the doctor check uses them) |
| `pages` | `{"docs": "https://...", "revoke": "https://..."}`, each a vendor page read on the day; either may be absent |
| `reaches` | one line: what it can read and change, shown before sign-in |

Unknown keys, wrong types, a second copy of a key, or a file over 64 KiB reject the whole recipe. Printed text loses
control characters.

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

### Example: `github` (tier 2, through `gh`)
```json
{
  "format": 1, "service": "github", "title": "GitHub", "job": "code", "tier": 2, "state": "ready",
  "sign_in": { "kind": "cli", "cli": "gh", "plugin": "github" },
  "questions": [],
  "guard": {
    "prefixes": [], "read": [],
    "commands": {
      "gh": {
        "free": [["pr","view"],["pr","list"],["pr","diff"],["pr","checks"],["pr","status"],["issue","view"],
                 ["issue","list"],["issue","status"],["repo","view"],["repo","list"],["run","view"],["run","list"],
                 ["workflow","view"],["workflow","list"],["release","view"],["release","list"],["label","list"],
                 ["search","repos"],["search","issues"],["search","prs"],["search","code"],["search","commits"],
                 ["auth","status"]],
        "deny": [["auth","token"],["--show-token"]]
      },
      "git": {
        "free": [["status"],["log"],["diff"],["show"],["add"],["commit"],["restore"],["switch"],["checkout"],
                 ["branch"],["tag"],["stash"],["fetch"],["pull"],["merge"],["rebase"],["reset"],["rev-parse"],
                 ["ls-files"],["blame"],["grep"],["worktree"],["describe"],["cherry-pick"],["revert"],["mv"],["rm"],
                 ["remote","-v"]],
        "deny": [["credential"]]
      }
    }
  },
  "hosts": ["api.githubcopilot.com"],
  "pages": {},
  "reaches": "Every repository your gh sign-in can reach; pushing, merging, releases, settings and secrets ask each time."
}
```
`sign_in.plugin` `github` (a skill-only plugin, story K7) is absent until K7 ships it; K7 also adds the `gh` and
revoke pages from GitHub's own documentation. `hosts` lets the doctor find GitHub's hosted server added by hand.

### Example: `gmail` (tier 2, a claude.ai connector)
```json
{
  "format": 1, "service": "gmail", "title": "Gmail", "job": "mail", "tier": 2, "state": "ready",
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
connector's own pages (To confirm 6, 7). `hosts` lets the doctor find Google's server added by hand.

## 2. Tiers

The tier is the most the person must do before sign-in works. `ade connect` prints it in plain words.

| Tier | Means | Services today |
|---|---|---|
| 0 | nothing to set up: the vendor registers the client itself | `clickup`, `jira`, `linear` (ready) |
| 1 | the vendor's published app id sits in the plugin | `slack` (held: the owner decides on the client id) |
| 2 | a sign-in the person already has | `github` through `gh`, `gmail` through the claude.ai connector (ready) |
| 3 | the person's own app (client id and secret) | `discord` (held: K3's question; and step 3 is not built) |
| 4 | an administrator must act first | `outlook`, `teams` (held: tenant administrator, legacy servers) |

`ade connect <service>`, step by step:
1. Refuse unless a person is at a terminal: inside a Claude Code session, piped or without a terminal, exit 2, nothing
   changed (ade's `tty_ready`).
2. Fetch ade-skills at the pin; check the recipe (section 1). Unknown service: exit 2 with the closest names.
3. Print the card: title, job, tier in words, `reaches`, "reading needs no question; every change asks", and
   `pages.docs` when present.
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
guard or `gh` sign-in absent), `unknown` (ade cannot read the sign-in: plugin servers and claude.ai connectors) or
`outside` (a server of this vendor sits outside the guard). `missing` and `outside` are gaps; `unknown` is not.

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
  which `ade connect <service>` to run at their terminal and never runs it.

## 4. The guard

One plugin, `guard@ade-skills`: `hooks/hooks.json`, `hooks/guard.sh` (bash and python3, the shipped script's
hardening: exactly one JSON object or nothing, never `allow`, no network), and `connectors/*.json`. Groups on
`PreToolUse`, each `{"type": "command", "command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"],
"onFailure": "block"}`:
- one matcher `<prefix>.*` for every prefix in every recipe (a test checks the set equals the recipes' prefixes);
- one matcher `Bash`.

Decisions, in order. "Ask" means `permissionDecision` `ask`, or `deny` naming the mode when `permission_mode` is
`bypassPermissions`; the reason names the tool or command.
1. Input it cannot read, or a recipe folder it cannot read: ask.
2. (a, b) A tool whose name starts with a recipe prefix (longest wins): if the project folder's `.ade/connectors.json`
   does not name that service, or cannot be read, ask (`<service> is not connected in this folder`); else a name on
   `guard.read` gets no decision, any other asks. This covers plugin-declared servers (ade-skills' and a vendor's own,
   such as `slack@slack`) and claude.ai connectors alike.
3. An MCP tool of a server no recipe names: no decision. The guard cannot tell a vendor's server from any other by
   name, and asking for every tool of every server would be approved by habit; a vendor server added by hand is the
   doctor check's to find (section 5).
4. (c) `Bash`: the command is `tool_input.command` (not a string: ask). To notice `gh` or `git`: remove `'`, `"`,
   `\` and `$`, split on white space and on each of `;` `&` `|` `(` `)` `<` `>` `=` `` ` ``; the command names them when a piece is `gh` or
   `git` or ends in `/gh` or `/git`. Not named: no decision. Named: first, a run of words equal to a `deny` entry,
   anywhere, gets `deny` in every mode (it prints a credential). Otherwise no decision only when all hold, else ask:
   the raw string has none of `; & | < > ( ) $` `` ` `` `\`, a newline or carriage return; `shlex.split` (POSIX)
   succeeds; the first word is exactly `gh` or `git`; for `git`, the global options are only `-C <dir>` and
   `--no-pager` (`-c` and anything else asks); no later word names `gh` or `git` (as above) or is `-x`, `--exec`,
   `--upload-pack`, `--receive-pack` or `--config`; and the words after the program and its global options start
   with an entry of `free` (later flags and arguments are free).

So a pipeline, `&&`, `sh -c`, `xargs`, an environment prefix or a substitution that runs `gh` or `git` always asks;
`gh api` always asks (one command reaches every endpoint); a `gh` extension asks. **Stated limit:** a script or a git
hook that calls `gh` is not seen in the command line. Parsing cannot close that, so the guard is exact about what it
lets through and best-effort about noticing; the fence against a determined agent is the scope of the credential.

The shipped per-plugin hooks (`ask-unless-read.sh` in `clickup`, `jira`, `linear`) stay as they are: a plugin stands
alone. For their prefixes the guard decides from the same list (a test checks `guard.read` equals `read-tools.txt`),
so two hooks give one answer. If To confirm 3 shows two questions for one call, the guard leaves out the prefixes of
ade-skills plugins that carry their own hook, and nothing else changes.

## 5. The doctor check

Reads files only (no network, no model, no command that connects to a server). For a folder, it lists every MCP server
whose `url` host is in some recipe's `hosts`, from: `<folder>/.mcp.json` (project scope), and the user- and local-scope
servers in `${HUB_CLAUDE_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-~}}/.claude.json` (To confirm 8). A server whose tools would
not start with one of that recipe's prefixes is outside the guard:
`connector jira: outside (a server named <name>, user scope, at mcp.atlassian.com; remove it and use the plugin, or add
"mcp__<name>__*" to permissions.ask in .claude/settings.json)`. Server names are printed with control characters
removed. claude.ai connectors are not in local files; the doctor says nothing about them (the guard covers known ones).

## 6. Per folder, per user

| Sign-in | Where it lives | What the folder commits |
|---|---|---|
| `plugin` (tiers 0, 1) | the plugin is installed in project scope; Claude Code keeps the OAuth sign-in (To confirm 1) | `enabledPlugins`, `.ade/connections.json` plugins, `.ade/connectors.json` |
| `cli` (`gh`) | `gh`'s own store, one per machine user | `.ade/connectors.json` |
| `claude-ai` | the Claude account, every folder it is used in | `.ade/connectors.json` |

Nothing per user is committed or written by `ade connect` into a folder. Tier 2 sign-ins are shared by nature; the
guard keeps a connector's MCP tools to folders that name it (section 4, rule 2). If To confirm 1 shows that Claude Code
keeps a plugin server's sign-in per config folder and not per project, `ade connect` keeps
`~/.config/ade/connect` (`service<TAB>config folder<TAB>folder`, 0600, paths only) and refuses a tier 0 or 1 connect
in a second folder under the same config folder, printing that a customer folder needs its own `HUB_CLAUDE_CONFIG_DIR`.

## 7. Step 3 (the local proxy) must stay possible

Format 1 refuses unknown `kind`, `to` and `format` values, so a later `proxy` kind and a `keychain` answer (a hidden
prompt, stored by ade-secrets, never a file or variable) arrive as format 2 without an old `ade` half-running them. The
guard keys on tool-name prefixes, not server type, so a plugin whose server is a local command is covered unchanged.

## To confirm before building

Each in Claude Code's, GitHub's or the vendor's own documentation, before the story that needs it.
- [ ] 1. Where Claude Code keeps a plugin server's OAuth sign-in: per config folder, per project, or both (section 6; A16).
- [ ] 2. Whether any `claude` command reads or starts a server's sign-in without the `/mcp` screen (A16 `status`).
- [ ] 3. Two `PreToolUse` hooks that both answer `ask` for one call: one question or two; `deny` over `ask` (K6).
- [ ] 4. How a hook learns the project folder: the input's `cwd` or `CLAUDE_PROJECT_DIR` (K6).
- [ ] 5. claude.ai connector tool names when the connector's name has spaces or punctuation; whether they load in `-p`
      runs and agent sessions; whether a project can switch one off (K6, K7).
- [ ] 6. The Gmail claude.ai connector's full tool list, and whether any tool sends mail (K7); ClickUp's connector
      tools equal its server's tools (K5); the names of Atlassian's, Linear's and Slack's connectors, to add prefixes.
- [ ] 7. Where a person adds a claude.ai connector, in words `ade connect` can print (A16).
- [ ] 8. The keys of user- and local-scope MCP servers in `.claude.json`, and where a vendor plugin's `.mcp.json` sits
      once installed (A17).
- [ ] 9. `gh auth status` exit codes; `gh auth login` on a terminal; the names `gh auth token` and `--show-token`;
      whether `gh` can keep its token in a plain file, and how `ade` can tell (then `connect` warns, `status` says
      `missing`) (A16, K6).
- [ ] 10. `claude -p` options to limit a run to one tool and to read whether the call failed (A17 `test`).
- [ ] 11. The shared `release.yml`: an `assets` entry can publish a file from a sub-folder under the name
      `connector-<service>.json`, with its sha256 in `release.json` (K5).
