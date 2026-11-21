# Changelog

## 0.4.0

- `fde` plugin, part 1 (F1a): `discovery` writes `docs/customer/constraints.md`; `proposal`, `sow` and
  `change-request` draft from it with every price, date and legal term left as a `[[TO FILL: ...]]` blank.
- `tests/fde.sh`: constraints first, no price, date or duration in the commercial templates, blanks in Pricing,
  Timeline and Terms, SOW acceptance criteria, ask-first rules; `tests/meta.sh` tests its leak patterns.
- Review hardening: wider leak patterns (symbols, codes after numbers, word durations, quarters, payment terms,
  slash and month-name dates), legal keywords outside blanks, Pricing, Terms and Change process hold only blanks,
  constraints-first as the first line, exact Ask first bullets, the provider rule, `## Approved tools and
  destinations`, gitleaks on `constraints.md`; a fifth convention line (read only inside the named folder) for every
  document plugin (`notes` 0.1.1 carries it). `tests/meta.sh` has a negative case for each.

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
