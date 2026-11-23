---
name: install-ade
description: Install ADE (the ade command) on one of the person's Orgo computers through Orgo's MCP server. Use when the person says "install ADE on my Orgo computer" or asks for ADE on a cloud desktop.
---

# Install ADE on an Orgo computer

The person asks their main agent; the agent does the steps below through this plugin's Orgo server
(`mcp__plugin_orgo_orgo__*`), with no command-line tool of Orgo's. Follow the `orgo` skill's rules as well.

- Never sign in for the person, and never type, paste or send a token, password or key on the remote computer.
- Never create, start, stop or delete a computer the person did not name.
- Everything here runs as Orgo's user, which is root on an Orgo computer, and every step but reading goes through this plugin's hook, which asks the person.
- After a failure, say in one line what failed, then what was and was not changed; retry a step at most once, and say that you did.

## Steps

1. **Pick the computer.** Read the workspaces with `orgo_list_workspaces` and the workspace's computers with
   `orgo_get_workspace` (they are under `desktops`); `orgo_get_computer` gives one computer's state. List them by name
   and ask the person which one. If there is none, offer to create one with `orgo_create_computer`, and say first:
   Orgo bills the computer by the hour while it runs, and ADE does not stop it. If the computer they name is stopped,
   say the same before starting it is asked for; do not start it yourself.
2. **Check the system**, with `orgo_execute_bash` on that computer:

   ```bash
   cat /etc/os-release; uname -m
   ```

   Go on only when it is Ubuntu 24.04 (`ID=ubuntu`, `VERSION_ID="24.04"`) on amd64 (`x86_64`) or arm64 (`aarch64`).
   Otherwise stop with one plain line: what the computer runs, and that ADE installs on Ubuntu 24.04 on amd64 or arm64.
3. **Run ade-cli's public installer**, with `orgo_execute_bash`. It is the one line ade-cli's README documents:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/better-ade/ade-cli/main/install.sh | bash
   ```

   The installer reads the release number on main, downloads the tagged release of that number, never main itself,
   checks the download against the sha256 in that release's `release.json`, and installs nothing when they differ. It
   writes `~/.local/bin/ade` (here `/root/.local/bin/ade`) and names any tool that is missing; it installs no system
   package when it is piped. It needs `curl` and `python3` on the computer. Run exactly this line: no other branch,
   tag or address, and nothing added to it.
4. **Mind the time limit.** A bash call ends after at most 300 seconds. The installer is short. If a step could run
   longer, start it detached in `tmux`, writing to a log, and read the log in later calls, never in one long call:

   ```bash
   tmux new-session -d -s ade-install 'curl -fsSL https://raw.githubusercontent.com/better-ade/ade-cli/main/install.sh | bash > /root/ade-install.log 2>&1'
   tmux has-session -t ade-install 2>/dev/null && echo running || echo finished; tail -n 20 /root/ade-install.log
   ```
5. **Verify**, with `orgo_execute_bash`: `~/.local/bin/ade version` (Orgo's bash tool does not have `~/.local/bin` on
   its `PATH`, so give the path). Report the line `ade version` prints, as it is.
6. **Hand over to the person.** Give the desktop link, `https://www.orgo.ai/computers/<id>` with the computer's id,
   and the next step, which is theirs: open the desktop, open a terminal, and type `ade setup`. That guide installs
   the rest and signs them in to Claude and GitHub there, in their own hands. Say again that the computer is still
   running and billed by the hour until they stop it.

## Ask first

- Creating or starting a computer: ask first, with the billing line above. Stopping or deleting one: only when the
  person asks for it by name.
- Each command on the computer: the hook asks the person and shows the command's first line; show the whole command
  in the conversation before you call the tool.
- Installing a system package, changing a setting, or running anything this skill does not list: ask first.
- Signing in to Claude, GitHub or anything else on the computer: never; it is the person's step, at the desktop.
