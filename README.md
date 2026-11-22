# ade-skills

Predefined skills and MCP servers for ADE developers, as a Claude Code plugin marketplace. Developers add more by pull
request. Roles live in [ade-method](https://github.com/better-ade/ade-method) and
[ade-agent-registry](https://github.com/better-ade/ade-agent-registry); this repo is what those roles can *do*.

| Plugin | What it gives an agent |
|---|---|
| `git` | Branch, commit and PR conventions: commit as the user, no AI attribution, verify before pushing, ask before push or merge |
| `browser` | Claude in Chrome for signed-in tools, Playwright MCP (headless, isolated) for public pages and tests; read-only by default |
| `ade` | Slash commands for the `ade` CLI (status, work, dispatch, notify, specialists, plugins); risky ones ask the owner |
| `notes` | Meeting notes, summaries, action items, digests and captures in the named hub folder, each point with its source |
| `fde` | Forward deployed engineering documents (discovery, proposal, SOW, change request, design doc, workflow, status report, handover) from the customer's constraints; prices, dates and terms left blank |
| `clickup` | ClickUp's own hosted MCP server; the owner signs in through `/mcp`; a hook asks before any tool not on its read list |
| `jira` | Atlassian's own hosted MCP server (Rovo MCP, v2) for Jira; the owner signs in through `/mcp`; a hook asks before any tool not on its read list |
| `linear` | Linear's own hosted MCP server; the owner signs in through `/mcp`; a hook asks before any tool not on its read list |
| `github` | GitHub's own hosted MCP server (story K1b, sign-in not working yet); a hook asks before any tool not on its read list |

## Install

```
/plugin marketplace add better-ade/ade-skills
/plugin install git@ade-skills
/plugin install browser@ade-skills
/plugin install ade@ade-skills
/plugin install notes@ade-skills
/plugin install fde@ade-skills
/plugin install clickup@ade-skills
/plugin install jira@ade-skills
/plugin install linear@ade-skills
/plugin install github@ade-skills
```

The connector plugins (`clickup`, `jira`, `linear`, `github`) hold no credential: each owner signs in themselves through
`/mcp`. [docs/connectors.md](docs/connectors.md) gives each server's address, sign-in, sign-out, revocation and reach.

A project can offer them to teammates in its committed `.claude/settings.json` (`extraKnownMarketplaces`,
`enabledPlugins`); each teammate still installs them on their own machine.

## Add a plugin

1. Copy `plugins/_template/` to `plugins/<name>/`, fill in `plugin.json` (name, description, version) and the skill.
2. Every skill has a `## Ask first` section: each action that sends, publishes, buys, deletes or changes something
   outside the repo, and that the agent asks before it.
3. A plugin that writes documents follows [docs/conventions.md](docs/conventions.md) and has the `document` keyword.
4. MCP servers: pin the package version. No secrets in this repo: remote servers sign in with OAuth; a server that
   needs a key gets it from the hub's Keychain (`bin/secret`), never from a value written here.
5. Add the plugin to `.claude-plugin/marketplace.json` (no version there), bump `version` in `plugin.json` on every
   change, run `bash tests/run.sh`, open a pull request.

## Verification

`bash tests/run.sh`: manifests and names, a version in one place, `## Ask first` in every skill, pinned MCP packages,
`claude plugin validate` on every plugin the marketplace lists (fails if `claude` is missing), the document-plugin
conventions in [docs/conventions.md](docs/conventions.md), the connector checks (`tests/connectors.sh`: vendor servers
only, no secret, the ask-first hook run on sample tool names), and a gitleaks scan.
