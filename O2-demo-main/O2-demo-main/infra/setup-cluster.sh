#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="o2-benchmark"

echo "============================================"
echo "  OpenObserve vs OpenSearch Benchmark Setup"
echo "============================================"

# ── Pre-flight checks ──────────────────────────
for cmd in docker kind kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed. Please install it first."
    exit 1
  fi
done

# ── Delete existing cluster if present ──────────
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "[*] Deleting existing KIND cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "$CLUSTER_NAME"
fi

# ── Create KIND cluster ────────────────────────
echo "[*] Creating KIND cluster '${CLUSTER_NAME}'..."
mkdir -p /tmp/o2-benchmark-data
kind create cluster --config "$SCRIPT_DIR/kind-config.yaml" --wait 120s

echo "[*] Cluster created. Nodes:"
kubectl get nodes -o wide

# ── Create namespaces ──────────────────────────
echo "[*] Creating namespaces..."
kubectl create namespace openobserve  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace opensearch   --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace benchmark    --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace logging      --dry-run=client -o yaml | kubectl apply -f -

echo "[*] Namespaces created:"
kubectl get namespaces

# ── Install Metrics Server ─────────────────────
echo "[*] Installing metrics-server (for kubectl top)..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server to work with KIND (self-signed certs)
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"},
    {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-preferred-address-types=InternalIP"}
  ]' 2>/dev/null || true

echo ""
echo "============================================"
echo "  Cluster setup complete!"
echo "  Nodes:       $(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
echo "  Namespaces:  openobserve, opensearch, benchmark, logging"
echo "============================================"
