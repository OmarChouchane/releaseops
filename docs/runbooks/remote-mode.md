# Using your own GitHub repository (`remote` mode)

The default `local` mode needs no repository. Remote mode makes Argo CD track a published repository.

The default `local` mode needs no repository. To make Argo CD track your published repository instead:

```bash
git remote set-url origin https://github.com/<you>/<repo>.git   # this checkout still points at the upstream challenge repo
git push -u origin main
# Settings > Actions > General > "Allow GitHub Actions to create and approve pull requests"
GITOPS_MODE=remote GITOPS_REPO_URL=https://github.com/<you>/<repo>.git ./run.sh up
```
* **Public repo:** nothing else — Argo CD reads anonymously.
* **Private repo:** a read-only token, passed as environment (never written to a file; it is stored in Terraform state, which is a secret):
  `GITOPS_REPO_USERNAME=<user> GITOPS_REPO_TOKEN=<read-only token> ./run.sh setup`.
* After `up`, the app waits for a pinned image: push to `main` → CI builds/scans/publishes to `ghcr.io/<you-lowercase>/releaseops-app` and opens a release PR → **merge it** → Argo CD deploys → `./run.sh verify`.
  Make the GHCR package public (or add an image pull secret) so the kind node can pull it.
* `./run.sh demo` in remote mode pushes the bad commit and its revert to `GITOPS_BRANCH`; it refuses unless you set `DEMO_ALLOW_PUSH=1` — use a throw-away branch (`GITOPS_BRANCH=demo`).

> **Not yet executed:** remote mode itself (Argo CD deploying from GitHub). The GitHub Actions `ci` workflow has run and is green. See [Known limitations](../limitations.md).
