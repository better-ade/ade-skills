# 0001: Connectors: predefined recipes, `ade connect` per user, one guard

Status: accepted, 2026-11-22 (owner approved the direction); amended 2026-11-22 (amendment 1, at the end: decisions 5,
7 and 9 and the services line changed). Contract: `.ade/context/connectors.md`.

## Context

K1 shipped `clickup`, `jira` and `linear` as plugins: the vendor's own server in the plugin's `.mcp.json`, a skill,
and a per-plugin `PreToolUse` hook that asks for every tool not on its read list, fails closed (`onFailure: block`),
and refuses in `bypassPermissions`. Six services are held (`docs/connectors.md`, "Held"): GitHub's server cannot sign
in through `/mcp` without a credential outside the plugin; Gmail needs the owner's client secret; Outlook and Teams
need a tenant's client id and an administrator, and Microsoft marks those servers legacy; Slack works only with Slack's
published client id written into the plugin; Discord waits for K3's question. The review also found that a server
added by hand, or a claude.ai connector at another address, loads unguarded.

The owner's words: "we'll need to pull these and ask the users via ade cli too that uses claude code"; "so the skills
are predefined but authentication is per user"; and "yes that works" to: (1) `ade connect` driven by a recipe in
ade-skills; (2) one guard covering plugin servers, claude.ai connectors and `gh`, plus a doctor check; (3) later, only
if needed, a local proxy for vendors that need the user's own app. This record designs steps 1 and 2.

## Decision

1. **A recipe per service, as data, in ade-skills**: `plugins/guard/connectors/<service>.json`, format 1. It names the
   job, the tier, how sign-in happens, at most two yes/no questions, the plugin to install, the guard's prefixes and
   read list, the vendor hosts and pages, and what it reaches. No field is run and none holds a secret or a client id.
   *Reason:* ade-cli needs no per-vendor code, and the guard reads the same file, so a read list exists once.
2. **Tiers 0 to 4** say how much the person must do: 0 nothing, 1 a published app id, 2 a sign-in they already have,
   3 their own app, 4 an administrator. *Reason:* the same verbs for every vendor, with an honest "not yet" or "your
   administrator must first" instead of a half-working connect.
3. **`ade connect` in ade-cli** (list, `<service>`, `status`, `test`, `disconnect`, `--check`). Anything that signs in
   or out runs only for a person at a terminal and refuses in an agent session. *Reason:* a person answers; ade's
   existing `tty_ready` already enforces it.
4. **Names only, in a new `.ade/connectors.json`**, not a new key in `.ade/connections.json`. *Reason:* an older `ade`
   rejects a connections record with an unknown key whole, which would block every teammate who has not updated.
5. **One guard plugin, `guard@ade-skills`**, matching every recipe prefix (plugin servers, a vendor's own plugin,
   claude.ai connectors) and `Bash` for `gh` and `git`. It never allows, fails closed, and asks for a connector's tools
   in a folder whose record does not name it. *Reason:* it closes the review finding for every vendor at once and keeps
   tier 2 sign-ins, which are shared by nature, to the folders that chose them. *(Amendment 1: only for `ready`
   recipes; a `held` recipe never causes a decision.)*
6. **The shipped per-plugin hooks stay**, unchanged; a test holds each plugin's `read-tools.txt` equal to its
   recipe's read list. *Reason:* a plugin must stand alone; the same list gives the same answer.
7. **`gh` and `git` are guarded by an exact list, not by parsing a shell.** Only one simple command on the `free` list
   passes; any pipeline, compound, substitution or `sh -c` that names them asks; credential-printing commands are
   denied. *Reason:* a shell line cannot be parsed safely enough to let a hidden `gh pr merge` through, so the
   fallback the review asked for is the rule. *(Amendment 1: the `free` list is an allow-list of words, flags and
   positionals, and it applies only in folders that connected GitHub.)*
8. **Recipes are pinned and verified**: read only at the `vX.Y.Z` tag ade already pins, and checked against the
   sha256 in that ade-skills release's `release.json`. *Reason:* the same trust ade-cli uses for itself (A12).
