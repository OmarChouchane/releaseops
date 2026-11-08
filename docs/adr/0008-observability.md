# ADR-0008: Observability stack and what it measures

**Status:** accepted

## Decisions
* **kube-prometheus-stack** (Prometheus Operator, Prometheus, Grafana, kube-state-metrics) installed by Terraform.
  Off for a laptop: Alertmanager, node-exporter, control-plane scrape targets kind does not expose, the admission
  webhook. Alerts are evaluated by Prometheus and visible in its UI and Grafana; add Alertmanager when there is a
  receiver to notify.
* The **application chart ships its own monitoring objects** (`PodMonitor`, `PrometheusRule`, dashboard ConfigMap)
  so the app is observable wherever the chart is deployed; `monitoring.enabled=false` for clusters without the CRDs.
  Prometheus is configured to select them from all namespaces.
* **Actuator is on its own port (8081)**, scraped through a `PodMonitor`, and is **not** in the Service: only the
  kubelet and Prometheus reach it. Exposure is limited to `health,info,prometheus`; `env`, `beans`, `heapdump`,
  `threaddump`, `configprops` return 404 (asserted by a test).
* **Database health** = the `app_database_up` gauge (a connection validated within 1s, evaluated on every scrape)
  plus Hikari pool metrics plus MySQL pod readiness from kube-state-metrics.

## What the dashboard shows (all queries are real PromQL; nothing is hard-coded)
Ready/desired replicas, scrape targets up, DB up, restarts, firing alerts, pod readiness over time, request rate
by status, 5xx ratio, p50/p95/p99 latency, JVM heap/GC/threads, Hikari connections, CPU and memory per pod.
`./run.sh verify` fails if Prometheus does not see every replica.

## Alerts (`PrometheusRule`)
`ReleaseOpsNoAvailableReplicas`, `ReleaseOpsRolloutStuck` (Deployment `Progressing=False`), `ReleaseOpsPodRestarting`,
`ReleaseOpsDatabaseDown`, `ReleaseOps5xxRatioHigh`, `ReleaseOpsTargetDown`.

## Limits
Retention is 12 h and storage is ephemeral (demo cluster). No tracing, no log aggregation.
