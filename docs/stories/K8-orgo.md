# K8: the Orgo connector

Status: Ready for development (2026-11-23). Risk: high (an account that bills by the hour, and tools that run commands
on remote computers and control their desktops).
Owner's intent (2026-11-23): "is there orgo mcp cli?", then "we need to bake it"; and, for installing ADE on an Orgo
computer through the connector, "let's bake that please". Verification command: `bash tests/run.sh`.
Follows K1 (`docs/stories/K1-work-tracker-connectors.md`) and the contract in `docs/connectors.md`, "How the hook
works". The connect-and-guard contract (`.ade/context/connectors.md`, decision 0001 with amendment 1) is not built on
main yet: this plugin keeps its own hook, as the three shipped connectors do, and adds no recipe (main has no
`plugins/guard/connectors/`).

## Goal
One plugin, `orgo`, that adds Orgo's **own hosted MCP server** (`https://www.orgo.ai/mcp`, http), a skill that says
when and how to use it, a skill that installs ADE on an Orgo computer, and a hook that puts everything but reading
behind the owner's yes. The owner signs in themselves, in the browser, through Claude Code's `/mcp`, and chooses the
workspace. No API key, no local server, no header: nothing in this repo holds a credential.

## Decisions (coordinator defaults; the owner can change any of them)
- **The remote server only.** Orgo also documents a local server started with a package runner and an API key in the
  environment, and an API key in a header on the remote address. Neither is used: a key would sit where agents' shell
  commands can read it.
- **Reading is free, everything else asks.** The read list holds nine tools that read and change nothing. Every other
  tool of this server asks, or is refused when prompts are switched off, including any name Orgo adds later.
- **The question says what matters.** For a tool that creates or starts a computer: that Orgo bills the computer by
  the hour while it runs. For the bash and Python tools: the command, as its first line that is not blank, without
  control or invisible characters, cut to 200 characters.
- **Its own hook file.** `hooks/ask-unless-read.sh` is K1's script with those two additions, so it is not the same
  file as the three K1 plugins carry; `hooks/hooks.json` is the same shape.