9. **The doctor check reads files only**: a server at a recipe's host whose tools carry none of its prefixes is
   reported with the exact fix. *Reason:* it finds what the guard cannot see, without a network call or a model.
   *(Amendment 1: only for services the folder's record names.)*

Services today: `clickup`, `jira`, `linear` (tier 0) and `github` through `gh`, `gmail` through the claude.ai
connector (tier 2) are ready; `slack` (1), `discord` (3), `outlook` and `teams` (4) are held. *(Amendment 1: `github`
and `gmail` are held until K6 and K7 ship; `clickup`, `jira`, `linear` are ready only in a release with the guard's
hook.)*

## Alternatives considered

| Option | Why not |
|---|---|
| Per-vendor code in `ade` | Grows the one bash file for each vendor; the recipe makes a vendor a data change |
| The record as a key in `.ade/connections.json` | Older `ade` rejects the whole record (decision 4) |
| Replace the per-plugin hooks by the guard | A connector plugin installed alone would be unguarded |
| The guard asks for every MCP tool of an unknown server | Prompts on every server get approved by habit; precise questions keep meaning. Left to the owner |
| Parse shell lines to let compound `gh` reads through | Cannot be made safe (quoting, substitution, `sh -c`); a hidden change would pass |
| `ade connect` writes `ask` rules into settings | Writes a per-user server name into a committed file; the doctor prints the rule instead |
| Settings rules instead of a hook | Reads would need `allow` rules written into each project, and a missing or mistyped rule fails open; the hook fails closed and never allows |
| The local proxy now | The biggest build and the highest risk; step 3, only if still needed |
| Community packages (Discord, Microsoft Graph) | Vendor servers and tools the user already trusts come first |

## Consequences

- A new vendor is a recipe plus, for tier 0 or 1, a plugin; ade-cli changes only for a new `kind`.
- GitHub ships without an MCP server and Gmail without registering an app; GitHub's hosted server stays held (K1b).
- In a folder with the guard, `cd x && git status` asks; agents use `git -C x status`. A script or git hook that calls
  `gh` is not seen: the guard is a check on ordinary use, the credential's scope is the fence. *(Amendment 1: this
  holds where GitHub is connected, and `-C x` passes only when `x` is inside the project folder.)*
- claude.ai connectors are visible to every folder of the account; the guard limits them only where it is installed.
- Sign-in state of plugin servers and claude.ai connectors is `unknown` to ade until To confirm 2 says otherwise.
- **Step 3 boundary:** format 1 refuses unknown `kind`, `to` and `format` values; the guard keys on tool-name prefixes,
  not server type. A `proxy` kind and a `keychain` answer can arrive as format 2. Nothing in steps 1 and 2 may put a
  secret in a file, a variable or a command line, or add a server outside a plugin.

## Left open for the owner

1. May Slack's published client id be written into `plugins/slack/.mcp.json` (tier 1)? Until then `slack` is held.
2. Discord: K3's question (wait, or a pinned community package with the bot token from ade-secrets).
3. Outlook and Teams: wait, or a new story for Work IQ MCP with a guard that reads the path as well as the tool.
4. Whether a server-side orchestrator may ever answer through an approval channel instead of a terminal. Not designed
   here; today a person answers at a terminal or the change does not happen.
5. Unknown claude.ai connectors: no decision (chosen) or ask for every tool.
6. Where the guard is installed: in each folder `ade connect` touches (chosen), or in every hub folder by default.
7. Tier 2 sharing: `gh` is one sign-in per machine user across customer folders. Accept it, or require a separate
   machine user or GitHub identity per customer.
8. The `gh` limit above: accept the guard as a check on ordinary use, or also require a read-only GitHub credential
   for agents.
9. "One guard": this record keeps the shipped per-plugin hooks beside the guard (decision 6). Confirm that reading.

## Proposed stories

| Id | Repo | One line | Risk | Order, depends on |
|---|---|---|---|---|
| K5 | ade-skills | Recipe format 1, the nine recipes in `plugins/guard/connectors/`, tests tying each to its plugin and read list, release assets | high | 1 |
| K6 | ade-skills | The `guard` plugin hook: prefixes, the folder rule, the `gh` and `git` rule, fail closed; tests | high | 2, K5 |
| A16 | ade-cli | `ade connect` list, `<service>`, `status`, `disconnect`; `.ade/connectors.json`; pin and sha256 check | high | 2, K5 (builds to this contract with fixtures) |
| A17 | ade-cli | `ade connect test`, `--check`, the doctor check, `ade restore` and `ade setup` wiring | high | 3, A16, K6 |
| K7 | ade-skills | Skill-only `github` and `gmail` plugins under the guard; docs and the held test updated | high | 3, K6 |

Ids are the next free ones seen today; the coordinator confirms them when writing the stories.

## Amendment 1 (2026-11-22)

An adversarial review of the contract reproduced seven findings (A to G below). Nothing built on the contract is
released, so format 1 itself changes; there is no format 2. The contract's "What changed in amendment 1" list is the
line-by-line version for builders.

