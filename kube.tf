resource "ovh_cloud_project_kube" "cluster" {
  service_name = var.service_name
  name         = var.cluster_name
  region       = var.region
  # version omitted on purpose: MKS picks the current default Kubernetes version

  private_network_id = tolist(ovh_cloud_project_network_private.network.regions_attributes[*].openstackid)[0]
  nodes_subnet_id    = ovh_cloud_project_network_private_subnet.subnet.id

  private_network_configuration {
    # Empty gateway IP + routing as default = nodes take the subnet DHCP's
    # advertised gateway (the OVH Gateway) as their default route: all egress
    # exits through the gateway's public IP. Pod-to-pod stays on the private network.
    default_vrack_gateway              = ""
    private_network_routing_as_default = true
  }

  depends_on = [ovh_cloud_project_gateway.gateway]
}

resource "ovh_cloud_project_kube_nodepool" "pool" {
  service_name  = var.service_name
  kube_id       = ovh_cloud_project_kube.cluster.id
  name          = "${var.cluster_name}-pool" # no underscores allowed
  flavor_name   = var.flavor_name
  desired_nodes = var.node_count
  min_nodes     = var.node_count
  max_nodes     = var.node_count
  autoscale     = false
}
