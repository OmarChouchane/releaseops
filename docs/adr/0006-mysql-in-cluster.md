# ADR-0006: MySQL as a StatefulSet inside the chart

**Status:** accepted for the local/demo environment; not recommended for production

## Decision
The challenge asks for the app plus its database on Kubernetes. The chart includes a **single-replica MySQL 8.4
StatefulSet** with a PersistentVolumeClaim, a ClusterIP Service (never exposed outside the cluster) and a
NetworkPolicy that admits only the application pods on 3306.

* Credentials come from a Secret created by Terraform (`secret.existingSecret`); the app connects as a dedicated
  `app` user (owner of `challenge` only), **not** root. Root's password is used by probes inside the pod only.
* Hardened: non-root (999), read-only root filesystem, all capabilities dropped, seccomp `RuntimeDefault`,
  no service-account token. Verified to run under the `restricted` Pod Security level.
* `--performance-schema=OFF --mysqlx=OFF` (laptop memory) is a local default in `values.yaml`.

## Why not the Bitnami chart / an operator?
Fewer moving parts and pinned, reviewable manifests for a one-replica demo database. An operator (or Bitnami charts,
whose free image catalogue changed in 2025) adds more surface than this exercise warrants.

## Production guidance
Use a managed database (RDS/Aurora, Cloud SQL): set `mysql.enabled=false` and `config.database.host`. A one-replica
StatefulSet has no HA, backups, point-in-time recovery or minor-version upgrade story.

## Safety property used by the demo
Data lives on a PVC created by `volumeClaimTemplates`; Argo CD's prune does not own it, and a Git revert does not
touch it. The demo proves it (canary record + unchanged MySQL pod UID).
