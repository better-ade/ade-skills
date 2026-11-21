---
description: Start deep work on a folder in a new terminal, optionally as a role (ade work).
argument-hint: <folder> [role]
---

This starts an agent. Run one of these two commands with the Bash tool, then report its output. Do not add other flags.

Before running it, escape every `"`, `$` and backtick in each argument with a backslash; if an argument contains a newline, run nothing and say why.

Without a role:

```bash
ade work "$1"
```

Only when a role was given:

```bash
ade work --role "$2" "$1"
```
