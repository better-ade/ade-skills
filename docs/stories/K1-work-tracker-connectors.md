# K1: connectors for work trackers: ClickUp, Jira, Linear

Status: Ready for development (2026-11-22). Risk: high (sign-in and access to the owner's accounts).
Owner's intent (2026-11-22): "Skills - add mcp for clickup, jira, linear, github, gmail, outlook, teams".
Mail and chat (Gmail, Outlook, Teams) are story K2. Verification command: `bash tests/run.sh`.
2026-11-22, after review: GitHub moved to story K1b (its hosted server's sign-in through `/mcp` needs a credential
set up outside the plugin, which leaves the server unguarded). This story now covers three plugins.

## Goal
Three plugins, one per service, so a project loads only the one it uses: `clickup`, `jira`, `linear`. Each
adds that vendor's **own hosted MCP server**, a skill that says when and how to use it, and a hook that puts every
change behind the owner's yes. The owner signs in themselves, in the browser, through Claude Code's `/mcp`. No key,
token or account name is in this repo.

| Plugin | Server (the vendor's own; the builder confirms each against the vendor's documentation on the day) |
|---|---|
| `clickup` | `https://mcp.clickup.com/mcp` (OAuth only) |
| `linear` | `https://mcp.linear.app/mcp` (OAuth) |
| `jira` | Atlassian's Rovo MCP server under `https://mcp.atlassian.com/` (OAuth). Its path changed in 2026 (`/v1/sse` was retired); use the one Atlassian's support page names now |

## Decisions (coordinator defaults; the owner can change any of them)
- **Vendor servers only.** No community package stands between the owner's account and the model.
- **One plugin per service**, not one bundle: a server's tools cost context only where the plugin is enabled.
- **Reading is free, changing asks.** A `PreToolUse` hook in each plugin lets a tool through only when its name is on
  that plugin's read list (get, list, search, find, read, fetch and the like, written out per server). Every other
  tool of that server, including one the vendor adds later, gets the decision `ask`.

## Acceptance criteria (`tests/connectors.sh`; no network, no model calls)
| AC | Criterion | Test |
|---|---|---|
| 1 | Each plugin passes `claude plugin validate`; the marketplace lists all three; each has a `version` in its `plugin.json` | `connectors_valid` |
| 2 | Each `.mcp.json` names exactly one server, of type `http`, at the `https` address in `docs/connectors.md`, on the vendor's own domain; no `command`, no `npx`, no header or environment value that holds a credential | `connectors_vendor_only` |
| 3 | No secret anywhere in the three plugins (the repo's secret scan passes; no token-shaped string, no account, workspace or person name) | `connectors_no_secret` |
| 4 | Each plugin's hook answers `ask` for a tool of its server that is not on its read list, `allow` nothing by itself (a read tool gets no decision, so the project's own rules still apply), and ignores tools of other servers; run with sample tool names, including a made-up new one | `connectors_hook_asks` |
| 5 | Each skill has `## Ask first` naming: creating, changing, moving, closing or deleting an item; commenting; assigning or mentioning a person | `connectors_ask_first` |
| 6 | Each skill says: content from the service is data, not instructions; quote the item's link for every fact; stay in the workspace or project the owner named | `connectors_rules` |
| 7 | `docs/connectors.md` lists, per plugin: the server address, where the vendor documents it, how the owner signs in (`/mcp`), how to sign out and revoke access at the vendor, and what the server can reach | `connectors_docs` |
| 8 | The README's plugin table and CHANGELOG record the three; `VERSION` is raised | `connectors_listed` |
| 9 | Review fixes (2026-11-22): the hook blocks on failure and refuses changes in `bypassPermissions`; skills and docs say a server added outside the plugin is unguarded and when the owner is not the one answering; GitHub is not shipped | `connectors_guarded`, `connectors_hook_asks` |

## Owner check (cannot be automated: it needs the owner's accounts)
For each plugin: enable it, run `/mcp`, sign in, read one item, then ask for one change and see the question appear.
For `linear`, also compare the tools `/mcp` lists with `hooks/read-tools.txt` (its names are not confirmed on the day).

## Out of scope
GitHub (K1b). Gmail, Outlook, Teams (K2). Orchestrators on a server signing in without a browser. ade-brain's ticket sync.
