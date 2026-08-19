resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  set = [{
    name  = "crds.enabled"
    value = "true"
  }]

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}

# ClusterIssuer applied through a local chart: keeps official providers only
# and a single greenfield apply (kubernetes_manifest would need the CRD at plan time).
resource "helm_release" "cluster_issuer" {
  name      = "cluster-issuer"
  chart     = "${path.module}/charts/cluster-issuer"
  namespace = "cert-manager"

  set = [{
    name  = "acmeEmail"
    value = var.acme_email
  }]

  depends_on = [helm_release.cert_manager, helm_release.ingress_nginx]
}
