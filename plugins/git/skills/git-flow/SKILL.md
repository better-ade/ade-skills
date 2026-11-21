---
name: git-flow
description: How to branch, commit, push and open pull requests in an ADE project. Use before any commit, push or PR.
---

# Git flow

1. **Branch** from the default branch, named for the story (`<story-id>-<short-slug>`). Never commit to the default branch.
2. **Commit** under the user's own git identity, with a message that says what changed and why. Add no AI attribution:
   no `Co-Authored-By` trailer for an agent or model, no "Generated with" line.
3. **Stage only the story's files** (`git add <paths>`), never `git add -A` in a repo with unrelated changes.
4. **Before pushing**, run the project's verification command; push only when it passes, or say plainly that it fails.
5. **Pull request** with `gh pr create`: what changed, why, and the verification command's real output.
6. Never force-push a shared branch, rewrite published history, or skip hooks (`--no-verify`).

## Ask first

- `git push`, `gh pr create`, `gh pr merge`, deleting a branch, and any force push: ask the user before each one,
  unless they already said to do that specific thing.
