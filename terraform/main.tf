terraform {
  required_version = ">= 1.6"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

locals {
  cluster_name = "gitops"
  host_port    = 8088 # host port the app is opened on: http://localhost:8088
  repo_url     = "https://github.com/stavgerti/devops-gitops-exercise.git"
}

provider "kind" {}

# helm provider v3: "kubernetes" is an attribute (=), not a block.
provider "helm" {
  kubernetes = {
    config_path = kind_cluster.this.kubeconfig_path
  }
}

resource "kind_cluster" "this" {
  name = local.cluster_name
  # Kubernetes v1.36.4 node image, pinned by digest so every apply runs the exact same image.
  node_image      = "kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
  kubeconfig_path = "${path.module}/${local.cluster_name}-kubeconfig"
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Host 127.0.0.1:8088 -> this node's port 30080 = Traefik's NodePort. kube-proxy serves a NodePort on
      # every node, so mapping only the control-plane is enough wherever the Traefik pod runs.
      extra_port_mappings {
        container_port = 30080
        host_port      = local.host_port
        listen_address = "127.0.0.1"
      }
    }

    node {
      role = "worker"
    }

    node {
      role = "worker"
    }
  }
}

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "42.2.0"
  namespace        = "traefik"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    # Chart v42 sets the Service type under service.spec (default LoadBalancer, which kind cannot provide).
    service = { spec = { type = "NodePort" } }
    ports   = { web = { nodePort = 30080 } }
    providers = {
      kubernetesIngress = {
        # Argo CD marks an Ingress Healthy only once it has an address; a NodePort Service has none,
        # so publish a fixed hostname instead of copying the Service's address.
        publishedService = { enabled = false }
        ingressEndpoint  = { hostname = "localhost" }
      }
    }
  })]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.11.6"
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    # Dex (SSO) and notifications are unused here; disabling them saves memory in the 4 GB Docker VM.
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs = {
      # Check git every 60s (+ up to 60s jitter) instead of the default 120s, so CI deploys roll out sooner.
      cm = { "timeout.reconciliation" = "60s" }
    }
  })]
}

# Bootstrap: the one Argo CD Application, which syncs k8s/ from this repo into namespace "web".
# A separate release (after argocd) because the Application CRD comes from the argo-cd chart and must
# exist before an Application can be created.
resource "helm_release" "app" {
  name       = "gitops-app"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.7"
  namespace  = "argocd"
  depends_on = [helm_release.argocd]

  values = [yamlencode({
    applications = {
      web = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = local.repo_url
          targetRevision = "main"
          path           = "k8s"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "web"
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}

output "app_url" {
  value = "http://localhost:${local.host_port}"
}
