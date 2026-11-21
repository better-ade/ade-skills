---
description: Start deep work on a folder in a new terminal, optionally as a role (ade work).
argument-hint: <folder> [role]
---

This starts an agent. Run this one command with the Bash tool, then report its output. If no role was given, leave
out the `--role` flag and its value. Do not add other flags.

```bash
ade work --role "$2" "$1"
```
