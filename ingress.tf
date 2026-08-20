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
        # Controller-wide allowlist: every Ingress, present and future (tenant
        # apps included), is admin-only unless it carries its own
        # whitelist-source-range annotation (the ACME solver does, to let
        # Let's Encrypt validate challenges — see charts/cluster-issuer).
        # The gateway egress IP must be here: in-cluster components (oauth2-
        # proxy, the operator) reach Keycloak through its public URL and their
        # traffic exits through the gateway. Accepted limit, same as the
        # registry's: tenant pods share that IP.
        "whitelist-source-range" = join(",", concat(
          ["${ovh_cloud_project_gateway.gateway.external_information[0].ips[0].ip}/32"],
          var.dashboard_allowed_cidrs,
        ))
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
