# A record in the existing OVH DNS zone, pointing to the ingress LoadBalancer IP.
resource "ovh_domain_zone_record" "helloworld" {
  zone      = var.dns_zone
  subdomain = var.helloworld_subdomain
  fieldtype = "A"
  ttl       = 60
  target    = data.kubernetes_service.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].ip
}
