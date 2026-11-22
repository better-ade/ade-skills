# K6: the guard

Status: Ready for development (2026-11-22). Risk: high (it is the check between an agent and the owner's accounts).
Depends on K5. Contract: `.ade/context/connectors.md` (sections 4 and 6); decision record
`.ade/context/decisions/0001-connect-and-guard.md`. The contract wins over this story. Verification command:
`bash tests/run.sh`.

## Goal
One plugin, `guard`, whose hook covers a connector's tools wherever its server is set up: a plugin's server, a
claude.ai connector, and `gh` and `git` run through the shell. Reading is free; a change asks, or is refused when
prompts are switched off. The three shipped plugins keep their own hooks unchanged.

## Acceptance criteria (`tests/guard.sh`; no network, no model calls; the hook is run exactly as `hooks.json` declares it)
| AC | Criterion | Test |
|---|---|---|
| 1 | `hooks/hooks.json` has one matcher per recipe prefix and one for the shell tool, each in exec form with `"onFailure": "block"`; it is generated from the recipes and a test fails when the two differ | `guard_matchers_from_recipes` |
| 2 | A tool on its recipe's read list gets no decision; any other tool under that prefix gets `ask` with a reason naming the tool, or `deny` naming the mode under `bypassPermissions` | `guard_asks` |
| 3 | In a folder whose `.ade/connectors.json` does not name the connector, every tool of that connector asks, reads included (the contract says how the hook learns the folder) | `guard_folder_rule` |
| 4 | A tool of a server no recipe names gets no decision | `guard_unknown_server` |
| 5 | Shell commands: a single simple command whose leading words are on the recipe's exact `free` list gets no decision; anything else that can run `gh` or `git` asks: a pipeline, `&&`, `;`, a subshell, `sh -c`, a substitution, a variable or path in place of the name, `command`, `env`, `xargs`, a here-document | `guard_gh_git` |
| 6 | `gh api` always asks; `gh auth token`, `--show-token` and `git credential` are always refused, in any mode | `guard_gh_refused` |
| 7 | A shell command that cannot run `gh` or `git` gets no decision, and the hook adds no more than a small, measured delay to it (the test sets the limit) | `guard_other_commands` |
| 8 | Input it cannot read, a missing or invalid recipe, or a missing helper ends in `ask`, never silence; it prints exactly one JSON object or nothing | `guard_fail_closed` |
| 9 | The shipped plugins' hooks are unchanged and still pass their tests; what happens when both hooks ask about one call is confirmed and written down | `guard_with_plugin_hooks` |
| 10 | `docs/connectors.md` says what the guard does not see (a script or a git hook that calls `gh`, MCP resources) and when the owner is not the one answering | `guard_docs` |

## Notes for the builder
- Each check must fail when its behaviour is undone; try each once on a copy.
- Out of scope: `ade connect`, the doctor check (ade-cli A17), the skill-only `github` and `gmail` plugins (K7).
