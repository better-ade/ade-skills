# F1: the `fde` plugin: discovery, proposal, SOW, design doc, workflow, status, change request, handover

Status: Ready for development (2026-11-21). Risk: high (customer-facing commitments and customer data).
Users: software engineers who are forward deployed engineers; works with the `forward-deployed` specialist
(ade-agent-registry). Depends on N1 for shared note and template conventions. Verification command: `bash tests/run.sh`.

## Goal
An `fde` plugin whose skills draft the documents of a customer engagement, in that customer's folder, reusing BMAD where
it already fits (`bmad-architecture` for the design, `bmad-prfaq`, `bmad-deep-recon`, `bmad-ticket`).

| Skill | Produces |
|---|---|
| `discovery` | `docs/customer/constraints.md`: goals, stakeholders, current state, constraints, approved AI providers, data boundaries |
| `proposal` | problem, approach, options with trade-offs, timeline, pricing placeholders |
| `sow` | scope, deliverables, acceptance criteria (testable), assumptions, out of scope, milestones, change process |
| `design-doc` | customer-facing solution design wrapping `bmad-architecture`: context, diagram, integrations, security, rollout |
| `workflow` | current and future process maps (Mermaid) with step tables |
| `status-report` | weekly status from tickets and the journal: done, next, risks, decisions needed |
| `change-request` | what, why, impact on time and cost, an approval line, linked to the SOW |
| `handover` | runbook, architecture summary, operate and support notes, open issues |

## Acceptance criteria (tests in `tests/run.sh`, against fixture inputs; no model calls)
| AC | Criterion |
|---|---|
| 1 | The plugin and its eight skills pass `claude plugin validate` and the repo checks. |
| 2 | Every document is a draft: each skill's `## Ask first` covers sending, sharing or signing anything with a customer. |
| 3 | `proposal`, `sow` and `change-request` never invent prices, dates or legal terms: their templates mark them as `[[TO FILL: ...]]` blanks, and a fixture check confirms no template holds a number for price or a date. |
| 4 | Every skill reads `docs/customer/constraints.md` first and stops if it is missing (pointing to `discovery`), and never uses a provider the constraints do not approve. |
| 5 | Every skill writes only inside the named customer folder; nothing is copied between customers. |
| 6 | `sow` acceptance criteria are written one per line in a form a test can prove (the template says so and a fixture check confirms the section). |
| 7 | Each skill ships its template under `skills/<name>/template.md`; documents export to Word, Google Docs or PDF only on request. |
| 8 | The marketplace lists `fde`; `VERSION` and `CHANGELOG.md` record the release. |

## Out of scope
E-signature, invoicing, CRM updates, sending email.