| Finding | What changed | Why |
|---|---|---|
| A. `free` let later flags and arguments through: `git remote -v add`, `git grep -O<program>`, `git log --output=`, `git fetch --upload-pa=`, `git rebase -x<program>`, `gh auth status -t`, `--jq env`, `--web`, and work-discarding commands under a free word | `free` entries are objects `{words, flags, args}`: exact leading words, the only flags allowed (matched as whole words, no abbreviation, no cluster; `F=` for a flag with a required value), and whether positionals are allowed. Any other `-` word asks. `--` only where positionals are allowed. The `github` lists free reading commands, ordinary local git work, and `fetch`/`pull` with plain remote names only (`"args": "names"`); `push`, `clone`, `config`, `submodule`, remote changes and the rest ask | A deny list of flags cannot be complete: git takes abbreviated long options, `=` forms, attached short values and clusters, and one letter means different things in `gh` and `git`. An allow-list is exact by construction. The principle (coordinator, for a usable guard): no decision for a listed shape that cannot reach the service with a change, cannot print a credential and carries only listed flags. Local work never reaches the service, the guard is not a sandbox (the shell tool can already run any program), and a hook's `ask` overrides the project's allow rules, so asking for every commit would get the guard switched off |
| A (found while widening the list). The shell-character check ignored quoting, and unquoted globs, braces and `~` expand into words the guard never sees (a file named `-Ofoo` matched by `*`) | The check is quote-aware: `( ) ; & \| < >` may sit inside quotes; outside quotes globs, braces, `~`, `!`, `$`, `` ` `` and `\` ask; inside double quotes `$`, `` ` ``, `\`, `!` ask; newlines ask anywhere | Commit messages such as `feat(x): y` must pass, and what the program receives must be what the guard read |
| A. Token printing slipped past the exact word `--show-token` | `deny` runs match element by element in any order; a long flag matches its `=` form, a one-letter flag any cluster or attached form containing it; `gh` deny gains `auth status --show-token` and `auth status -t`; `git` deny is `credential fill` (two words, so a commit message that mentions credentials is not refused) | The forms the review used must be refused; a rare over-match costs a rephrase, an under-match prints a token |
| A. `--jq` reads the environment | Left off every `free` list (asks); not added to `deny` | A shell `printenv` prints the same variables with no guard at all, so denying it closes nothing; `gh auth token` reads the keyring, which the shell cannot, so it stays denied |
| B. `git -C <dir>` or an earlier `cd` runs a free command in a repository whose config came with a clone | `git` global options are only `--no-pager` and `-C <dir>`, `<dir>` inside the project folder; `-c` asks; the working directory must be the project folder or inside it, for `gh` too. Noticing also catches `GIT_`, `GH_`, `GITHUB_` variable names. `ade setup` offers `safe.bareRepository=explicit` (A17) | Outside the project folder the guard cannot know whose config runs. The reproduced case inside it, a committed bare repository, is a stated limit, narrowed by the setting (To confirm 16), not closed |
| C. Rule 4 ignored the recipe's `state` and the record | The allow-list applies only where the record names a `ready` `cli` service; elsewhere `gh` and `git` get no decision; `deny` applies wherever the guard is installed | The guard's job is the remote and tokens in folders that chose GitHub; token printing is refused everywhere because a token is never a folder's business |
| D. A held recipe's prefix made the guard ask (or deny) in every folder, blocking a person's own vendor plugin | A `held` recipe never causes a decision and has no matcher (a failing guard cannot block it); a `ready` recipe not named in the record still asks; the doctor reports only for named services | Customer separation is kept for services ade can connect; a service it cannot connect is not the guard's to claim |
| E. `github` and `gmail` were marked ready before their hook and skills exist | Both ship `held`; K7 flips them and adds `sign_in.plugin`. K5 and K6 are released together, so `clickup`, `jira`, `linear` are `ready` in the first release that ships recipes. A checker rule stays as the safety net: no recipe is `ready` in a checkout without `plugins/guard/hooks/hooks.json` and `guard.sh` | The coordinator's decision: a recipe is never `ready` in a release where the guard's hook does not exist |
| F. A claude.ai connector for a `plugin`-kind service carries a prefix no recipe lists | Fixed card sentences per kind; the `plugin` card says the guard does not cover that connector and Claude Code's own permission settings decide, in every folder. `plugin` recipes carry `mcp__plugin_` prefixes only | Honest wording over a half-guard: the connector's tool names and read list are not known for those vendors |
| G. The checker missed cross-file rules, `claude-ai` recipes claiming other prefixes or plugins, and invisible characters | Per-kind rules (`claude-ai`: one prefix `mcp__claude_ai_<connector>__`, `sign_in.plugin` equal to `service`; `cli`: no prefixes, no read list); cross-file rules (no overlapping prefixes, unique connector and plugin, one recipe per program); every string refuses Unicode Cc, Cf, Cs, Co, Cn, Zl, Zp; a recipe is a regular file | A recipe must not be able to speak for another service, and printed text must show what it says. Overlap is refused, so "longest prefix wins" is gone |

Stories affected: K5 (recipe checks, the new `free` lists, `github` and `gmail` held), K6 (rules 2 to 4, matchers
for `ready` recipes only; released together with K5), A16 (the checks mirrored, card sentences, `missing (held:
...)`), A17 (doctor scope, `safe.bareRepository`), K7 (flips `github` and `gmail`). To confirm 4, 6 and 9 changed; 12
to 17 are new.

Left open for the owner, added by amendment 1:
10. In a folder where GitHub is connected, reading, ordinary local git work (`add`, `commit`, `switch`, `stash`,
    `merge`, `rebase`, `reset`, ...) and `fetch`/`pull` with plain remote names get no question; `push` and every
    change on GitHub ask. The owner can tighten this: drop any entry (for example `reset --hard`, `clean -f`,
    `branch -D`) from the `github` recipe's `free` list, and that command asks.
11. Decided by the coordinator: K5 and K6 are released together, so `clickup`, `jira` and `linear` are `ready` in the
    first release that ships recipes; "never `ready` without the guard's hook" stays as the safety net.
12. Accepted as written: `deny` is refused in every mode and matches in any order, so a rare harmless command can be
    refused; the person can run it themselves.
