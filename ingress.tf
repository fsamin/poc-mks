resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true # waits until the LoadBalancer gets its external IP
  timeout          = 900

  values = [yamlencode({
    controller = {
      service = {
        type = "LoadBalancer"
        annotations = {
          "loadbalancer.ovhcloud.com/class" = "octavia" # Public Cloud Load Balancer
        }
      }
    }
  })]

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

data "kubernetes_service" "ingress_nginx_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [helm_release.ingress_nginx]
}
