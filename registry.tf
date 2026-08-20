# In-cluster OCI registry for the images the git-deploy platform builds: the
# MKS equivalent of the local PoC's kind-registry. buildkit Jobs push each
# tenant commit here, the AppRelease controller reads the image config from
# here, kubelets pull from here.
#
# Access model (PoC-grade, deliberate):
# - anonymous push/pull, gated by an IP allowlist on the Ingress: the gateway
#   egress IP (every node and pod exits through it — kubelet pulls and
#   buildkit pushes included) plus the admin CIDRs. Real client IPs exist
#   thanks to the PROXY protocol plumbing on the LB (see ingress.tf).
# - known limit, documented in the README: tenant pods share that egress IP,
#   so a malicious tenant workload could push/overwrite images.
# - plain HTTP is served on port 80 WITHOUT the https redirect: the operator's
#   registry clients are wired for an http registry (`name.Insecure` for the
#   EXPOSE inspection, `registry.insecure=true` for buildctl). HTTPS stays
#   available on 443 for humans and docker CLIs.

resource "kubernetes_namespace" "registry" {
  metadata {
    name = "registry"
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

resource "kubernetes_persistent_volume_claim" "registry_data" {
  metadata {
    name      = "registry-data"
    namespace = kubernetes_namespace.registry.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
    # Default storage class (cinder CSI on MKS).
  }

  # The claim binds only when the pod schedules (WaitForFirstConsumer).
  wait_until_bound = false
}

resource "kubernetes_deployment" "registry" {
  metadata {
    name      = "registry"
    namespace = kubernetes_namespace.registry.metadata[0].name
    labels    = { app = "registry" }
  }

  spec {
    replicas = 1

    # RWO volume: never two pods at once.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "registry" }
    }

    template {
      metadata {
        labels = { app = "registry" }
      }

      spec {
        container {
          name  = "registry"
          image = "registry:2.8.3"

          env {
            # Allows DELETE of manifests, so a garbage collection pass is
            # possible when the PVC fills up.
            name  = "REGISTRY_STORAGE_DELETE_ENABLED"
            value = "true"
          }

          port {
            container_port = 5000
            name           = "http"
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/registry"
          }

          readiness_probe {
            http_get {
              path = "/v2/"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.registry_data.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

resource "kubernetes_service" "registry" {
  metadata {
    name      = "registry"
    namespace = kubernetes_namespace.registry.metadata[0].name
  }

  spec {
    selector = { app = "registry" }
    port {
      port        = 80
      target_port = 5000
    }
  }
}

resource "kubernetes_ingress_v1" "registry" {
  metadata {
    name      = "registry"
    namespace = kubernetes_namespace.registry.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      # The access control: cluster egress IP (nodes + pods) and admins only.
      "nginx.ingress.kubernetes.io/whitelist-source-range" = join(",", concat(
        ["${ovh_cloud_project_gateway.gateway.external_information[0].ips[0].ip}/32"],
        var.dashboard_allowed_cidrs,
      ))
      # The operator's clients speak plain http (see the header comment):
      # serve port 80 as-is instead of 308-redirecting to https.
      "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
      # Image layers: no body-size cap, stream uploads instead of buffering
      # them to nginx disk, and keep slow pushes alive.
      "nginx.ingress.kubernetes.io/proxy-body-size"         = "0"
      "nginx.ingress.kubernetes.io/proxy-request-buffering" = "off"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"      = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"      = "3600"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [local.registry_host]
      secret_name = "registry-tls"
    }

    rule {
      host = local.registry_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.registry.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  # The hostname resolves through the apps wildcard record; HTTP-01 needs both
  # the record and the issuer. The allowlist does not break the challenge:
  # cert-manager's solver Ingress overrides it (see charts/cluster-issuer).
  depends_on = [helm_release.cluster_issuer, ovh_domain_zone_record.apps_wildcard]
}
