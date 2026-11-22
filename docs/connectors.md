# Connectors

Recorded by story K1. Each connector plugin adds one vendor's own hosted MCP server, a skill, and a `PreToolUse` hook
that asks the owner before any of that server's tools that is not on the plugin's read list. `tests/connectors.sh`
checks the tested parts. Nothing here holds a credential: the owner signs in themselves, in the browser, through
Claude Code's `/mcp`.

Facts below were read from each vendor's own page on 2026-11-22. "Answers" means a plain unauthenticated request to the
address on that day returned `401` with a `WWW-Authenticate: Bearer ... resource_metadata=...` challenge (an OAuth
protected resource); no sign-in was made and no tool was called.

## How the hook works (the contract K2 and K3 follow)

- A plugin's server key is the plugin's name, so its tools are named `mcp__plugin_<plugin>_<plugin>__<tool>` (Claude
  Code's form for a plugin-bundled server: `mcp__plugin_<plugin-name>_<server-name>__<tool-name>`, from
  [the MCP reference](https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers) and
  [the hooks reference](https://code.claude.com/docs/en/hooks#match-mcp-tools)). A matcher on the bare
  `mcp__<server>__` form never fires for a plugin's server.
- `hooks/hooks.json` runs `"${CLAUDE_PLUGIN_ROOT}"/hooks/ask-unless-read.sh <prefix>` on `PreToolUse`, with the matcher
  `<prefix>.*`, where `<prefix>` is `mcp__plugin_<plugin>_<plugin>__`.
- `hooks/ask-unless-read.sh` is the same file in every connector plugin (a plugin must stand alone). It reads the
  hook's JSON on stdin and strips the prefix from `tool_name`. A name on `hooks/read-tools.txt` gets no output (no
  decision, so the project's own permission rules still apply); any other tool of that server gets
  `permissionDecision: "ask"` with a reason naming the tool; input it cannot read gets `ask`; a tool of another server
  gets no output. It never allows, never denies, makes no network call, and needs only bash and python3.
- `hooks/read-tools.txt`: one exact tool name per line, `#` comments, no patterns. Each name is a read by its vendor's
  own documentation; a tool the vendor adds later is not on it, so it asks.
- The hook adds a question; it takes nothing away. A project's `deny` and `ask` rules still apply to every tool.

## `clickup`

- Server: `https://mcp.clickup.com/mcp`
- Documented at: https://developer.clickup.com/docs/connect-an-ai-assistant-to-clickups-mcp-server (address, OAuth
  only, Claude Code setup on https://developer.clickup.com/docs/connect-an-ai-assistant-to-clickups-mcp-server-1)
- Confirmed on the day: yes. The page names this address; it answers (`401`, OAuth challenge; the authorization server
  offers dynamic client registration). Transport: streamable HTTP.
- Sign in: run `/mcp`, pick `plugin:clickup:clickup`, choose Authenticate, sign in to ClickUp in the browser and choose
  the workspaces to allow. ClickUp accepts OAuth only: no API key or personal token.
- Sign out: in `/mcp`, pick the server and choose Clear authentication, or run `claude mcp logout plugin:clickup:clickup`.
- Revoke at the vendor: ClickUp settings, Apps (https://app.clickup.com/settings/apps). Not confirmed on the day: the
  page documents that settings page for apps and tokens, not the MCP authorization in particular.
- Reaches: the workspaces the owner allows at sign-in, as the owner: tasks, lists, folders, spaces, docs, comments,
  chat, time tracking, reminders, custom fields and views, including bulk changes through `clickup_execute_operator`
  and deleting tasks and comments. MCP calls are rate-limited per workspace per day on some plans.
- Read list: 28 tools, the ones ClickUp's
  [Supported Tools](https://developer.clickup.com/docs/mcp-tools) page marks `Read`. Every tool it marks `Write` asks.

## `jira`

- Server: `https://mcp.atlassian.com/v2/mcp`
- Documented at: https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/
  (tools on https://support.atlassian.com/atlassian-ai-gateway/docs/supported-tools/; the move from v1 on
  https://support.atlassian.com/atlassian-ai-gateway/docs/how-to-upgrade-from-atlassian-mcp-v1-to-atlassian-mcp-v2/)
- Confirmed on the day: yes. Atlassian's page names this address for Claude Code
  (`claude mcp add --transport http atlassian https://mcp.atlassian.com/v2/mcp`); it answers (`401`, OAuth challenge;
  dynamic client registration offered). Transport: streamable HTTP. The old `/v1/sse` and `/v1/mcp` addresses still
  answer `401` but are v1; Atlassian moves v1 users to v2 tools on 2027-03-01.
- Sign in: run `/mcp`, pick `plugin:jira:jira`, choose Authenticate, sign in to Atlassian in the browser and grant
  access on the consent screen (OAuth 2.1). Atlassian also offers API-token sign-in; this plugin does not use it.
- Sign out: in `/mcp`, pick the server and choose Clear authentication, or run `claude mcp logout plugin:jira:jira`.
- Revoke at the vendor: the Atlassian account's connected apps (https://id.atlassian.com/manage-profile/apps). Not
  confirmed on the day: Atlassian's MCP pages do not name it.
- Reaches: every Atlassian app the owner can reach on the sites they allow, with their permissions: Jira, Jira Service
  Management, Confluence, Bitbucket, Loom, Goals, Projects, Assets and the Teamwork Graph. Organisation admins choose
  which permission groups are on (delete and admin groups are off by default). Enriched tools spend Rovo credits.
- Read list: 31 tools: the common read tools (`atlassianUserInfo`, `getAccessibleAtlassianResources`, `discover`) and
  the `read_jira` and `search_jira` groups on the Supported tools page. On purpose not on it, so they ask:
  `executeRead`, `executeWrite`, `executeDestructive` (they run tools found with `discover`; the hook cannot see which),
  other products' tools, and every Enriched tool (they cost credits).
- The default address shows a few tools and finds the rest with `discover`. Atlassian also documents
  `https://mcp.atlassian.com/v2/mcp?tools=all` (every tool, flat); this plugin keeps the default to keep context small.

## `linear`

- Server: `https://mcp.linear.app/mcp`
- Documented at: https://linear.app/docs/mcp
- Confirmed on the day: yes. Linear's page names this address for Claude Code
  (`claude mcp add --transport http linear-server https://mcp.linear.app/mcp`); it answers (`401`, OAuth challenge,
  scopes `read write`; dynamic client registration offered). Transport: streamable HTTP (`/sse` is the older one).
- Sign in: run `/mcp`, pick `plugin:linear:linear`, choose Authenticate, sign in to Linear in the browser (OAuth 2.1).
  Each Linear workspace is its own sign-in.
- Sign out: in `/mcp`, pick the server and choose Clear authentication, or run `claude mcp logout plugin:linear:linear`.
- Revoke at the vendor: Linear settings, Security & access, Authorized applications, Revoke access
  (https://linear.app/docs/security-and-access).
- Reaches: the workspace the owner signs in to, as the owner: issues, projects, cycles, documents, comments, labels,
  teams and users, read and write.
- Read list: 19 tools. Not confirmed on the day: Linear's page does not list tool names, so the list is the server's
  known `get_`, `list_` and `search_` tools; compare it with what `/mcp` shows after signing in. A missing name only
  asks. Linear also offers `https://mcp.linear.app/mcp/readonly` (read tools only) for a project that never changes
  anything.

## `github`

- Server: `https://api.githubcopilot.com/mcp/`
- Documented at: https://github.com/github/github-mcp-server/blob/main/docs/remote-server.md (Claude Code setup in
  `docs/installation-guides/install-claude.md` of the same repository)
- Confirmed on the day: the address, yes: GitHub's page names it and it answers (`401`, OAuth challenge pointing to
  GitHub's sign-in server). Transport: streamable HTTP. Signing in through `/mcp`: **not confirmed, and likely to fail
  as shipped.** GitHub's sign-in server publishes no client registration (no `registration_endpoint`, no client ID
  metadata documents), GitHub's own Claude guides use a personal access token in a header, and Claude Code's MCP page
  says the same. Claude Code then reports "does not support dynamic client registration". This is open for the owner;
  see the owner check.
- Sign in: run `/mcp`, pick `plugin:github:github`, choose Authenticate and sign in to GitHub in the browser. If it
  fails as above, the owner decides between: registering their own GitHub OAuth app and adding the server themselves
  with its client ID (`claude mcp add --transport http --client-id <id> --callback-port <port> ...`, Claude Code's
  "pre-configured OAuth credentials"); or a fine-grained token kept outside this repo (for an ADE hub, in the hub's
  Keychain through `bin/secret`), never in `.mcp.json`.
- Sign out: in `/mcp`, pick the server and choose Clear authentication, or run `claude mcp logout plugin:github:github`.
- Revoke at the vendor: GitHub settings, Applications, Authorized OAuth Apps (or Authorized GitHub Apps), Revoke
  (https://docs.github.com/en/apps/oauth-apps/using-oauth-apps/reviewing-your-authorized-oauth-apps).
- Reaches: everything the granted scopes allow, as the owner: repositories (private ones too), files, branches,
  commits, issues, pull requests and reviews, Actions runs and logs, code scanning, Dependabot and secret scanning
  alerts, discussions, gists, notifications, projects, organisations and teams.
- Read list: 67 tools: those with `readOnlyHint: true` in the server's tool snapshots (`pkg/github/__toolsnaps__`,
  commit `9a72d8d`, 2026-11-20), less `get_secret_scanning_alert` and `list_secret_scanning_alerts`, which ask because
  they can show a leaked secret. Tools only the hosted server has (Copilot ones) are not in the snapshots, so they ask.
