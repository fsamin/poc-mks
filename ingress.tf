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
        # Required so client source IPs reach nginx (whitelist-source-range ACLs)
        externalTrafficPolicy = "Local"
        annotations = {
          "loadbalancer.ovhcloud.com/class"                  = "octavia" # Public Cloud Load Balancer
          "loadbalancer.openstack.org/proxy-protocol"        = "v2"
          "loadbalancer.openstack.org/enable-health-monitor" = "true"
        }
      }
      config = {
        "use-proxy-protocol" = "true"
        "real-ip-header"     = "proxy_protocol"
        "proxy-real-ip-cidr" = var.subnet_cidr # vRack: trusted range = private subnet
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
