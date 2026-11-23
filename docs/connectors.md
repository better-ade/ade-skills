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

## `orgo`

Recorded by story K8; facts read from Orgo's own pages on 2026-11-23. Orgo gives cloud computers (Linux desktops, and
others) that agents can drive. Orgo: sign in through `/mcp`, choose the workspace; agents can read freely, and ask
before creating computers, running commands or controlling a desktop.

- Server: `https://www.orgo.ai/mcp`
- Documented at: https://docs.orgo.ai/guides/mcp (the address, sign-in, the tool table, revoking); the tool names and
  their HTTP methods in Orgo's published API specification, https://docs.orgo.ai/api-reference/openapi.json (version
  2.0.0 on the day); the bash tool's limits on https://docs.orgo.ai/api-reference/computers/bash.
- Confirmed on the day: from the page only. The guide names this address for remote HTTP MCP clients and says "No API
  key is needed for this connection" (OAuth authorization-code flow with PKCE, one-hour access tokens, rotating
  refresh tokens). No request was made to the address itself, no sign-in was made and no tool was called.
- Sign in: run `/mcp`, pick `plugin:orgo:orgo`, choose Authenticate; Orgo's sign-in and consent page opens in the
  browser; choose the workspace to authorize and approve. Orgo also offers an API key (in a header, or with a local
  server); this plugin uses neither.
- Sign out: in `/mcp`, pick the server and choose Clear authentication, or run `claude mcp logout plugin:orgo:orgo`.
- Revoke at the vendor: Orgo's Settings, Security, Connected AI apps (https://www.orgo.ai/settings/security#connected-apps):
  click Disconnect next to the app; its next tool call fails with `401`.
- Reaches: the one workspace the owner chooses at sign-in: reading the workspace, creating and managing its
  computers, the screenshot, mouse, keyboard, bash and Python tools on them (commands run as root), screens, and
  listing, exporting, downloading, deleting and uploading files. Orgo's guide says a sign-in is not offered templates,
  clients, account, chat or support tools, creating or deleting workspaces, suspending or resuming, a computer's
  password, or putting vault secrets on a computer.
- Costs: Orgo bills a computer by the hour while it runs (from the account's credit, or against the plan's room), so
  the hook's question says so for `orgo_create_computer`, `orgo_clone_computer`, `orgo_fork_computer`,
  `orgo_start_computer`, `orgo_restart_computer` and `orgo_resume_computer`. Nothing here stops a computer by itself.
- Read list: 9 tools, each in the guide's tool table and a `GET` in the specification: `orgo_list_workspaces`,
  `orgo_get_workspace`, `orgo_get_computer`, `orgo_get_computer_operation`, `orgo_get_resize_limits`,
  `orgo_list_screens`, `orgo_get_screen`, `orgo_get_screenshot`, `orgo_list_files`. On purpose not on it, though each
  is a `GET`: `orgo_download_file` (a signed link to a file), `orgo_get_vnc_password` and `orgo_get_computer_ssh` (a
  way in), `orgo_get_residential_proxy` and `orgo_get_computer_suspension` (each can do more than read). Every other
  tool asks, including `orgo_wait`, the workflow tools and any name Orgo adds later.
- The question for `orgo_execute_bash` and `orgo_execute_python` ends with the command (`command` or `code`): its
  first line that is not blank, without control or invisible characters, cut to 200 characters, with the number of
  lines when there are more. It shows the start of a command, not all of it; the skill has the agent show the whole
  command in the conversation first.
