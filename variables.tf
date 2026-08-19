variable "service_name" {
  description = "OVHcloud Public Cloud project ID"
  type        = string
}

variable "region" {
  description = "MKS / network region"
  type        = string
  default     = "GRA5" # only Gravelines compute region enabled on this project
}

variable "cluster_name" {
  type    = string
  default = "poc-mks"
}

variable "flavor_name" {
  type    = string
  default = "b3-8"
}

variable "node_count" {
  type    = number
  default = 3
}

variable "vlan_id" {
  description = "vRack VLAN ID for the private network"
  type        = number
  default     = 42
}

variable "subnet_cidr" {
  type    = string
  default = "192.168.168.0/24"
}

variable "subnet_start" {
  type    = string
  default = "192.168.168.100"
}

variable "subnet_end" {
  type    = string
  default = "192.168.168.200"
}

variable "dns_zone" {
  description = "Existing OVH DNS zone (e.g. example.com)"
  type        = string
}

variable "helloworld_subdomain" {
  description = "Subdomain for the helloworld app in the DNS zone"
  type        = string
  default     = "helloworld"
}

variable "acme_email" {
  description = "Email used for the Let's Encrypt ACME account"
  type        = string
}

variable "dashboard_subdomain" {
  description = "Subdomain for the admin dashboard in the DNS zone"
  type        = string
  default     = "dashboard"
}

variable "dns_subzone" {
  description = "Optional intermediate label under the OVH zone (e.g. \"poc\" gives helloworld.poc.<zone>). Empty for none. Note: OVH zones cannot be subzones, so this stays a record prefix."
  type        = string
  default     = "poc"
}

variable "dashboard_allowed_cidrs" {
  description = "Client CIDRs allowed to reach the dashboard ingress (admin allowlist)"
  type        = list(string)
  default = [
    "109.190.254.34/32", "93.182.196.20/32", "109.190.254.5/32", "192.168.0.0/24",
    "213.186.33.64/32", "109.190.130.253/32", "91.134.217.6/32", "51.210.35.64/32",
    "109.190.254.33/32", "79.137.104.241/32", "51.161.75.217/32", "109.190.254.58/32",
    "109.190.254.57/32", "5.196.197.1/32", "5.39.111.3/32", "109.190.254.61/32",
    "109.190.254.36/32", "5.39.16.33/32", "51.77.185.156/32", "213.251.182.3/32",
  ]

  validation {
    condition     = length(var.dashboard_allowed_cidrs) > 0 && !contains(var.dashboard_allowed_cidrs, "0.0.0.0/0")
    error_message = "The allowlist must not be empty and must not contain 0.0.0.0/0 (it would disable the ACL)."
  }
}

locals {
  dns_suffix              = var.dns_subzone == "" ? "" : ".${var.dns_subzone}"
  apps_wildcard_subdomain = "*${local.dns_suffix}"
  helloworld_subdomain    = "${var.helloworld_subdomain}${local.dns_suffix}"
  dashboard_subdomain     = "${var.dashboard_subdomain}${local.dns_suffix}"
  helloworld_host         = "${local.helloworld_subdomain}.${var.dns_zone}"
  dashboard_host          = "${local.dashboard_subdomain}.${var.dns_zone}"
}
