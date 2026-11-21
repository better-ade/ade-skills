# Changelog

## 0.5.0

- `fde` plugin 0.2.0, part 2 (F1b): `design-doc` (wraps `bmad-architecture`), `workflow` (current and future Mermaid
  maps with step tables), `status-report` (from the folder's tickets and journal only) and `handover`; design and
  handover templates keep secrets to names and locations.

## 0.4.0

- `fde` plugin, part 1 (F1a): `discovery` writes `docs/customer/constraints.md`; `proposal`, `sow` and
  `change-request` draft from it with every price, date and legal term left as a `[[TO FILL: ...]]` blank.
- `tests/fde.sh`: constraints first, no price, date or duration in the commercial templates, blanks in Pricing,
  Timeline and Terms, SOW acceptance criteria, ask-first rules; `tests/meta.sh` tests its leak patterns.

## 0.3.0

- `notes` plugin (N1): `meeting-notes`, `summarize`, `action-items`, `digest`, `capture`, writing into the named folder.
- `docs/conventions.md`: the shared rules for document plugins (folder, approved providers, templates, the four lines).
- Checks: `tests/validate.sh` validates every plugin `marketplace.json` lists and fails when `claude` is missing;
  `tests/docs.sh` checks document plugins; `tests/meta.sh` tests both on fixtures.

## 0.2.0

- `ade` plugin (P1): `/ade:status`, `/ade:work`, `/ade:dispatch`, `/ade:notify`, `/ade:agent-add`, `/ade:skills-add`,
  `/ade:doctor`, the `ade` skill, and the permission block for the project's settings; `tests/ade.sh` checks them.

## 0.1.0

- First slice: marketplace, plugin template, git and browser plugins, checks.
