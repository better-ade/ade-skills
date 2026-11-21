# F1b: `fde` plugin, part 2: design doc, workflow, status report, handover

Status: Ready for development (2026-11-21). Risk: medium. Depends on F1a. Verification command: `bash tests/run.sh`.

## Goal
`design-doc` (wraps `bmad-architecture`: context, diagram, integrations, security, rollout), `workflow` (current and
future process maps in Mermaid, with step tables), `status-report` (from the folder's tickets and journal: done, next,
risks, decisions needed) and `handover` (runbook, architecture summary, operate and support notes, open issues).

## Acceptance criteria (no model calls)
| AC | Criterion |
|---|---|
| 1 | The four skills pass `claude plugin validate`, the repo checks, `tests/docs.sh` and the constraints-first rule of F1a AC2. |
| 2 | Each has `skills/<name>/template.md` with its named sections; `tests/fde.sh` checks the headings. |
| 3 | `status-report` reads only the named folder. |
| 4 | `handover` and `design-doc` templates have a `## Secrets` section that says "names and locations only". |
| 5 | Each `## Ask first` names sending, sharing or exporting; export only to an approved target. |
| 6 | `VERSION` and `CHANGELOG.md` record the release. |
