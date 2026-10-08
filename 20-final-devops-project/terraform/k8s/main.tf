# Cluster bootstrap for the LOCAL Minikube cluster, as code: the namespaces IncidentDesk and its
# tooling live in, plus guard-rails (ResourceQuota + LimitRange) on the app namespace.
#
# This is a separate root module from ../ on purpose: ../ talks to the (emulated) cloud API,
# this one talks to a Kubernetes API, and the two have different lifecycles and credentials.
#
#   terraform init && terraform apply           # uses ~/.kube/config, context "minikube"

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }
}

variable "kube_context" {
  description = "kubeconfig context to manage"
  type        = string
  default     = "minikube"
}

variable "app_namespace" {
  type    = string
  default = "incidentdesk"
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

locals {
  namespaces = {
    (var.app_namespace) = { purpose = "application", psa = "baseline" }
    monitoring          = { purpose = "prometheus-grafana", psa = "privileged" } # node-exporter needs host access
    argocd              = { purpose = "gitops", psa = "baseline" }
  }
}

resource "kubernetes_namespace_v1" "ns" {
  for_each = local.namespaces
  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "purpose"                            = each.value.purpose
      "pod-security.kubernetes.io/enforce" = each.value.psa
    }
  }
}

# A ceiling on what the app namespace may request in total — on a 2-node laptop cluster this
# is what stops one runaway HPA or a misconfigured replica count from starving everything else.
resource "kubernetes_resource_quota_v1" "app" {
  metadata {
    name      = "incidentdesk-quota"
    namespace = kubernetes_namespace_v1.ns[var.app_namespace].metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"           = "1500m"
      "requests.memory"        = "1536Mi"
      "limits.memory"          = "3Gi"
      "pods"                   = "20"
      "persistentvolumeclaims" = "4"
    }
  }
}

# Defaults for any container that forgets to declare resources (a quota with requests.* makes
# such pods un-admittable otherwise), plus a per-container maximum.
resource "kubernetes_limit_range_v1" "app" {
  metadata {
    name      = "incidentdesk-defaults"
    namespace = kubernetes_namespace_v1.ns[var.app_namespace].metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default_request = {
        cpu    = "50m"
        memory = "64Mi"
      }
      # Stated explicitly: when max.cpu is set and default.cpu is not, the API server copies
      # max into default — which made every second `terraform plan` try to remove it.
      default = {
        cpu    = "1"
        memory = "256Mi"
      }
      max = {
        cpu    = "1"
        memory = "1Gi"
      }
    }
  }
}

output "namespaces" {
  value = [for ns in kubernetes_namespace_v1.ns : ns.metadata[0].name]
}
