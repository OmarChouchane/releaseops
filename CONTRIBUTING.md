# Contributing

## Workflow

1. Branch from `main` (`feature/<topic>` or `fix/<topic>`).
2. Make a small, focused change. One logical change per commit.
3. Run the checks below, then open a pull request using the template.
4. A code owner reviews; merge when checks pass. Roll back with `git revert`.

## Commit messages

Short imperative subject (about 50 characters), blank line, then why the change is needed.
Example: `Raise the Grafana memory limit to 768Mi`.

## Checks before a pull request

```bash
./run.sh validate     # shell syntax, helm lint, terraform fmt/validate
./run.sh test         # unit + Testcontainers tests (needs Docker)
./run.sh up           # full local deployment, ends with 12 verification checks
```

Optional but recommended: `pre-commit install` (see [.pre-commit-config.yaml](.pre-commit-config.yaml)).

## Conventions

- Comments explain why, in one line. Prefer clear names over comments.
- Shell: `set -uo pipefail`, quote variables, pass `shellcheck`.
- Terraform: `terraform fmt`, pinned provider versions, a lock file per environment.
- Helm: keep defaults environment-neutral; environment values live in `deploy/environments/`.
- Image digests are written by the release process, never by hand.
- Decisions that change the architecture get an ADR in [docs/adr/](docs/adr/).

## Layout

See the repository layout in the [README](README.md#repository-layout) and the
[documentation index](docs/README.md).
