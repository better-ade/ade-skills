---
description: Add a specialist from ade-agent-registry to this project (ade agent add).
argument-hint: <name>
---

This changes the project. Run this one command with the Bash tool, then report its output. The names come from
`ade agent list`.

Before running it, escape every `"`, `$` and backtick in each argument with a backslash; if an argument contains a newline, run nothing and say why.

```bash
ade agent add "$1"
```
