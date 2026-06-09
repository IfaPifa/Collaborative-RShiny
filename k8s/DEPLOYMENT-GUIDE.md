# ShinySwarm — Rancher Deployment Guide

## Server Requirements

- **CPU**: 8 vCPU
- **RAM**: 16 GB
- **Disk**: 80 GB SSD
- **OS**: Ubuntu 22.04 LTS
- **Provider**: Hetzner Cloud (CPX41 ~€15/mo) or any VPS with the above specs

## 1. Initial Server Setup

SSH into your server:

```bash
ssh root@<server-ip>
```

Update and install prerequisites:

```bash
apt update && apt upgrade -y
apt install -y curl open-iscsi nfs-common
```

## 2. Install K3s (Lightweight Kubernetes)

K3s is a single-binary Kubernetes distribution. Rancher runs on top of it.

```bash
curl -sfL https://get.k3s.io | sh -
```

Verify it's running:

```bash
kubectl get nodes
# Should show one node in Ready state
```

Set up kubeconfig for non-root use:

```bash
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
```

## 3. Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## 4. Install Rancher UI

Add the Rancher Helm repo:

```bash
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
```

Install cert-manager (required for Rancher's TLS):

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
```

Install Rancher:

```bash
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.<server-ip>.sslip.io \
  --set bootstrapPassword=shinyswarm \
  --set replicas=1
```

Wait for Rancher to be ready:

```bash
kubectl -n cattle-system rollout status deploy/rancher
```

Access Rancher UI at: `https://rancher.<server-ip>.sslip.io`
- Username: `admin`
- Password: `shinyswarm` (you'll be prompted to change it)

## 5. Install k6 (on your local machine)

k6 runs from your laptop against the server. Install it locally:

```bash
# macOS
brew install k6

# Ubuntu/Debian
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D68
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt update && sudo apt install k6

# Windows
choco install k6
```

## 6. Deploy the Logging Stack

Deploy Loki + Promtail + Grafana (keep running across all benchmarks):

```bash
kubectl apply -f k8s/logging-stack.yaml
```

Access Grafana at: `http://<server-ip>:30300`
- Username: `admin`
- Password: `shinyswarm`
- Loki data source is pre-configured

## 7. Clone the Repo on the Server

```bash
git clone https://github.com/IfaPifa/Collaborative-RShiny.git
cd Collaborative-RShiny
```

## 8. Run Benchmarks (One Architecture at a Time)

### Architecture 1: REST API

```bash
# Deploy
./k8s/deploy-rest.sh

# Wait for all pods to be ready (~2-3 minutes)
kubectl get pods -w

# Run k6 from your LOCAL machine
./k6/run-all.sh http://<server-ip>:30001 rest

# Tear down before next architecture
./k8s/teardown.sh
```

### Architecture 2: Kafka

```bash
./k8s/deploy-kafka.sh
kubectl get pods -w

# Run k6 from your LOCAL machine
./k6/run-all.sh http://<server-ip>:30001 kafka

./k8s/teardown.sh
```

### Architecture 3: Monolithic

```bash
./k8s/deploy-monolithic.sh
kubectl get pods -w

# Monolithic has no Spring Boot API — none of the k6 tests apply.
# Use Playwright tests or manual testing instead.

./k8s/teardown.sh
```

## 9. Collect Results

k6 results are saved to `k6/results/<arch>/`:

```
k6/results/
├── kafka/
│   ├── 01-state-relay-latency.json
│   ├── 01-state-relay-latency-summary.json
│   ├── 02-collaboration-latency-summary.json
│   ├── 03-save-restore-latency-summary.json
│   ├── 04-throughput-summary.json
│   ├── 05-data-loss-summary.json
│   ├── 06-cross-contamination-summary.json
│   └── 07-session-lifecycle-summary.json
├── rest/
│   └── ... (same structure)
```

Grafana dashboards (screenshots for thesis):
1. Open `http://<server-ip>:30300`
2. Go to Explore → select Loki
3. Query: `{app="spring-backend"}` to see backend logs
4. Query: `{app=~"shiny-.*"}` to see all Shiny logs
5. Filter by time range matching your k6 run

## 10. Firewall Rules

If using Hetzner or another cloud provider, open these ports:

| Port | Service |
|------|---------|
| 22 | SSH |
| 443 | Rancher UI (HTTPS) |
| 30001 | Angular Frontend |
| 30080-30087 | Shiny Apps (via nginx) |
| 30300 | Grafana |

```bash
# Example with ufw
ufw allow 22,443,30001,30300/tcp
ufw allow 30080:30087/tcp
ufw enable
```

## Troubleshooting

**Pods stuck in ImagePullBackOff:**
The GHCR images are public after the first CI build on main. If they're
private, create a pull secret:
```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<github-user> \
  --docker-password=<github-pat>
```
Then add `imagePullSecrets: [{ name: ghcr-secret }]` to each deployment spec.

**Pods crash-looping:**
```bash
kubectl logs <pod-name> --tail=50
```

**Kafka not ready:**
Kafka needs Zookeeper first. If Kafka pods restart, wait — they'll
stabilize after Zookeeper is healthy (~30s).

**K3s uses ports 80/443:**
K3s Traefik ingress binds to 80/443 by default. If you need those ports
for something else:
```bash
# Disable Traefik
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
```
