# Public entry point of the git-deploy platform: oauth2-proxy in front of the
# operator's HTTP API/UI. The proxy handles ONLY the browser session (login
# redirect to Keycloak, cookie) and forwards the OIDC token as an
# Authorization: Bearer header; CLI requests already carrying a valid bearer
# JWT pass through untouched (--skip-jwt-bearer-tokens). The operator verifies
# the JWT itself on every request either way — the proxy is a convenience for
# browsers, never the security boundary. This Ingress is the ONLY one exposing
# the API: the operator is deployed with OVERLAY=config/no-api-ingress so no
# proxy-free door exists.

resource "kubernetes_namespace" "git_deploy_gateway" {
  metadata {
    name = "git-deploy-gateway"
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

# 32 ASCII characters = the 32-byte cookie secret oauth2-proxy expects.
resource "random_password" "oauth2_proxy_cookie_secret" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "oauth2_proxy" {
  metadata {
    name      = "oauth2-proxy"
    namespace = kubernetes_namespace.git_deploy_gateway.metadata[0].name
  }

  data = {
    OAUTH2_PROXY_CLIENT_SECRET = random_password.oauth2_proxy_client_secret.result
    OAUTH2_PROXY_COOKIE_SECRET = random_password.oauth2_proxy_cookie_secret.result
  }
}

resource "kubernetes_deployment" "oauth2_proxy" {
  metadata {
    name      = "oauth2-proxy"
    namespace = kubernetes_namespace.git_deploy_gateway.metadata[0].name
    labels    = { app = "oauth2-proxy" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "oauth2-proxy" }
    }

    template {
      metadata {
        labels = { app = "oauth2-proxy" }
      }

      spec {
        container {
          name  = "oauth2-proxy"
          image = "quay.io/oauth2-proxy/oauth2-proxy:v7.8.1"

          args = [
            "--http-address=0.0.0.0:4180",
            "--provider=keycloak-oidc",
            "--oidc-issuer-url=https://${local.keycloak_host}/realms/git-deploy",
            "--client-id=oauth2-proxy",
            "--redirect-url=https://${local.gitdeploy_host}/oauth2/callback",
            "--code-challenge-method=S256",
            "--email-domain=*",
            # The single upstream: the operator's API/UI ClusterIP service
            # (kustomize namePrefix applied to config/api/service.yaml).
            "--upstream=http://git-deploy-operator-api.git-deploy-operator-system.svc.cluster.local",
            # CLI requests: a valid bearer JWT (audience git-deploy-cli) passes
            # without a session.
            "--skip-jwt-bearer-tokens=true",
            "--oidc-extra-audience=git-deploy-cli",
            # Browser sessions: forward the OIDC token as Authorization: Bearer
            # so the operator sees one auth shape for every caller.
            "--pass-authorization-header=true",
            # Keycloak access tokens live 5 minutes: refresh the session before
            # the forwarded token expires, or the operator would answer 401 to
            # a browser whose cookie is still valid.
            "--cookie-refresh=4m",
            "--cookie-secure=true",
            # What a client needs before it has a token, plus the probe path.
            "--skip-auth-route=GET=^/healthz$",
            "--skip-auth-route=GET=^/v1/auth/config$",
          ]

          env_from {
            secret_ref {
              name = kubernetes_secret.oauth2_proxy.metadata[0].name
            }
          }

          port {
            container_port = 4180
            name           = "http"
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 4180
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            # OIDC discovery against Keycloak happens at startup: stay patient
            # while Keycloak itself is still coming up.
            failure_threshold = 30
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

resource "kubernetes_service" "oauth2_proxy" {
  metadata {
    name      = "oauth2-proxy"
    namespace = kubernetes_namespace.git_deploy_gateway.metadata[0].name
  }

  spec {
    selector = { app = "oauth2-proxy" }
    port {
      port        = 80
      target_port = 4180
    }
  }
}

resource "kubernetes_ingress_v1" "git_deploy" {
  metadata {
    name      = "git-deploy"
    namespace = kubernetes_namespace.git_deploy_gateway.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      # `git-deploy logs --follow` streams are unbounded: keep nginx from
      # cutting them after its default 60s timeouts (same as the dashboard).
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
      # No IP allowlist: OIDC is the access control.
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [local.gitdeploy_host]
      secret_name = "git-deploy-tls"
    }

    rule {
      host = local.gitdeploy_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.oauth2_proxy.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.cluster_issuer, ovh_domain_zone_record.apps_wildcard]
}

# What `make deploy` does not carry: the manager's Keycloak admin credentials,
# consumed as an optional envFrom Secret named keycloak-admin. The namespace is
# created here so the Secret can exist before the first `make deploy`; kustomize
# applying the same Namespace object afterwards is a no-op.
resource "kubernetes_namespace" "git_deploy_operator_system" {
  metadata {
    name = "git-deploy-operator-system"
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

resource "kubernetes_secret" "keycloak_admin_client" {
  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace.git_deploy_operator_system.metadata[0].name
  }

  data = {
    KEYCLOAK_CLIENT_ID     = "git-deploy-operator"
    KEYCLOAK_CLIENT_SECRET = random_password.operator_client_secret.result
  }
}
