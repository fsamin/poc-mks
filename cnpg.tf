# CloudNativePG: the PostgreSQL operator backing the git-deploy `postgresql`
# add-on (the git-deploy operator creates a CNPG Cluster per add-on and reads
# its Ready condition; CNPG owns the StatefulSet, PVCs and connection secret).
resource "helm_release" "cnpg" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = "0.29.0" # operator 1.30.0
  namespace        = "cnpg-system"
  create_namespace = true
  wait             = true

  # Chart defaults are fine: single replica, CRDs installed by the chart.

  depends_on = [ovh_cloud_project_kube_nodepool.pool]
}
