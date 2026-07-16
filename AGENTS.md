# AGENTS.md

## Project Overview

This is a Godot project.

Follow these instructions when editing this repository. Run all commands from the repository root.

## Godot Environment

This project uses Godot 4.6.2.

The installation script must install:

* The Godot 4.6.2 editor binary.
* The matching Godot 4.6.2 export templates.
* A `godot` executable at `$HOME/.local/bin/godot`.

Use the following command in all checks:

```bash
GODOT="${GODOT:-$HOME/.local/bin/godot}"
```

## Installation

Install the required download tools before running the Godot installation script:

```bash
sudo apt-get update
sudo apt-get install -y curl unzip
```

Install Godot:

```bash
chmod +x scripts/install-godot.sh
./scripts/install-godot.sh
```

Verify the installed version:

```bash
GODOT="${GODOT:-$HOME/.local/bin/godot}"
"$GODOT" --version
```

The reported version must start with:

```text
4.6.2
```

Import the project resources:

```bash
GODOT="${GODOT:-$HOME/.local/bin/godot}"
"$GODOT" --headless --path . --import
```

## Test

Launch the main project headlessly for 600 frames:

```bash
GODOT="${GODOT:-$HOME/.local/bin/godot}"

"$GODOT" \
  --headless \
  --path . \
  --verbose \
  --quit-after 600 \
  --log-file godot-smoke-test.log
```

The command must complete successfully.

Check the log for known runtime and script errors:

```bash
if grep -nE \
  "SCRIPT ERROR|ERROR:|CRASH|Invalid call|Invalid access|Null instance|Previously freed" \
  godot-smoke-test.log
then
  echo "Godot errors were found in godot-smoke-test.log"
  exit 1
else
  echo "No known Godot error patterns were found."
fi
```

Do not treat the smoke test as complete without reading both:

* The command output.
* `godot-smoke-test.log`.

## Build

Export the release Web build used by GitHub Pages:

```bash
GODOT="${GODOT:-$HOME/.local/bin/godot}"

rm -rf build/web
mkdir -p build/web

"$GODOT" \
  --headless \
  --path . \
  --export-release "Web" \
  build/web/index.html
```

The project must contain an export preset named exactly `Web` in `export_presets.cfg`.

The matching Godot export templates must also be installed.

Verify the build output:

```bash
test -f build/web/index.html
```

## Required Checks

Before opening a PR or MR, run:

```bash
GODOT="${GODOT:-$HOME/.local/bin/godot}"

"$GODOT" --headless --path . --import

"$GODOT" \
  --headless \
  --path . \
  --verbose \
  --quit-after 600 \
  --log-file godot-smoke-test.log

if grep -nE \
  "SCRIPT ERROR|ERROR:|CRASH|Invalid call|Invalid access|Null instance|Previously freed" \
  godot-smoke-test.log
then
  exit 1
fi

rm -rf build/web
mkdir -p build/web

"$GODOT" \
  --headless \
  --path . \
  --export-release "Web" \
  build/web/index.html

test -f build/web/index.html
```

## If Checks Fail

If a check fails:

1. Read the command output and relevant log files carefully.
2. Fix the issue when it is related to the current task.
3. Re-run the failing check.
4. Do not open a PR or MR with failing checks unless the user explicitly requests it.
5. If a failure is unrelated to the current changes, clearly describe it in the PR or MR description.

Do not claim that the task is complete unless the project was imported, launched, and successfully exported.

## Git Workflow

Agents must complete the Git workflow autonomously without asking for routine
confirmation at each step:

1. Before editing, create or switch to a focused branch named
   `agent/<short-task-slug>`. Never make task commits directly on `main`.
2. Preserve any existing user changes. Stage only files related to the current
   task and never include unrelated modifications in the commit.
3. Run the required build and test commands.
4. Create a concise commit describing the completed change.
5. Push the branch with upstream tracking.
6. Open a pull request into `main` and report its URL.

Use non-interactive commands. A typical publish sequence is:

```bash
git switch -c agent/<short-task-slug>
git add <task-files>
git commit -m "<concise change summary>"
git push -u origin agent/<short-task-slug>
gh pr create \
  --base main \
  --head agent/<short-task-slug> \
  --title "<PR title>" \
  --body "<PR description>"
```

If the task is already on an appropriate feature branch, continue using it
instead of creating another branch. Do not amend or rewrite commits that were
not created for the current task.

If authentication, permissions, or unavailable tooling blocks a push or pull
request, keep the local commit intact, report the exact failure, and provide the
single command needed after the blocker is resolved.

### Web Preview Rule

Every pushed branch deploys to the shared GitHub Pages URL. Before merging a
feature into `main`:

1. Push the feature branch's latest commit.
2. Wait for **Build web game** and **Deploy to GitHub Pages** to pass.
3. Verify the game at `https://misaki0011.github.io/godot_foodlogi/`.
4. Merge only after the browser check succeeds.

The most recently pushed branch owns the shared preview URL. A push to `main`
after merging restores the URL to the merged version.

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
