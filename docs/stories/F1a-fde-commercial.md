# F1a: `fde` plugin, part 1: discovery, proposal, SOW, change request

Status: Ready for development (2026-11-21). Risk: high (customer commitments). Depends on N1 (conventions).
Users: forward deployed engineers, with the `forward-deployed` specialist. Verification command: `bash tests/run.sh`.

## Goal
`discovery` writes `<folder>/docs/customer/constraints.md` (goals, stakeholders, current state, constraints,
`## Approved AI providers`, data boundaries). `proposal`, `sow` and `change-request` draft from it, with every price,
date and legal term left as a `[[TO FILL: ...]]` blank.

## Acceptance criteria (no model calls)
| AC | Criterion |
|---|---|
| 1 | The `fde` plugin with these four skills passes `claude plugin validate`, the repo checks and `tests/docs.sh`. |
| 2 | Every skill except `discovery` states it reads `<folder>/docs/customer/constraints.md` first and stops, pointing to `discovery`, when it is missing. |
| 3 | `tests/fde.sh` fails if a template of `proposal`, `sow` or `change-request` matches a currency symbol or code next to a digit (`[$€£]\s?\d`, `\b(USD|EUR|GBP|CAD|PHP)\s?\d`), a date (`\d{4}-\d{2}-\d{2}`), or a duration (`\d+\s?(days|weeks|months)`). |
| 4 | Those templates contain `[[TO FILL:` blanks in the sections `## Pricing`, `## Timeline` and (sow) `## Terms`. |
| 5 | The `sow` template's `## Acceptance criteria` section says one criterion per line, each provable by a test or recorded evidence. |
| 6 | Each `## Ask first` names sending, sharing, signing or exporting a document; export goes only to a target the constraints approve. |
| 7 | The marketplace lists `fde`; `VERSION` and `CHANGELOG.md` record the release. |
