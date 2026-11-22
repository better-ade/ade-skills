# Changelog

## 0.8.0

- The guard (K6), to the contract's amendment 1: `guard` plugin 0.2.0 adds one `PreToolUse` hook (`hooks/guard.sh`
  with its python3 helper `hooks/guard.py`, run through `bash`, `onFailure: "block"`) on `Bash` and on every prefix of
  a `ready` recipe. `hooks/hooks.json` is generated from the recipes by `scripts/make-hooks.sh`; every recipe is
  checked by `check-recipe.sh`'s own rules on every call. In a folder whose `.ade/connectors.json` names a ready
  service, its reads need no question and every other tool asks (or is refused in `bypassPermissions`); where the
  record does not name it, its tools ask, reads included. A `held` recipe (`slack`, `discord`, `outlook`, `teams`, and
  `github` and `gmail` until K7) causes no decision. Where a ready `cli` recipe is named, `gh` and `git` pass only as
  one plain command matching an entry's words, listed flags and arguments (`clickup`, `jira` and `linear` are
  unaffected by that rule); `gh api` asks; the `deny` runs (`gh auth token`, `gh auth status -t`, `--show-token`,
  `git credential fill`) are refused in every mode and folder; a positional that is a path outside the project folder
  (or starts with `~`) makes a free command ask. `check-recipe.sh`'s folder mode now finds the hook files in an
  installed copy's own `hooks/` folder (it refused every ready recipe outside the repository layout). The shipped
  plugins' own hooks are unchanged. Anything the guard cannot read asks. `tests/guard.sh` checks it with a 285-row command table; `docs/connectors.md`, "The
  guard (K6)", says what it does not see.

## 0.7.0

- Connector recipes (K5): `guard` plugin 0.1.0 carries one recipe per service in `plugins/guard/connectors/`, format 1
  of `.ade/context/connectors.md` (amendment 1), for `ade connect` and the guard (its hook is story K6; K5 and K6 are
  released together). Ready with the guard's hook: `clickup`, `jira`, `linear` (tier 0, read lists equal to each
  plugin's `read-tools.txt`). Held: `github` and `gmail` (tier 2, until the guard's hook and their skills ship; `github`
  lists the `gh` and `git` commands that need no question, each with its own flags), `slack` (tier 1), `discord`
  (tier 3), `outlook` and `teams` (tier 4). `plugins/guard/scripts/check-recipe.sh` checks one recipe or the folder;
  `tests/recipes.sh` checks them all. Each release attaches every recipe as `connector-<service>.json`, hashed in
  `release.json`.

## 0.6.0

- Connector plugins (K1), each 0.1.0, one per service, each with the vendor's own hosted MCP server, a skill and a
  `PreToolUse` hook (run through `bash`, `onFailure: "block"`, Claude Code 2.1.295 or later) that asks before any tool
  of that server not on the plugin's read list, and refuses it in `bypassPermissions` mode: `clickup`
  (`https://mcp.clickup.com/mcp`), `jira` (Atlassian's Rovo MCP server, `https://mcp.atlassian.com/v2/mcp`) and
  `linear` (`https://mcp.linear.app/mcp`). The owner signs in through `/mcp`; nothing here holds a credential.
  `docs/connectors.md` records each server, the hook's contract and its limits; `tests/connectors.sh` checks them.
  GitHub moved to story K1b after review.
- `browser` plugin 0.2.0: the `browse` skill defers to an ADE hub folder's own `playwright` MCP server
  (`<hub>/bin/browser run <folder>`) when the folder has one, and describes server profile mode (isolated by default,
  a per-folder profile the owner turns on and signs in to; the owner's word over Telegram on a server).

## 0.5.0

- `fde` plugin 0.2.0, part 2 (F1b): `design-doc` (wraps `bmad-architecture`), `workflow` (current and future Mermaid
  maps with step tables), `status-report` (from the folder's tickets and journal only) and `handover`; design and
  handover templates keep secrets to names and locations.
- The four delivery skills carry F1a's hardened rules: exact export bullet (approved destinations only), provider,
  slug, folder and quoting lines, and the isolation line.

## 0.4.0

- `fde` plugin, part 1 (F1a): `discovery` writes `docs/customer/constraints.md`; `proposal`, `sow` and
  `change-request` draft from it with every price, date and legal term left as a `[[TO FILL: ...]]` blank.
- `tests/fde.sh`: constraints first, no price, date or duration in the commercial templates, blanks in Pricing,
  Timeline and Terms, SOW acceptance criteria, ask-first rules; `tests/meta.sh` tests its leak patterns.
- Review hardening: wider leak patterns (symbols, codes after numbers, word durations, quarters, payment terms,
  slash and month-name dates), legal keywords outside blanks, Pricing, Terms and Change process hold only blanks,
  constraints-first as the first line, exact Ask first bullets, the provider rule, `## Approved tools and
  destinations`, gitleaks on `constraints.md`; a fifth convention line (read only inside the named folder) for every
  document plugin (`notes` 0.1.1 carries it). `tests/meta.sh` has a negative case for each.

## 0.3.0

- `notes` plugin (N1): `meeting-notes`, `summarize`, `action-items`, `digest`, `capture`, writing into the named folder.
- `docs/conventions.md`: the shared rules for document plugins (folder, approved providers, templates, the four lines).
- Checks: `tests/validate.sh` validates every plugin `marketplace.json` lists and fails when `claude` is missing;
  `tests/docs.sh` checks document plugins; `tests/meta.sh` tests both on fixtures.

## 0.2.0

- `ade` plugin (P1): `/ade:status`, `/ade:work`, `/ade:dispatch`, `/ade:notify`, `/ade:agent-add`, `/ade:skills-add`,
  `/ade:doctor`, the `ade` skill, and the permission block for the project's settings; `tests/ade.sh` checks them.

## 0.1.0

- First slice: marketplace, plugin template, git and browser plugins, checks.
