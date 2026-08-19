resource "ovh_cloud_project_network_private" "network" {
  service_name = var.service_name
  name         = "${var.cluster_name}-network"
  vlan_id      = var.vlan_id
  regions      = [var.region]
}

resource "ovh_cloud_project_network_private_subnet" "subnet" {
  service_name = var.service_name
  network_id   = ovh_cloud_project_network_private.network.id # OVH ID, not openstackid
  region       = var.region
  start        = var.subnet_start
  end          = var.subnet_end
  network      = var.subnet_cidr
  dhcp         = true  # required: MKS nodes get their IP via DHCP
  no_gateway   = false # a gateway IP must exist for the OVH Gateway
}

# Single egress point for all node/pod outbound traffic (advertised as default
# route by the subnet DHCP), also required so the Octavia LoadBalancer created
# by ingress-nginx can get a public floating IP.
resource "ovh_cloud_project_gateway" "gateway" {
  service_name = var.service_name
  name         = "${var.cluster_name}-gateway"
  model        = "s"
  region       = var.region
  network_id   = tolist(ovh_cloud_project_network_private.network.regions_attributes[*].openstackid)[0]
  subnet_id    = ovh_cloud_project_network_private_subnet.subnet.id
}
