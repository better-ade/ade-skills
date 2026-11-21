---
description: Send a message to an agent or the owner (ade notify).
argument-hint: <to> <text>
---

This sends a message. `<to>` is the first word of `$ARGUMENTS`; `<text>` is the rest. Run this one command with the
Bash tool, with both values in double quotes (escape any `"` or `$` inside the text), then report its output.

```bash
ade notify "<to>" "<text>"
```
