# P1: the `ade` plugin: drive ADE from inside Claude Code

Status: Ready for development (2026-11-21). Risk: medium (lets the model start agents). Depends on ade-cli A1.
Verification command: `bash tests/run.sh`.

## Goal
A plugin `ade` with slash commands that call the `ade` CLI, a skill telling the model when to use it, and permission
rules that keep anything that starts agents or changes state behind the owner's prompt.

- Commands: `/ade:status`, `/ade:work <folder> [role]`, `/ade:dispatch <folder>`, `/ade:notify <to> <text>`,
  `/ade:agent-add <name>`, `/ade:skills-add <plugin>`, `/ade:doctor`.
- Skill `ade`: when the user asks to start work on a ticket, see what agents are doing, message an agent, or add a
  specialist or plugin, use the matching `ade` command; never `--approve` on the user's behalf.
- Permissions (in the plugin README for the project's settings, since a plugin cannot grant them): allow
  `Bash(ade status*)`, `Bash(ade doctor*)`, `Bash(ade agent list*)`; ask `Bash(ade work*)`, `Bash(ade dispatch*)`,
  `Bash(ade chat*)`, `Bash(ade notify*)`; deny `Bash(*--dangerously-skip-permissions*)`.

## Acceptance criteria (no model calls)
| AC | Criterion |
|---|---|
| 1 | The plugin passes `claude plugin validate` and the repo checks (`## Ask first` in the skill) |
| 2 | Each command file runs exactly one `ade …` command with the user's arguments quoted; a check greps each |
| 3 | The skill's `## Ask first` names starting agents, approving tickets, starting a chat orchestrator, and messaging agents |
| 4 | The README's permission block is valid settings JSON (a check parses it) and has the allow, ask and deny rules above |
| 5 | The marketplace lists `ade`; `VERSION` and `CHANGELOG.md` record the release |
