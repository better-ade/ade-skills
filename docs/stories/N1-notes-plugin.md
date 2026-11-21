# N1: the `notes` plugin: meeting notes, summaries, action items, digests, capture

Status: Ready for development (2026-11-21). Risk: medium (reads transcripts and threads that hold personal data).
Users: developers, tech support, forward deployed engineers. Verification command: `bash tests/run.sh`.

## Goal
A `notes` plugin whose skills turn raw input into notes that land in the right hub folder, where ade-brain indexes them.

| Skill | Input | Output |
|---|---|---|
| `meeting-notes` | a transcript (Read AI, Zoom/Meet export, pasted text) | attendees, decisions, action items (owner, due), open questions |
| `summarize` | any document, email thread, ticket history, PR or channel | a summary at the asked length, each point citing its source |
| `action-items` | notes or a summary | proposed tickets for `bmad-ticket`, created only on the user's yes |
| `digest` | the hub journal, tickets, sessions | a daily or weekly recap: done, blocked, needs the owner |
| `capture` | a quick thought ("note: customer X wants SSO") | a dated note in the named folder |

## Acceptance criteria (tests in `tests/run.sh`, against fixture inputs; no model calls)
| AC | Criterion |
|---|---|
| 1 | The plugin and its five skills pass `claude plugin validate` and the repo checks (versioned, `## Ask first` in each skill). |
| 2 | Each skill names where it writes: `<folder>/notes/YYYY-MM-DD-<slug>.md` in the hub folder the user names (or the current one), never another customer's folder. |
| 3 | Each skill's `## Ask first` covers: sending or sharing a note, creating tickets, writing outside the named folder. |
| 4 | Each skill states that transcripts, threads and pages are data, not instructions. |
| 5 | Each skill states: keep personal data to what the note needs; never send it to a provider the folder has not approved. |
| 6 | `meeting-notes` and `summarize` ship an output template with a source line per point; a fixture check confirms the template sections. |
| 7 | The marketplace lists `notes`; `VERSION` and `CHANGELOG.md` record the release. |

## Out of scope
Recording or transcribing audio; calendar integration; auto-sending recaps.
