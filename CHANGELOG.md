# Changelog

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
