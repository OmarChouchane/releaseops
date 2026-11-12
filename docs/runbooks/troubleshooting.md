# Troubleshooting

Symptoms and fixes seen while running the stack.

| Symptom | Cause / fix |
|---|---|
| `cannot talk to the Docker daemon` | Start Docker Desktop and enable *WSL integration* for your distro (the `docker` command may exist on the Windows PATH but not work in WSL). |
| `bind: Only one usage of each socket address` while creating the cluster | Docker Desktop + WSL2 clash on kind's random API port. The scripts pin the API port (`API_PORT=16443`); change it if that port is taken. |
| `host port … already in use` | Override: `APP_PORT=28080 ARGOCD_PORT=28081 GRAFANA_PORT=23000 PROMETHEUS_PORT=29090 ./run.sh up` |
| Tests fail with `I/O error … ClosedChannelException` | JDK HttpClient + IPv6 loopback on some WSL2 setups. The POM already sets `-Djava.net.preferIPv4Stack=true` for tests. |
| `pods … violates PodSecurity "restricted"` | A manifest lost its security context; the namespace policy is doing its job. |
| `./run.sh up` is slow the first time | Image pulls (kind node, Argo CD, Prometheus, Grafana, MySQL, Trivy DB ≈ 2–3 GB). Re-runs reuse everything. |
| Argo CD shows `ComparisonError` right after setup | The git mirror was just seeded; `argocd.argoproj.io/refresh=hard` is applied automatically, or wait ≤ 30 s. |
| `docker pull ghcr.io/aquasecurity/trivy` is denied | The scanner is pulled from Docker Hub (`aquasec/trivy`, same digest as on public.ecr.aws). |
| `Permission denied: ./run.sh` after cloning | The scripts were created on Windows without the executable bit. Fix once, then commit it: `git add --chmod=+x run.sh scripts/*/*.sh deploy/git-mirror/entrypoint.sh && git commit -m "scripts: executable"` (or locally: `chmod +x run.sh scripts/*/*.sh deploy/git-mirror/entrypoint.sh`). |
| Reset a broken state | `./run.sh cleanup --yes && ./run.sh up` |
