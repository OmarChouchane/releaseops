# ADR-0005: GitOps source, release flow and the in-cluster git mirror

**Status:** accepted

## The flow

```
code change ──► CI: test ► build ► Trivy ► SBOM ► push to GHCR (digest) ► attest provenance
                                                        │
                                  release PR pins  image@sha256:…  in deploy/environments/local/values.yaml
                                                        │   (a human reviews and merges = the deploy decision)
                                                        ▼
                    Argo CD (polls Git) ► renders deploy/helm/releaseops + that values file ► syncs the cluster
                                                        │
                                        ./run.sh verify  (separate from Argo's own "Healthy")
```

* **Desired state lives in Git**: chart in `deploy/helm/releaseops`, environment in `deploy/environments/<env>/values.yaml`.
* **Immutable references**: images are referenced as `repo@sha256:…`; the chart refuses to render with neither a
  digest nor an explicit tag.
* **Least privilege**: CI uses the built-in `GITHUB_TOKEN` with per-job permissions (the release job gets
  `contents: write` + `pull-requests: write`, nothing else). No personal access token, no deploy key. Argo CD only
  needs *read* access (none for a public repo). Trade-off: PRs opened with `GITHUB_TOKEN` do not trigger further
  workflows; the release PR only changes a pin to an already-scanned image, so this is accepted.
* **Rollback = `git revert`** of the release commit/PR. Argo CD does **not** roll back a failed release by itself:
  it faithfully applies what Git says, including a broken release. Detection is the job of release verification
  (ADR-0007); recovery is a Git operation.

## Where does Argo CD read from?
Two modes, same code path:

| | `GITOPS_MODE=local` (default) | `GITOPS_MODE=remote` |
|---|---|---|
| Argo CD reads | a small **git server inside the kind cluster**, seeded from your working tree | `GITOPS_REPO_URL` (your public GitHub repo) |
| Needs | nothing – works before the repo is published | repo URL (+ read-only token if private) |
| Release commits | `./run.sh deploy` commits the local-registry digest to the mirror | CI's release PR |
| Demo commits (bad release / revert) | to the mirror – **no network, no credentials, nothing pushed to anyone's GitHub** | to `GITOPS_BRANCH` of your repo; requires `DEMO_ALLOW_PUSH=1` and should use a dedicated branch |

### Why a local git server at all?
The brief says to avoid one unless there is a compelling reason. The reason: the failure demo must make *real
commits* and *real reverts* that Argo CD reads back, repeatedly, on a machine where the repository **has not been
published yet** and where a reviewer has **no push rights**. Pushing demo noise to a public `main` is wrong, and
`file://` repositories are not readable by the Argo CD repo-server. The mirror is ~50 lines (nginx + `git
http-backend`), unauthenticated, ClusterIP-only (the host reaches it through `kubectl port-forward`), and is
**not** part of the "production" story – it is there only for the local demo. `remote` mode has no git server.

**Status of `remote` mode:** implemented, but only the *local* mode was executed end-to-end by the author
(no repository was published). See README → *Known limitations*.
