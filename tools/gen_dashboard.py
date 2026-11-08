import json, sys

DS = {"type": "prometheus", "uid": "prometheus"}
NS = '$namespace'
APP = f'namespace="{NS}",container="app"'
HTTP = f'namespace="{NS}",uri!~"/actuator.*"'
_id = [0]


def nid():
    _id[0] += 1
    return _id[0]


def target(expr, legend="", ref="A"):
    return {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": ref}


def stat(title, expr, x, y, w=4, unit="none", thresholds=None, mappings=None, desc=""):
    steps = thresholds or [{"color": "green", "value": None}]
    return {
        "id": nid(), "type": "stat", "title": title, "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": 4},
        "targets": [target(expr)],
        "fieldConfig": {"defaults": {"unit": unit, "thresholds": {"mode": "absolute", "steps": steps},
                                     "mappings": mappings or []}, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "background", "graphMode": "none", "textMode": "auto"},
    }


def ts(title, targets, x, y, w=12, h=8, unit="none", desc=""):
    return {
        "id": nid(), "type": "timeseries", "title": title, "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [target(e, l, chr(65 + i)) for i, (e, l) in enumerate(targets)],
        "fieldConfig": {"defaults": {"unit": unit, "custom": {"lineWidth": 1, "fillOpacity": 8}}, "overrides": []},
        "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    }


def row(title, y):
    return {"id": nid(), "type": "row", "title": title, "collapsed": False,
            "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []}


updown = [{"type": "value", "options": {"0": {"text": "DOWN", "color": "red"}, "1": {"text": "UP", "color": "green"}}}]
red_if_zero = [{"color": "red", "value": None}, {"color": "green", "value": 1}]
red_if_pos = [{"color": "green", "value": None}, {"color": "red", "value": 1}]

panels = [
    row("Availability and release health", 0),
    stat("Ready replicas", f'kube_deployment_status_replicas_available{{namespace="{NS}",deployment="releaseops"}}', 0, 1, thresholds=red_if_zero,
         desc="Pods that passed the readiness probe (which includes MySQL)."),
    stat("Desired replicas", f'kube_deployment_spec_replicas{{namespace="{NS}",deployment="releaseops"}}', 4, 1),
    stat("Metric targets up", f'sum(up{{{APP}}})', 8, 1, thresholds=red_if_zero),
    stat("Database (as seen by the app)", f'min(app_database_up{{namespace="{NS}"}})', 12, 1, thresholds=red_if_zero, mappings=updown,
         desc="app_database_up: a pooled connection validated within 1s."),
    stat("Container restarts (1h)", f'sum(increase(kube_pod_container_status_restarts_total{{namespace="{NS}"}}[1h]))', 16, 1, thresholds=red_if_pos),
    stat("Firing alerts", f'count(ALERTS{{namespace="{NS}",alertstate="firing"}}) or vector(0)', 20, 1, thresholds=red_if_pos),
    ts("Pod readiness", [(f'kube_pod_status_ready{{namespace="{NS}",condition="true"}}', "{{pod}}")], 0, 5, 12, 7,
       desc="1 = Ready. During a bad release you see the new pod stay at 0 while old pods stay at 1."),
    ts("Deployment replicas", [
        (f'kube_deployment_status_replicas_available{{namespace="{NS}",deployment="releaseops"}}', "available"),
        (f'kube_deployment_status_replicas_unavailable{{namespace="{NS}",deployment="releaseops"}}', "unavailable"),
        (f'kube_deployment_status_replicas_updated{{namespace="{NS}",deployment="releaseops"}}', "updated")], 12, 5, 12, 7),

    row("HTTP traffic (API port, actuator excluded)", 12),
    ts("Request rate by status", [(f'sum by (status) (rate(http_server_requests_seconds_count{{{HTTP}}}[2m]))', "{{status}}")], 0, 13, 8, 8, "reqps"),
    ts("5xx ratio", [(f'sum(rate(http_server_requests_seconds_count{{{HTTP},status=~"5.."}}[2m])) / clamp_min(sum(rate(http_server_requests_seconds_count{{{HTTP}}}[2m])), 1e-9)', "5xx ratio")], 8, 13, 8, 8, "percentunit"),
    ts("Latency p50 / p95 / p99", [
        (f'histogram_quantile(0.50, sum by (le) (rate(http_server_requests_seconds_bucket{{{HTTP}}}[5m])))', "p50"),
        (f'histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{{{HTTP}}}[5m])))', "p95"),
        (f'histogram_quantile(0.99, sum by (le) (rate(http_server_requests_seconds_bucket{{{HTTP}}}[5m])))', "p99")], 16, 13, 8, 8, "s"),

    row("JVM", 21),
    ts("Heap used vs max", [
        (f'sum by (pod) (jvm_memory_used_bytes{{{APP},area="heap"}})', "used {{pod}}"),
        (f'sum by (pod) (jvm_memory_max_bytes{{{APP},area="heap"}})', "max {{pod}}")], 0, 22, 8, 8, "bytes"),
    ts("GC pause time (rate)", [(f'sum by (pod) (rate(jvm_gc_pause_seconds_sum{{{APP}}}[5m]))', "{{pod}}")], 8, 22, 8, 8, "s"),
    ts("Live threads", [(f'jvm_threads_live_threads{{{APP}}}', "{{pod}}")], 16, 22, 8, 8),

    row("Database connections (HikariCP) and resources", 30),
    ts("Hikari connections", [
        (f'hikaricp_connections_active{{{APP}}}', "active {{pod}}"),
        (f'hikaricp_connections_pending{{{APP}}}', "pending {{pod}}"),
        (f'hikaricp_connections_max{{{APP}}}', "max {{pod}}")], 0, 31, 8, 8),
    ts("CPU usage (cores)", [(f'sum by (pod) (rate(container_cpu_usage_seconds_total{{namespace="{NS}",container!="",container!="POD"}}[2m]))', "{{pod}}")], 8, 31, 8, 8, "short"),
    ts("Memory working set", [
        (f'sum by (pod) (container_memory_working_set_bytes{{namespace="{NS}",container!="",container!="POD"}})', "{{pod}}")], 16, 31, 8, 8, "bytes"),
]

dash = {
    "uid": "releaseops-overview", "title": "ReleaseOps - application and release health",
    "tags": ["releaseops", "spring-boot", "kubernetes"], "timezone": "browser", "schemaVersion": 39, "version": 1,
    "refresh": "10s", "time": {"from": "now-30m", "to": "now"},
    "templating": {"list": [{
        "name": "namespace", "type": "query", "label": "Namespace", "datasource": DS, "refresh": 2,
        "query": {"query": "label_values(kube_deployment_spec_replicas{deployment=\"releaseops\"}, namespace)", "refId": "q"},
        "current": {"text": "releaseops", "value": "releaseops"}, "includeAll": False, "multi": False}]},
    "annotations": {"list": []},
    "panels": panels,
}
json.dump(dash, open(sys.argv[1], "w", newline="\n"), indent=2)
print("panels:", len(panels))
