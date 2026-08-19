# A record in the existing OVH DNS zone, pointing to the ingress LoadBalancer IP.
resource "ovh_domain_zone_record" "helloworld" {
  zone      = var.dns_zone
  subdomain = local.helloworld_subdomain
  fieldtype = "A"
  ttl       = 60
  target    = data.kubernetes_service.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].ip
}

resource "ovh_domain_zone_record" "dashboard" {
  zone      = var.dns_zone
  subdomain = local.dashboard_subdomain
  fieldtype = "A"
  ttl       = 60
  target    = data.kubernetes_service.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].ip
}

# Wildcard so any app in any namespace resolves as <app>.<namespace>.poc.<zone>
# (RFC 4592: the wildcard synthesizes names of any depth, except below the
# explicit records above).
resource "ovh_domain_zone_record" "apps_wildcard" {
  zone      = var.dns_zone
  subdomain = local.apps_wildcard_subdomain
  fieldtype = "A"
  ttl       = 60
  target    = data.kubernetes_service.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].ip
}
