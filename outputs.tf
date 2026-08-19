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

output "dashboard_token" {
  description = "Long-lived cluster-admin bearer token for Headlamp login"
  value       = kubernetes_secret.headlamp_admin_token.data["token"]
  sensitive   = true
}
