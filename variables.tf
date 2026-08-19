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

locals {
  helloworld_host = "${var.helloworld_subdomain}.${var.dns_zone}"
}
