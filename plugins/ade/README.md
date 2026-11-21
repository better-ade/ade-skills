# ade

Drive ADE from inside Claude Code. The commands call the [`ade` CLI](https://github.com/better-ade/ade-cli), which
must be on `PATH`; the `ade` skill tells the model which command fits the request.

| Command | Runs |
|---|---|
| `/ade:status` | `ade status` |
| `/ade:work <folder> [role]` | `ade work --role <role> <folder>` |
| `/ade:dispatch <folder>` | `ade dispatch <folder>` |
| `/ade:notify <to> <text>` | `ade notify <to> <text>` |
| `/ade:agent-add <name>` | `ade agent add <name>` |
| `/ade:skills-add <plugin>` | `ade skills add <plugin>` |
| `/ade:doctor` | `ade doctor` |

## Permissions

A plugin cannot grant permissions, so add these to the project's `.claude/settings.json`. Reading status is allowed;
anything that starts agents, opens a chat orchestrator or sends a message asks the owner; skipping permissions is
denied. Approving a ticket (`ade dispatch --approve`) stays with the owner.

```json
{
  "permissions": {
    "allow": ["Bash(ade status*)", "Bash(ade doctor*)", "Bash(ade agent list*)"],
    "ask": ["Bash(ade work*)", "Bash(ade dispatch*)", "Bash(ade chat*)", "Bash(ade notify*)"],
    "deny": ["Bash(*--dangerously-skip-permissions*)"]
  }
}
```
