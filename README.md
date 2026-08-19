# poc-mks — OVHcloud Managed Kubernetes PoC with Terraform

Provision, in a **single `terraform apply`**, an OVHcloud MKS cluster wired to a
private network with a single egress gateway, an ingress controller, TLS
certificates from Let's Encrypt, and a demo application proving the whole chain
works end to end.

## What gets created (14 resources)

| Layer | Resources |
|---|---|
| Network | Private network (vRack), subnet `192.168.168.0/24` (DHCP), OVH Gateway (model `s`) |
| Kubernetes | MKS cluster (region `GRA5`, default k8s version), node pool of 3 × `b3-8` |
| Ingress | `ingress-nginx` (Helm) exposed through an Octavia Public Cloud Load Balancer |
| TLS | `cert-manager` (Helm) + Let's Encrypt production `ClusterIssuer` (HTTP-01) |
| DNS | `A` records `helloworld[.<subzone>].<zone>`, `dashboard[.<subzone>].<zone>` and wildcard `*[.<subzone>].<zone>` → Load Balancer IP, in an existing OVH DNS zone (`var.dns_subzone`, default `poc`, prefixes the records — OVH zones cannot be subzones) |
| Demo | `helloworld` app (3 replicas of `nginxdemos/hello:plain-text`) served in HTTPS |
| Admin | **Headlamp** dashboard (bearer-token auth, cluster-admin SA token) behind an **IP-allowlisted** ingress |

### Network topology

```
                     internet
                    ▲        ▲
          (ingress) │        │ (egress: single public IP)
                    │        │
   Octavia LB (floating IP)  OVH Gateway "s"
                    │        │
        ┌───────────┴────────┴───────────┐
        │  private network 192.168.168.0/24  (vRack)
        │   node1 ── node2 ── node3      │
        │     └── pod-to-pod stays here ──┘
        └────────────────────────────────┘
```

- **All node/pod outbound traffic exits through the gateway's public IP**
  (`private_network_routing_as_default = true`: the subnet DHCP advertises the
  gateway as default route).
- **Pod-to-pod / node-to-node traffic stays on the private network** and never
  transits the gateway.
- Inbound traffic reaches pods only through the Load Balancer → ingress-nginx.

## Layout

```
versions.tf                  # providers: ovh ~>2.1, helm ~>3.0, kubernetes ~>2.35
variables.tf                 # region, flavor, node count, subnet, dns zone, acme email
network.tf                   # private network + subnet + gateway
kube.tf                      # MKS cluster + fixed 3-node pool
ingress.tf                   # ingress-nginx helm release (PROXY protocol v2) + LB service data source
certmanager.tf               # cert-manager + ClusterIssuer (local chart)
charts/cluster-issuer/       # mini local Helm chart carrying the ClusterIssuer
dns.tf                       # A records in the existing OVH DNS zone
helloworld.tf                # namespace / deployment / service / ingress (TLS)
headlamp.tf                  # admin dashboard: Headlamp + admin token + allowlisted ingress
outputs.tf                   # kubeconfig, LB IP, gateway egress IP, app URL
```

## Prerequisites

- Terraform >= 1.5.
- An OVHcloud Public Cloud project with the target region enabled
  (`GRA5` by default — check yours with `GET /cloud/project/{id}/region`,
  the apply fails with `Invalid region` otherwise).
