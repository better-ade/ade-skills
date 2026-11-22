# K5: connector recipes

Status: Ready for development (2026-11-22). Risk: high (what a recipe says decides what the guard lets through).
Owner's intent (2026-11-22): "so the skills are predefined but authentication is per user"; order approved the same
day ("yes that works"). Decision record: `.ade/context/decisions/0001-connect-and-guard.md`. Contract:
`.ade/context/connectors.md` (sections 1 and 2). Where this story and the contract differ, the contract wins: stop
and say so. Verification command: `bash tests/run.sh`.

## Goal
One data file per service, `plugins/guard/connectors/<service>.json`, in format 1: the single place that says how a
service is signed in to, which tier it is, and which of its tools are reads. ade-cli reads them (A16); the guard reads
them (K6). A recipe is data: nothing in it is run, and nothing in it differs per user.

## Acceptance criteria (`tests/recipes.sh`; no network, no model calls)
| AC | Criterion | Test |
|---|---|---|
| 1 | Nine recipes exist (`clickup`, `jira`, `linear`, `github`, `gmail`, `slack`, `discord`, `outlook`, `teams`), each passing every field rule of format 1 in the contract | `recipes_valid` |
| 2 | The checker refuses a recipe with an unknown field, an unknown `sign_in.kind`, an unknown answer target or a format other than `1`, each with a one-line reason; it is one small script other repos can run on a file | `recipes_refuse_unknown` |
| 3 | Tiers and states are as the contract's section 2: `clickup`, `jira`, `linear` tier 0 and ready; `github` and `gmail` tier 2, held until K7 ships their skills; `slack` tier 1, `discord` tier 3, `outlook` and `teams` tier 4, each held with its one-line reason | `recipes_tiers` |
| 4 | For a `plugin` recipe, `guard.read` holds exactly the names in that plugin's `hooks/read-tools.txt`, and its prefixes include the plugin's own; changing either side alone fails | `recipes_match_plugins` |
| 5 | No recipe holds a secret, a client id, a tenant, an account, a workspace or a person's name | `recipes_no_secret` |
| 6 | Every address or host in a recipe is on that vendor's own domain | `recipes_hosts` |
| 7 | The `guard` plugin folder that carries the recipes passes `claude plugin validate` and is listed in the marketplace, described as holding the recipes (its hook is story K6) | `recipes_plugin_valid` |
| 8 | A release publishes each recipe's sha256 in `release.json` under the name `connector-<service>.json`, the way the contract's pinning rule needs; if the shared release workflow cannot do that yet, the story says so and stops before inventing another way | `recipes_release_assets` |
| 9 | `docs/connectors.md`, README and CHANGELOG record the recipes; `VERSION` is raised | `recipes_listed` |

## Notes for the builder
- Work through the contract's "To confirm before building" list first for the items this story touches (the release
  workflow, the Gmail connector's real tool names). What cannot be confirmed stays marked "not confirmed on the day".
- Out of scope: the guard's hook (K6), any change to the three shipped plugins' hooks, `ade connect` (ade-cli A16).
