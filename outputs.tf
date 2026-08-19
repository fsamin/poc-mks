output "kubeconfig" {
  value     = ovh_cloud_project_kube.cluster.kubeconfig
  sensitive = true
}

output "cluster_url" {
  value = ovh_cloud_project_kube.cluster.url
}

output "ingress_lb_ip" {
  description = "Public IP of the ingress-nginx LoadBalancer (Octavia floating IP)"
  value       = try(data.kubernetes_service.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].ip, null)
}

output "helloworld_url" {
  description = "HTTPS URL of the helloworld app"
  value       = "https://${local.helloworld_host}/"
}

output "gateway_egress_ip" {
  description = "Public IP of the gateway — the single egress IP for all node/pod outbound traffic"
  value       = try(ovh_cloud_project_gateway.gateway.external_information[0].ips[0].ip, null)
}

output "dashboard_url" {
  description = "HTTPS URL of the admin dashboard (IP-allowlisted)"
  value       = "https://${local.dashboard_host}/"
}

output "apps_url_pattern" {
  description = "URL pattern for apps exposed via the wildcard DNS record"
  value       = "https://<app>.<namespace>${local.dns_suffix}.${var.dns_zone}/"
}

output "dashboard_token" {
  description = "Long-lived cluster-admin bearer token for Headlamp login"
  value       = kubernetes_secret.headlamp_admin_token.data["token"]
  sensitive   = true
}

output "keycloak_url" {
  description = "HTTPS URL of Keycloak (admin console at /admin; realm git-deploy)"
  value       = "https://${local.keycloak_host}/"
}

output "keycloak_admin_password" {
  description = "Bootstrap password of the Keycloak 'admin' console user"
  value       = random_password.keycloak_admin.result
  sensitive   = true
}

output "gitdeploy_url" {
  description = "HTTPS URL of the git-deploy API/UI (OIDC-authenticated via oauth2-proxy)"
  value       = "https://${local.gitdeploy_host}/"
}

output "registry_host" {
  description = "OCI registry for platform-built images (IP-allowlisted; use as REGISTRY= on make deploy)"
  value       = local.registry_host
}
