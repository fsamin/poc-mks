resource "kubernetes_namespace" "helloworld" {
  metadata {
    name = "helloworld"
  }

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

resource "kubernetes_deployment" "helloworld" {
  metadata {
    name      = "helloworld"
    namespace = kubernetes_namespace.helloworld.metadata[0].name
    labels    = { app = "helloworld" }
  }

  spec {
    replicas = 3

    selector {
      match_labels = { app = "helloworld" }
    }

    template {
      metadata {
        labels = { app = "helloworld" }
      }

      spec {
        container {
          name  = "helloworld"
          image = "nginxdemos/hello:plain-text"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "helloworld" {
  metadata {
    name      = "helloworld"
    namespace = kubernetes_namespace.helloworld.metadata[0].name
  }

  spec {
    selector = { app = "helloworld" }

    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_ingress_v1" "helloworld" {
  metadata {
    name      = "helloworld"
    namespace = kubernetes_namespace.helloworld.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [local.helloworld_host]
      secret_name = "helloworld-tls"
    }

    rule {
      host = local.helloworld_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.helloworld.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  # DNS record must exist so the HTTP-01 challenge can be validated
  depends_on = [helm_release.cluster_issuer, ovh_domain_zone_record.helloworld]
}
