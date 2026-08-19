# Keycloak: OIDC identity provider AND authorization source of the git-deploy
# platform (who is admin, who belongs to which tenant — as realm role and
# groups). PoC sizing on purpose: one replica, dev-mode H2 database persisted
# on a PVC, realm imported from a versioned template at startup
# (--import-realm never overwrites an existing realm, so console changes
# survive pod restarts as long as the PVC lives).

resource "kubernetes_namespace" "keycloak" {
  metadata {
    name = "keycloak"
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

resource "random_password" "keycloak_admin" {
  length  = 24
  special = false
}

resource "random_password" "oauth2_proxy_client_secret" {
  length  = 32
  special = false
}

resource "random_password" "operator_client_secret" {
  length  = 32
  special = false
}

# The rendered realm carries the confidential client secrets: a Secret, not a
# ConfigMap. The template itself (templates/keycloak-realm.json.tpl) is
# versioned with placeholders only.
resource "kubernetes_secret" "keycloak_realm" {
  metadata {
    name      = "keycloak-realm-import"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
  }

  data = {
    "git-deploy-realm.json" = templatefile("${path.module}/templates/keycloak-realm.json.tpl", {
      gitdeploy_host             = local.gitdeploy_host
      oauth2_proxy_client_secret = random_password.oauth2_proxy_client_secret.result
      operator_client_secret     = random_password.operator_client_secret.result
    })
  }
}

resource "kubernetes_secret" "keycloak_admin" {
  metadata {
    name      = "keycloak-admin-bootstrap"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
  }

  data = {
    KC_BOOTSTRAP_ADMIN_USERNAME = "admin"
    KC_BOOTSTRAP_ADMIN_PASSWORD = random_password.keycloak_admin.result
  }
}

resource "kubernetes_persistent_volume_claim" "keycloak_data" {
  metadata {
    name      = "keycloak-data"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    # Default storage class (cinder CSI on MKS).
  }

  # The claim binds only when the pod schedules (WaitForFirstConsumer).
  wait_until_bound = false
}

resource "kubernetes_deployment" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
    labels    = { app = "keycloak" }
  }

  spec {
    replicas = 1

    # RWO volume: never two pods at once.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "keycloak" }
    }

    template {
      metadata {
        labels = { app = "keycloak" }
      }

      spec {
        # The image runs as UID 1000 (keycloak); a fresh cinder volume is
        # root-owned. fsGroup makes kubelet chown the mount, or H2 cannot
        # create /opt/keycloak/data/h2.
        security_context {
          fs_group = 1000
        }

        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:26.3"
          args  = ["start-dev", "--import-realm"]

          env_from {
            secret_ref {
              name = kubernetes_secret.keycloak_admin.metadata[0].name
            }
          }

          env {
            # Public URL: tokens must carry it as issuer.
            name  = "KC_HOSTNAME"
            value = "https://${local.keycloak_host}"
          }
          env {
            # TLS terminates at ingress-nginx; trust its X-Forwarded-* headers.
            name  = "KC_PROXY_HEADERS"
            value = "xforwarded"
          }
          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }
          env {
            # Health endpoints live on the management port (9000).
            name  = "KC_HEALTH_ENABLED"
            value = "true"
          }

          port {
            container_port = 8080
            name           = "http"
          }

          volume_mount {
            name       = "data"
            mount_path = "/opt/keycloak/data"
          }
          volume_mount {
            name       = "realm-import"
            mount_path = "/opt/keycloak/data/import"
            read_only  = true
          }

          readiness_probe {
            http_get {
              path = "/health/ready"
              port = 9000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 12
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              memory = "1536Mi"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.keycloak_data.metadata[0].name
          }
        }
        volume {
          name = "realm-import"
          secret {
            secret_name = kubernetes_secret.keycloak_realm.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

resource "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
  }

  spec {
    selector = { app = "keycloak" }
    port {
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      # No IP allowlist: end users must reach the login pages.
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [local.keycloak_host]
      secret_name = "keycloak-tls"
    }

    rule {
      host = local.keycloak_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.keycloak.metadata[0].name
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
  # the record and the issuer.
  depends_on = [helm_release.cluster_issuer, ovh_domain_zone_record.apps_wildcard]
}
