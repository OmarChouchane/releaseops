## What and why

<!-- One or two sentences: what changes, and the reason. -->

## How it was checked

- [ ] `./run.sh validate` (lint, fmt, helm, terraform validate)
- [ ] `./run.sh test` (if application code changed)
- [ ] `./run.sh up` and `./run.sh verify` (if deploy, chart or infra changed)

## Risk and rollback

<!-- What could break, and how to undo it (usually `git revert` of this PR). -->

## Notes for reviewers

- [ ] No secrets, state files or generated reports are committed
- [ ] Docs or ADR updated when behaviour or a decision changed
