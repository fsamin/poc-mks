resource "kubernetes_namespace" "headlamp" {
  metadata {
    name = "headlamp"
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

resource "helm_release" "headlamp" {
  name       = "headlamp"
  repository = "https://kubernetes-sigs.github.io/headlamp/"
  chart      = "headlamp"
  version    = "0.44.0"
  namespace  = kubernetes_namespace.headlamp.metadata[0].name
  wait       = true

  # Chart defaults are already correct for this setup:
  # ingress.enabled=false, service ClusterIP :80 (plain HTTP), config.baseURL="" (root),
  # per-user bearer-token auth (config.unsafeUseServiceAccountToken=false).
}

resource "kubernetes_service_account" "headlamp_admin" {
  metadata {
    name      = "headlamp-admin"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "headlamp_admin" {
  metadata {
    # "-user" suffix: the chart itself owns a ClusterRoleBinding named
    # "headlamp-admin" for its backend pod — identical names collide at install.
    name = "headlamp-admin-user"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.headlamp_admin.metadata[0].name
    namespace = kubernetes_namespace.headlamp.metadata[0].name
  }
}

# Long-lived login token: the token controller fills .data["token"]; the
# provider waits for it (wait_for_service_account_token defaults to true).
resource "kubernetes_secret" "headlamp_admin_token" {
  metadata {
    name      = "headlamp-admin-token"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.headlamp_admin.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_ingress_v1" "headlamp" {
  metadata {
    name      = "headlamp"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      # Real client IPs available thanks to PROXY protocol on the Octavia LB
      "nginx.ingress.kubernetes.io/whitelist-source-range" = join(",", var.dashboard_allowed_cidrs)
      # Headlamp streams over websockets: nginx supports them natively, only the
      # 60s proxy timeouts need raising (ingress-nginx docs recommend > 3600).
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [local.dashboard_host]
      secret_name = "headlamp-tls"
    }

    rule {
      host = local.dashboard_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = helm_release.headlamp.name # fullname == release name == "headlamp"
              port {
                number = 80 # plain HTTP — no backend-protocol annotation needed
              }
            }
          }
        }
      }
    }
  }

  # DNS record must exist so the HTTP-01 challenge can be validated
  depends_on = [helm_release.cluster_issuer, ovh_domain_zone_record.dashboard]
}