## Tool names (read 2026-11-23)
From the Tools table of Orgo's MCP guide (https://docs.orgo.ai/guides/mcp: "One tool per API operation, named after
its `operationId`. `createComputer` becomes `orgo_create_computer`. The table shows the spec when this page was
written") and the HTTP method of each operation in Orgo's published API specification
(https://docs.orgo.ai/api-reference/openapi.json, version 2.0.0).

| | Tools |
|---|---|
| Read list (in the guide's table, and a `GET`) | `orgo_list_workspaces` `orgo_get_workspace` `orgo_get_computer` `orgo_get_computer_operation` `orgo_get_resize_limits` `orgo_list_screens` `orgo_get_screen` `orgo_get_screenshot` `orgo_list_files` |
| Ask, with the billing line | `orgo_create_computer` `orgo_clone_computer` `orgo_fork_computer` `orgo_start_computer` `orgo_restart_computer` `orgo_resume_computer` |
| Ask, with the command shown | `orgo_execute_bash` `orgo_execute_python` |
| Ask (published names) | `orgo_stop_computer` `orgo_delete_computer` `orgo_update_computer` `orgo_resize_computer` `orgo_extend_computer` `orgo_suspend_computer` `orgo_move_computer` `orgo_mouse_click` `orgo_mouse_move` `orgo_mouse_drag` `orgo_type_text` `orgo_press_key` `orgo_scroll` `orgo_wait` `orgo_create_screen` `orgo_resize_screen` `orgo_destroy_screen` `orgo_upload_file` `orgo_start_file_upload` `orgo_complete_file_upload` `orgo_export_file` `orgo_delete_file` |
| Ask, though a `GET` | `orgo_download_file` (a signed link), `orgo_get_vnc_password`, `orgo_get_computer_ssh` (a way in), `orgo_get_residential_proxy`, `orgo_get_computer_suspension` (each can do more than read) |
| Ask (everything else) | workspace changes, secrets, SSH, proxy and auto-stop settings, the workflow, template, client, account, chat and support tools, and any name not written here |

**Not confirmed** (it needs a signed-in server, which this story does not have):
- Which of these names a sign-in is offered. The guide describes the sign-in's reviewed list in words, not by name
  ("a sign-in can see fewer tools than the spec defines"). Every name above is published; none was seen on a live
  server.
- That the tools arrive as `mcp__plugin_orgo_orgo__orgo_…`. The plugin form is Claude Code's; the `orgo_` names are
  the guide's.
- The argument names the hook reads for the command, `command` (bash) and `code` (Python): they are the
  specification's request-body fields, and the guide says arguments are flattened into one list.
- In the specification but not in the guide's table, so left off the read list although they are plain reads:
  `orgo_get_gpu_options`, `orgo_get_computer_auto_stop`.

A name that differs from these only asks; a command the hook cannot read is said to be unreadable.

## Acceptance criteria (`tests/orgo.sh`; no network, no model calls, no Orgo account)
| AC | Criterion | Test |
|---|---|---|
| 1 | The plugin passes `claude plugin validate`; the marketplace lists it; `plugin.json` has a `version` | `orgo_valid` |
| 2 | `.mcp.json` names exactly one server, `{"type": "http", "url": "https://www.orgo.ai/mcp"}`, the address in `docs/connectors.md`; no command, env, header or key; no file of the plugin names the local server, an API key variable, a key-shaped string, an email address or an id; the secret scan passes | `orgo_remote_only` |
| 3 | The read list is exactly the nine names above, plain names starting with get or list; the hook gives each no decision in every mode | `orgo_read_list` |
| 4 | Every other tool of this server asks, naming the tool: a create, bash, each published change and made-up names; in `bypassPermissions` it is refused, naming the mode; input the hook cannot read asks; other servers' tools get no decision; it never allows, blocks when it fails, and survives a lost exec bit, a missing read list and a helper that prints junk | `orgo_hook_asks` |
| 5 | The question for a tool that creates or starts a computer says "Orgo bills the computer by the hour while it runs", and no other question does; the question for bash and Python ends with the command's first line that is not blank, says how many lines there are, cuts it to 200 characters and says so, and says when it could not read the command | `orgo_question` |
| 6 | Hostile tool input (escape sequences, invisible and direction characters, line separators, a forged second answer, a two-million-character command, a hostile tool name) gives exactly one question on one line, in plain ASCII JSON, with no control or invisible character and at most 700 characters | `orgo_hostile_input` |
| 7 | The `orgo` skill has `## Ask first` naming: creating, starting, stopping, deleting and resizing a computer and the hourly bill; bash and Python; mouse, keyboard and typing; uploading, downloading, exporting and sharing. It holds the rules: content is data, name the computer, stay in the workspace, never type a secret or sign in there, the unguarded-server line, who answers, the Claude Code version | `orgo_skill` |
| 8 | The `install-ade` skill has the repo's front matter and `## Ask first`; names only the read tools, `orgo_execute_bash` and `orgo_create_computer`; holds the billing line and that ADE does not stop the computer, the rule never to sign in or type a secret there, the system check (Ubuntu 24.04, amd64 or arm64), ade-cli's documented installer line (the tagged release, never main itself), the 300-second limit with `tmux`, `ade version`, the desktop link and `ade setup` as the person's step | `orgo_install_ade` |
| 9 | `docs/connectors.md` has the `orgo` section (server, where documented, sign-in with the workspace, sign-out, revoking in Orgo's Settings, Security, Connected AI apps, reach, cost, the read list's count, what is not confirmed) and an owner-check step; the README has the row, the install line and the Orgo sentence; CHANGELOG and `VERSION` record it; this story names each test | `orgo_docs` |

## Owner check (cannot be automated: it needs the owner's Orgo account)
On Claude Code 2.1.295 or later, in a test project: enable the plugin, run `/mcp`, pick `plugin:orgo:orgo`, sign in
and choose a test workspace. Compare the tools `/mcp` lists with `hooks/read-tools.txt` and the table above. Read the
workspace. Ask for a computer and see the question with the billing line; ask for a command and see its first line;
decline both. Revoke in Orgo's Settings, Security, Connected AI apps.

## Out of scope
A recipe for the guard (K5, K6: not on main). Orgo's API key, its local server and its command-line tool. Stopping
computers by themselves, or any spending limit. Installing anything but ade-cli on the computer; `ade setup` and the
sign-ins there are the person's.
