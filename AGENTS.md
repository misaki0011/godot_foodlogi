# AGENTS.md

## Project Overview

This is a godot project.
Follow these instructions when editting this repository.

## Testing & Validation

verify that Godot scene files (`.tscn`, `.tres`) are syntactically correct and load without parsing errors, run the editor headlessly with the `--editor --quit` flags:

```bash
  /mnt/c/Users/harat_local/Desktop/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64.exe --headless --editor --quit
```

### GitHub Pull Request

If this repository uses GitHub, use the GitHub CLI if available:

```bash
git push -u origin agent/<short-task-slug>
gh pr create \
  --base main \
  --head agent/<short-task-slug> \
  --title "<PR title>" \
  --body "<PR description>"
```

If `gh` is not installed or not authenticated, push the branch and explain how to create the PR manually.

### If Checks Fail

If a check fails:

1. Read the error carefully.
2. Fix the issue if it is related to the current task.
3. Re-run the failing check.
4. Do not open a PR/MR with failing checks unless the user explicitly asks.

If the failure appears unrelated to the current changes, explain that clearly in the PR/MR description.

### Main Branch Protection Assumption

Assume `main` is protected.

The expected workflow is:

```txt
feature branch
→ commit changes
→ push branch
→ open PR/MR into main
→ human review and CI
→ merge by maintainer
```

The agent must not merge its own PR/MR unless explicitly instructed.

## Git and File Safety

* Keep changes focused on the user’s request.
* Do not rewrite unrelated files.
* Ask before adding new production dependencies.
* Never commit secrets, tokens, `.env` files, or private credentials.
* Never rewrite `main` history.
* Never force-push without explicit approval.
* If unsure whether a change is safe, explain the concern before continuing.

## Response Style

When finishing a task, respond with:

1. What changed
2. Files modified
3. Checks run and results
4. PR/MR link, if created
5. Any known issues or follow-up work

Be direct and practical. Avoid unnecessary explanations.

Do not claim that checks passed unless they were actually run and passed.
Do not claim that a PR/MR was created unless it was actually created.

## Feature Implementation

All planned features are defined in `FEATURES.md`.

`FEATURES.md` is extracted from `SPEC.md`, which is the source specification document. Use both documents when implementing features. When a spec is changed, maintain both documents.