- Not confirmed: which tools a sign-in is offered, by name. The guide describes the sign-in's reviewed list in words
  ("a sign-in can see fewer tools than the spec defines") and its table "shows the spec when this page was written";
  the names here come from that table and the specification, not from a signed-in server. Also not confirmed: that the
  tools arrive named `mcp__plugin_orgo_orgo__orgo_…` (the guide gives the `orgo_` names), and the argument names
  `command` and `code` over MCP (they are the specification's body fields; the guide says arguments are flattened).
  A name that differs only asks; a command the hook cannot read is said to be unreadable. The owner check compares.
- A screenshot is on the read list, so it needs no extra question: it shows whatever is on that desktop.
- The `install-ade` skill installs ADE on an Orgo computer through these tools: it reads the workspace, checks the
  system and runs ade-cli's public installer (the tagged release) with `orgo_execute_bash`, each call asked by the
  hook, then leaves `ade setup` and every sign-in to the person at the desktop.

## GitHub

GitHub is not shipped yet: its hosted server's sign-in does not work through `/mcp` without a credential set up
outside this plugin, which would leave the server unguarded (story K1b). Work with GitHub through `gh` and git, under
the `git` plugin's rules.

## Held: mail and chat (K2, K3)

Stories K2 (Gmail, Outlook, Teams) and K3 (Slack, Discord) were checked on 2026-11-22 against each vendor's own page,
Claude Code's [MCP reference](https://code.claude.com/docs/en/mcp) and
[plugins reference](https://code.claude.com/docs/en/plugins-reference), and a plain request with no credentials to
each address. None of them is shipped: no plugin folder, no marketplace entry. The rule they were held against is
K1's: a plugin ships only if sign-in works with the server declared in the plugin's own `.mcp.json`, with no token or
client secret in the repo, a project file, a command line or an environment variable agents' shell commands can read,
and with nothing that differs per owner written into the repo.

What Claude Code documents on the day:
- A plugin's `.mcp.json` can carry an `oauth` object (`clientId`, `callbackPort`, `authServerMetadataUrl`, `scopes`).
- `${VAR}` expansion is documented for `command`, `args`, `env`, `url` and `headers`, not for `oauth`. A
  `${user_config.KEY}` value is documented as "substituted in MCP server config", but `claude plugin validate` (2.1.330)
  checks such a reference in `url` and not in `oauth.clientId`, so a client id from a variable is not shown to work.
- A client secret is set only when the server is added by hand ("You can set the client secret only when you add the
  server"); that puts the server outside the plugin, where its hook never fires (see "If you already added this server
  yourself"). There is no documented `oauth` field for a secret in a plugin.

### `gmail`

- Server: `https://gmailmcp.googleapis.com/mcp/v1`, documented at
  https://developers.google.com/workspace/gmail/api/reference/mcp (set-up:
  https://developers.google.com/workspace/gmail/api/guides/configure-mcp-server). Developer Preview: the owner's Google
  account must be in the Google Workspace Developer Preview Program.
- Answers without credentials: `initialize` and `tools/list` return `200`; `tools/call` returns `401` with
  `WWW-Authenticate: Bearer resource_metadata=".../.well-known/oauth-protected-resource/<tool>"`. The resource metadata
  names `https://accounts.google.com/` as the authorization server.
- Dynamic client registration: no. Google's authorization server metadata has no `registration_endpoint` and no
  client id metadata document support.
- Tools on the day (live `tools/list`, 23): reads `get_message`, `get_thread`, `search_threads`, `list_labels`,
  `list_drafts`, `get_draft`; changes `create_draft`, `create_label`, `label_message`, `unlabel_message`,
  `update_message_labels`, `label_thread`, `unlabel_thread`, `trash_message`, `untrash_message`, `trash_thread`,
  `untrash_thread`, `mark_message_spam`, `unmark_message_spam`, `mark_thread_spam`, `unmark_thread_spam`,
  `apply_sensitive_message_label`, `apply_sensitive_thread_label`. No send tool: it drafts but does not send. Google's
  reference page lists 10 of these.
- Why: sign-in needs the owner's own OAuth client id and client secret (Google's page: "Copy your Client ID and Client
  Secret"), and a plugin cannot hold the secret; adding the server by hand with the secret leaves it unguarded.
- To ship it: Claude Code would have to document a client secret for a plugin's server kept in its own secure storage
  (for example a sensitive `userConfig` value used by `oauth`), or Google would have to offer dynamic client
  registration. The owner would also join the Developer Preview and create a Google Cloud project with an AI-agent
  OAuth client.

### `outlook`

- Server: Microsoft's Agent 365 Mail server,
  `https://agent365.svc.cloud.microsoft/agents/tenants/{tenantId}/servers/mcp_MailTools`, documented at
  https://learn.microsoft.com/en-us/microsoft-copilot-studio/mcp-mail-tools (overview:
  https://learn.microsoft.com/en-us/microsoft-agent-365/tooling-servers-overview).
- Answers without credentials: with a placeholder tenant id, `400` `TenantIdInvalid` and no challenge; it was not tried
  with a real tenant id. Sign-in is Microsoft Entra ID, whose metadata has no `registration_endpoint`.
- Microsoft marks it legacy: the Mail and Teams servers "are only intended for backward compatibility purposes and
  shouldn't be used in production environments or new projects"; new work is pointed to Work IQ MCP. Preview; needs
  the tenant's administrator and licence.
- Tools (Microsoft's page, 10): reads `mcp_MailTools_graph_mail_getMessage`, `mcp_MailTools_graph_mail_listSent`,
  `mcp_MailTools_graph_mail_searchMessages`; changes `createMessage` (a draft), `sendMail`, `sendDraft`, `reply`,
  `replyAll`, `updateMessage`, `deleteMessage` (each prefixed `mcp_MailTools_graph_mail_`).
- Why: no dynamic client registration, so sign-in needs an Entra app registration's client id, which differs per
  tenant and which a plugin cannot take from a variable; and Microsoft itself says not to start new work on it.
- To ship it: the owner decides between waiting and Microsoft's Work IQ MCP (`https://workiq.svc.cloud.microsoft/mcp`,
  also Entra, also no dynamic registration). Work IQ's generic tools (`fetch`, `do_action`, `create_entity`, ...) act on
  a path, so a read list by tool name cannot tell reading mail from sending it (`do_action /me/sendMail`), the same
  trap as Jira's `executeRead`.

### `teams`

- Server: Microsoft's Agent 365 Teams server,
  `https://agent365.svc.cloud.microsoft/agents/tenants/{tenantId}/servers/mcp_TeamsServer`, documented at
  https://learn.microsoft.com/en-us/microsoft-copilot-studio/mcp-teams-tools.
- Answers without credentials: as `outlook` (`400` `TenantIdInvalid` with a placeholder tenant id).
- Microsoft marks it legacy, as `outlook`. Preview; scope `McpServers.Teams.All`.
- Why: as `outlook`.
- To ship it: as `outlook`.

### `slack`

- Server: `https://mcp.slack.com/mcp`, documented at https://docs.slack.dev/ai/slack-mcp-server (Claude Code:
  https://docs.slack.dev/ai/slack-mcp-server/connect-to-claude).
- Answers without credentials: `401`, `WWW-Authenticate: Bearer
  resource_metadata="https://mcp.slack.com/.well-known/oauth-protected-resource"`.
- Dynamic client registration: no. Slack's page: "We do not support SSE-based connections or Dynamic Client
  Registration at this time", and "MCP clients must be backed by a registered Slack app with a fixed app ID and
  hardcode that app ID". The metadata has no `registration_endpoint`; its token endpoint takes `client_secret_post`.
  Slack also offers PKCE for desktop clients.
- Sign-in inside a plugin does work: Slack's own Claude Code plugin declares the server in its `.mcp.json` with an
  `oauth` object holding Slack's published client id and `callbackPort` 3118, and no secret. A workspace administrator
  approves the app.
- Tool names Slack publishes (its page and its own plugin's skills; the full list comes only from the signed-in
  server): reads `slack_search_public`, `slack_search_public_and_private`, `slack_search_channels`,
  `slack_search_users`, `slack_read_channel`, `slack_read_thread`, `slack_read_user_profile`,
  `slack_list_channel_members`; asks `slack_read_file` (opens a file), `slack_send_message_draft`,
  `slack_get_file_upload_url`, `slack_complete_file_upload`, and every unnamed tool (send, schedule, react, create
  channel, canvases, lists).
- Why: the only documented way is Slack's client id written into the plugin's `.mcp.json`, and this repo keeps every
  client id out (and story K3 wanted it from an environment variable, which `oauth` does not document).
- To ship it: the owner decides whether a vendor's published client id (Slack's app for Claude, not the owner's) may be
  written into `.mcp.json`. If yes, the plugin is built as K1's with the read list above. Slack also publishes its own
  plugin, `slack@slack`, whose server key is `slack`; installing both would give two servers at one address.

### `discord`

- Story K3 records that Discord has not published an MCP server of its own, leaving a community package run with the
  owner's bot token. Not checked again on the day, because the open question below holds it either way.
- Why: story K3's open question is not answered.
- To ship it: the owner answers K3's open question (a community package pinned to one version, the bot token only from
  ade-secrets).

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
7. For `orgo` (story K8), the same steps with `plugin:orgo:orgo`, choosing a test workspace at sign-in. Compare the tool
   list `/mcp` shows with `plugins/orgo/hooks/read-tools.txt`. Ask for a computer to be created and see the question
   say that Orgo bills it by the hour while it runs; ask for a command and see its first line in the question; decline
   both. Revoke in Orgo's Settings, Security, Connected AI apps.
6. Sign out with Clear authentication, and revoke at the vendor as above.
