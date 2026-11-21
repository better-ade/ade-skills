---
description: Send a message to an agent or the owner (ade notify).
argument-hint: <to> <text>
---

This sends a message. `<to>` is the first word of `$ARGUMENTS`; `<text>` is the rest. Run this one command with the
Bash tool, with both values in double quotes, then report its output.

Before running it, escape every `"`, `$` and backtick in each argument with a backslash; if an argument contains a newline, run nothing and say why.

```bash
ade notify "<to>" "<text>"
```
