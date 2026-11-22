# K1b: the GitHub connector

Status: Waiting for the owner's choice (2026-11-22). Risk: high (sign-in and access to the owner's repositories).
Split from K1 after its adversarial review. The plugin as first built is on branch `K1b-github` (not merged).
Verification command: `bash tests/run.sh`.

## Why it was split
GitHub's hosted MCP server (`https://api.githubcopilot.com/mcp/`) cannot be signed in to through Claude Code's `/mcp`
the way ClickUp, Jira and Linear can: GitHub's sign-in server does not let a client register itself. The two ways
round that were first documented both broke K1's promise ("every change through this server asks"):

- **Adding the server yourself with a client id** puts the server outside the plugin, where the plugin's hook never
  fires.
- **A token in a header** has to come from an environment variable, which agents' shell commands can read.

## The choices (owner decides)
| | Choice | What it needs | What is given up |
|---|---|---|---|
| A | **The owner's own GitHub OAuth app, declared inside the plugin** (the client id from an environment variable, the app's secret kept by Claude Code in the system keychain) | Claude Code must support an OAuth client id in a plugin's `.mcp.json`; the builder confirms this in the documentation before anything is built. The owner registers one OAuth app | Nothing, if the documentation confirms it. If it does not, this choice is not available |
| B | **No MCP server: the `github` plugin guards `gh`** (a skill plus a hook on shell commands that asks before `gh` or `git` changes anything on GitHub: merge, push, release, settings, secrets) | Nothing new: `gh` is already signed in on the owner's machine and is what ADE uses today | GitHub's MCP tools; agents use `gh` as they do now |
| C | **Wait** until GitHub's sign-in works through `/mcp` | Nothing | A GitHub connector, for now |

**Coordinator's recommendation:** B now, because it guards the door agents already use, and A when the documentation
confirms it. GitHub's read-only address (`/mcp/readonly`), where GitHub itself refuses changes, is the safer address
for A's first version.

## Acceptance criteria
Written when the owner has chosen; K1's criteria (vendor server only, no secret, the hook asks or refuses, honest docs)
apply to A, and the same "asks or refuses" rule applies to B's hook on `gh` and `git`.

## Out of scope
A token in a project file, an environment variable or a command line, in any choice.
