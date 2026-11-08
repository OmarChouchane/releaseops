terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
    random     = { source = "hashicorp/random" }
  }
}

variable "namespace" { type = string }
variable "chart_version" { type = string }
variable "grafana_node_port" { type = number }
variable "prometheus_node_port" { type = number }

# No default admin/prom-operator credentials: a random password, kept in a Secret + TF state.
resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = var.namespace
    labels    = { "app.kubernetes.io/managed-by" = "terraform" }
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana.result
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = var.namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version

  atomic          = true
  wait            = true
  timeout         = 900
  cleanup_on_fail = true

  values = [yamlencode({
    # Sized for a laptop: no Alertmanager, no node-exporter, no scraping of control-plane
    # components that kind does not expose. Alerts are evaluated by Prometheus and visible in its UI
    # and in Grafana; add Alertmanager when there is a receiver to notify.
    alertmanager               = { enabled = false }
    nodeExporter               = { enabled = false }
    "prometheus-node-exporter" = { enabled = false }
    kubeEtcd                   = { enabled = false }
    kubeScheduler              = { enabled = false }
    kubeControllerManager      = { enabled = false }
    kubeProxy                  = { enabled = false }
    defaultRules = {
      rules = {
        alertmanager          = false
        etcd                  = false
        kubeScheduler         = false
        kubeControllerManager = false
        kubeProxy             = false
        # node-exporter is off, so its rules would only ever be "no data".
        nodeExporterAlerting  = false
        nodeExporterRecording = false
        node                  = false
      }
    }

    prometheusOperator = {
      # The admission webhook needs a certificate-patching Job; skipping it removes two moving
      # parts at the cost of server-side validation of PrometheusRule objects.
      admissionWebhooks = { enabled = false }
      tls               = { enabled = false }
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }

    "kube-state-metrics" = {
      resources = {
        requests = { cpu = "25m", memory = "48Mi" }
        limits   = { memory = "128Mi" }
      }
    }

    prometheus = {
      service = {
        type     = "NodePort"
        nodePort = var.prometheus_node_port
      }
      prometheusSpec = {
        # Select PodMonitors/ServiceMonitors/Rules from ALL namespaces, not only those labelled
        # with this Helm release - the application chart ships its own.
        podMonitorSelectorNilUsesHelmValues     = false
        serviceMonitorSelectorNilUsesHelmValues = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false
        scrapeConfigSelectorNilUsesHelmValues   = false
        scrapeInterval                          = "15s"
        evaluationInterval                      = "15s"
        retention                               = "12h" # demo cluster: no persistent volume
        resources = {
          requests = { cpu = "200m", memory = "512Mi" }
          limits   = { memory = "1Gi" }
        }
      }
    }

    grafana = {
      admin = {
        existingSecret = kubernetes_secret_v1.grafana_admin.metadata[0].name
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }
      service = {
        type     = "NodePort"
        nodePort = var.grafana_node_port
      }
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "384Mi" }
      }
      sidecar = {
        dashboards = {
          searchNamespace  = "ALL" # pick up the dashboard ConfigMap shipped by the app chart
          folderAnnotation = "grafana_folder"
          provider         = { foldersFromFilesStructure = true }
        }
      }
    }
  })]
}

output "grafana_admin_user" {
  value = "admin"
}

output "grafana_admin_password" {
  value     = random_password.grafana.result
  sensitive = true
}
