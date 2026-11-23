# Changelog

## 0.7.0

- `orgo` plugin 0.1.0 (K8): Orgo's own hosted MCP server for cloud computers (`https://www.orgo.ai/mcp`, http, signed
  in through `/mcp`; no API key, no local server), built as `clickup`, `jira` and `linear` are: a skill and a
  `PreToolUse` hook that asks before any tool of that server not on the plugin's read list (nine reads: workspaces,
  a computer, its screens, a screenshot, the file list) and refuses it in `bypassPermissions` mode. Orgo's two
  additions: the question says that Orgo bills a computer by the hour while it runs when a tool creates or starts
  one, and for the bash and Python tools it ends with the command's first line, cleaned of control characters and cut
  to 200 characters. A second skill, `install-ade`, installs ADE on an Orgo computer through that server with
  ade-cli's public installer (the tagged release) and leaves `ade setup` and every sign-in to the person.
  `docs/connectors.md` records the server and what is not confirmed; `tests/orgo.sh` checks it.

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