- An existing DNS zone in the same OVH account.
- An OVH API token (https://www.ovh.com/auth/api/createToken) with:

  ```
  GET     /me
  GET/POST/PUT/DELETE  /cloud/*
  GET/POST/PUT/DELETE  /domain/zone/*
  ```

  (`GET /me` is required by the provider at init; without it you get
  `403 This call has not been granted`.)

- A local `ovh-credentials.env` file (gitignored, **never commit it**):

  ```bash
  OVH_ENDPOINT=ovh-eu
  OVH_APPLICATION_KEY=...
  OVH_APPLICATION_SECRET=...
  OVH_CONSUMER_KEY=...
  TF_VAR_service_name=...   # Public Cloud project ID
  TF_VAR_dns_zone=...       # e.g. example.com (exact lowercase name matters)
  TF_VAR_acme_email=...     # Let's Encrypt account email
  ```

## Usage

```bash
set -a; source ./ovh-credentials.env; set +a
terraform init
terraform apply
```

Single apply, ~15–20 min total (cluster ~4 min, node pool ~4 min, Load
Balancer ~4 min, certificate ~1–2 min after the DNS record lands).

Then:

```bash
terraform output -raw kubeconfig > kubeconfig.yaml && chmod 600 kubeconfig.yaml
export KUBECONFIG=$PWD/kubeconfig.yaml

terraform output helloworld_url      # https://helloworld.<zone>/
terraform output ingress_lb_ip       # Load Balancer public IP
terraform output gateway_egress_ip   # single egress IP of the cluster
terraform output dashboard_url       # https://dashboard.<zone>/ (IP-allowlisted)
terraform output -raw dashboard_token  # bearer token for the Headlamp login screen
```

## Verifying the PoC

```bash
# 3 nodes Ready, internal IPs in 192.168.168.0/24 (private network attachment)
kubectl get nodes -o wide

# Certificate issued by Let's Encrypt production
kubectl get certificate -n helloworld

# End to end: valid TLS, 200, responses spread across the 3 replicas
curl https://helloworld.<zone>/

# Single egress IP: every pod sees the gateway IP as its public address
kubectl run egress-test --image=curlimages/curl --restart=Never --attach --rm -q \
  -- -s https://api.ipify.org   # == terraform output gateway_egress_ip

# Pod-to-pod stays direct on the private network
kubectl get pods -n helloworld -o wide      # take a pod IP
kubectl run p2p-test --image=curlimages/curl --restart=Never --attach --rm -q \
  -- -s http://<pod-ip>/
```

## Exposing an app in any namespace

A wildcard record `*[.<subzone>].<zone>` points to the Load Balancer IP, so
`<app>.<namespace>[.<subzone>].<zone>` resolves for **any** namespace without
touching Terraform (a DNS wildcard synthesizes names of any depth, RFC 4592).
Deploy a Service, then an Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello
  namespace: demo
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  rules:
    - host: hello.demo.poc.<zone>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hello
                port:
                  number: 80
  tls:
    - hosts: [hello.demo.poc.<zone>]
      secretName: hello-tls
```

cert-manager issues one certificate per host (HTTP-01) as soon as the Ingress
appears — allow ~1 min. `terraform output apps_url_pattern` recalls the URL
scheme.

Caveats:

- Namespaces named like an existing record label (`helloworld`, `dashboard`)
  do **not** resolve under the wildcard: an explicit DNS node blocks wildcard
  synthesis below itself.
- The wildcard is open by design: anyone with cluster access can expose a
  host under it. Exposure is gated by cluster access, not by DNS.
- Let's Encrypt production rate limits apply (one cert per host, 50
  certificates per registered domain per week).
- A per-ingress `whitelist-source-range` does not break HTTP-01: cert-manager
  creates a separate solver Ingress for `/.well-known/acme-challenge/` that
  does not carry the annotation (nginx applies allowlists per-location). Never
  set `acme.cert-manager.io/http01-edit-in-place: "true"` on an allowlisted
  Ingress and never make the allowlist controller-global — Let's Encrypt does
  not publish its validator IPs, so they cannot be allowlisted.

## Admin dashboard (Headlamp)

- Reachable at `https://dashboard.<zone>/` **only from the CIDRs in
  `var.dashboard_allowed_cidrs`** (nginx `whitelist-source-range`, HTTP 403
  otherwise). The allowlist is per-ingress: `helloworld.<zone>` stays public.
- Login: bearer token — `terraform output -raw dashboard_token` (long-lived
  cluster-admin ServiceAccount token; rotate with
  `terraform apply -replace=kubernetes_secret.headlamp_admin_token`).
- Client-IP ACLs only work because the Octavia LB speaks **PROXY protocol v2**
  to ingress-nginx (`loadbalancer.openstack.org/proxy-protocol: "v2"` +
  `externalTrafficPolicy: Local` + nginx `use-proxy-protocol`). Never add an
  allowlist annotation without this plumbing: nginx would only ever see
  amphora IPs from the private subnet.
- Headlamp is the dashboard officially recommended by the Kubernetes project
  since kubernetes-dashboard was retired (archived January 2026).

## Design notes & gotchas

- **ID asymmetry (main foot-gun of the ovh provider):** the subnet's
  `network_id` takes the **OVH ID** (`.id`) while the gateway's `network_id`
  and the cluster's `private_network_id` take the **OpenStack UUID**
  (`regions_attributes[*].openstackid`); `nodes_subnet_id` and the gateway's
  `subnet_id` take the subnet `.id`.
- **ClusterIssuer via a local Helm chart**, not `kubernetes_manifest`: that
  resource fetches the CRD schema from the cluster **at plan time**, which
  breaks a greenfield single apply (cluster and CRD don't exist yet). Helm
  applies the manifest at apply time — official providers only, one apply.
- **The gateway is load-bearing twice**: it is the single egress route for the
  nodes, and it is mandatory for the Octavia LB to get its floating IP (OVH
  silently creates an unmanaged one otherwise).
- **OVH keeps a small egress exception list on the nodes** (observed on the
  nodes via `ip rule`): a policy-routing table sends a few pinned destinations
  out the node's own public interface instead of the gateway — `1.1.1.1`,
  `8.8.8.8`, `169.254.169.254` (metadata), `213.186.33.99` (OVH DNS), a few OVH
  control-plane IPs, and fwmark'd system traffic (kubelet ↔ control plane).
  Everything else follows the gateway. Don't test the egress topology against
  `1.1.1.1`/`8.8.8.8` — you'll be measuring the exception, not the rule.
- All egress shares the gateway bandwidth (model `s`); bump `model` to
  `m`/`l` if it becomes a bottleneck.
- **Never change `private_network_id` on a live cluster**: OVH resets the
  cluster (all workloads deleted).
- If an apply fails with a helm/kubernetes provider connection error after the
  cluster was tainted or recreated (their config is derived from cluster
  attributes): `terraform apply -target=ovh_cloud_project_kube_nodepool.pool`
  first, then a full apply.
- Billing: 3 × `b3-8` instances + 1 gateway `s` + 1 Octavia LB `s` + 2 public
  floating IPs (LB + gateway).

## Teardown

```bash
set -a; source ./ovh-credentials.env; set +a
terraform destroy
```
