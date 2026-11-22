# Connectors

Recorded by story K1. Each connector plugin adds one vendor's own hosted MCP server, a skill, and a `PreToolUse` hook:
every tool of that server that is not on the plugin's read list asks, or is refused when prompts are switched off.
`tests/connectors.sh` checks the tested parts. Nothing here holds a credential: the owner signs in themselves, in the
browser, through Claude Code's `/mcp`. The plugins need Claude Code 2.1.295 or later (the hook's `onFailure`).

Facts below were read from each vendor's own page on 2026-11-22. "Answers" means a plain unauthenticated request to the
address on that day returned `401` with a `WWW-Authenticate: Bearer ... resource_metadata=...` challenge (an OAuth
protected resource); no sign-in was made and no tool was called.

## How the hook works (the contract K2 and K3 follow)

- A plugin's server key is the plugin's name, so its tools are named `mcp__plugin_<plugin>_<plugin>__<tool>` (Claude
  Code's form for a plugin-bundled server: `mcp__plugin_<plugin-name>_<server-name>__<tool-name>`, from
  [the MCP reference](https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers) and
  [the hooks reference](https://code.claude.com/docs/en/hooks#match-mcp-tools)). A matcher on the bare
  `mcp__<server>__` form never fires for a plugin's server, and this plugin's matcher never fires for a server named
  anything else.
- `hooks/hooks.json` runs the script in exec form, `"command": "bash"` with
  `"args": ["${CLAUDE_PLUGIN_ROOT}/hooks/ask-unless-read.sh", "<prefix>"]`, so a lost exec bit does not matter, on
  `PreToolUse` with the matcher `<prefix>.*`, where `<prefix>` is `mcp__plugin_<plugin>_<plugin>__`. It sets
  `"onFailure": "block"`: if the hook cannot start, fails or times out, Claude Code blocks the call instead of letting
  it go ahead. That field needs Claude Code 2.1.295 or later; an older Claude Code lets the call go ahead.
- `hooks/ask-unless-read.sh` is the same file in every connector plugin (a plugin must stand alone). It reads the
  hook's JSON on stdin and strips the prefix from `tool_name`. A name on `hooks/read-tools.txt` gets no output (no
  decision, so the project's own permission rules still apply). Any other tool of that server gets
  `permissionDecision: "ask"` with a reason naming the tool, or `"deny"` naming the mode when `permission_mode` is
  `bypassPermissions`. Input it cannot read gets `ask`; a tool of another server gets no output. It prints exactly one
  JSON object or nothing, whatever its python3 helper prints. It never allows, makes no network call, and needs only
  bash and python3.
- `hooks/read-tools.txt`: one exact tool name per line, `#` comments, no patterns. Each name is a read by its vendor's
  own documentation; a tool the vendor adds later is not on it, so it asks.
- The hook adds a question for this server's tools. A project's `deny` and `ask` rules still apply to every tool; the
  hook cannot make a call safer than the answerer (next sections).
- MCP resources the server offers (read through `ReadMcpResourceTool`) are not tools of this server, so the hook does
  not match them; they only read.
- Each skill carries the rule, as one line:

- If this service's tools are not named `mcp__plugin_<plugin>_<plugin>__…`, this plugin's hook is not guarding them: say so and change nothing.

## If you already added this server yourself

Claude Code connects a server once. A server you added yourself (local, project or user scope) at the same address
outranks the plugin's, so its tools are named `mcp__<your-server-name>__…` and this plugin's hook never sees them.
A claude.ai connector to the same vendor at the same address ranks below the plugin and is hidden; at another address
it loads as a separate server, also unguarded. Either remove your own entry (or that connector) and use the plugin,
or add an `ask` rule for it to the project's `.claude/settings.json`, with the name `/mcp` shows for it:

```json
{
  "permissions": {
    "ask": ["mcp__<your-server-name>__*"]
  }
}
```

## When the owner is not the one answering

The hook's `ask` becomes a question in Claude Code's permission prompt. It reaches the owner only when the owner is
the one answering prompts. It does not when:
- the session runs with a `--permission-prompt-tool` or an Agent SDK `canUseTool` callback, or on a host that answers
  prompts for the session (an orchestrator on a server, for example): that tool or host answers;
- a `PermissionRequest` hook is installed: it can answer the prompt;
- a mod that handles `tool.check` is installed: without managed settings it can approve a call a hook asked about or
  blocked;
- the session is in `bypassPermissions` mode: no prompt is shown, so the hook returns `deny` for every tool not on the
  read list;
- the session is in `dontAsk` mode, or is a `-p` run with no one to answer: Claude Code refuses what would prompt.

In those setups, a change goes ahead only on the owner's word in the conversation, never on an automatic answer.

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
- Confirmed on the day: yes. Atlassian's page gives this address for Claude Code; it answers (`401`, OAuth challenge;
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
- The default address shows a few tools and finds the rest with `discover`, so in this mode most reads go through
  `executeRead` and therefore ask. Never choose "always allow" for `executeRead`, `executeWrite` or
  `executeDestructive`: an allow rule would let every tool they can run through. Atlassian also documents
  `https://mcp.atlassian.com/v2/mcp?tools=all` (every tool, flat); this plugin keeps the default to keep context small.

## `linear`

- Server: `https://mcp.linear.app/mcp`
- Documented at: https://linear.app/docs/mcp
- Confirmed on the day: yes. Linear's page gives this address for Claude Code; it answers (`401`, OAuth challenge,
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
  asks; the owner check compares them.

## GitHub

GitHub is not shipped yet: its hosted server's sign-in does not work through `/mcp` without a credential set up
outside this plugin, which would leave the server unguarded (story K1b). Work with GitHub through `gh` and git, under
the `git` plugin's rules.

## Owner check

Needs the owner's accounts, so it cannot be automated. For each of `clickup`, `jira` and `linear`, on Claude Code
2.1.295 or later:
1. Enable the plugin in a test project; run `/mcp`, pick `plugin:<plugin>:<plugin>`, Authenticate, sign in.
2. Check that the server's tools are named `mcp__plugin_<plugin>_<plugin>__…` and that no server you added yourself
   points at the same address.
3. Ask for one item to be read and see its link quoted.
4. Ask for one change and see the hook's question, labelled `[plugin:<plugin>]` and naming the tool; decline it.
5. For `linear`: compare the tool list `/mcp` shows with `plugins/linear/hooks/read-tools.txt`, and report any read
   tool missing from it and any name on it that is not a read (its 19 names are not confirmed on the day).
6. Sign out with Clear authentication, and revoke at the vendor as above.
