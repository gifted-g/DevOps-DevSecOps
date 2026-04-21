#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="o2-benchmark"

# ── Colors ──────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

# ── Pre-flight ─────────────────────────────
echo -e "${BOLD}"
cat << 'BANNER'

  ╔══════════════════════════════════════════════════════════════╗
  ║                                                              ║
  ║    ⚡ OpenObserve vs OpenSearch Benchmark Suite ⚡           ║
  ║                                                              ║
  ║    LogStorm → FluentBit → [OpenObserve | OpenSearch]         ║
  ║    on KIND (Kubernetes IN Docker)                            ║
  ║                                                              ║
  ╚══════════════════════════════════════════════════════════════╝

BANNER
echo -e "${NC}"

for cmd in docker kind kubectl go curl jq python3; do
  if ! command -v "$cmd" &>/dev/null; then
    err "'$cmd' is required but not installed."
    exit 1
  fi
done
ok "All prerequisites found"

# Check Docker is running
if ! docker info &>/dev/null; then
  err "Docker is not running. Please start Docker Desktop first."
  exit 1
fi
ok "Docker is running"

# Check Docker memory (warn if < 6GB)
DOCKER_MEM=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
DOCKER_MEM_GB=$(python3 -c "print(round(${DOCKER_MEM} / 1073741824, 1))")
if (( $(python3 -c "print(1 if $DOCKER_MEM_GB < 6 else 0)") )); then
  warn "Docker has only ${DOCKER_MEM_GB}GB RAM. Recommend 6GB+ for this benchmark."
  warn "Increase in Docker Desktop → Settings → Resources → Memory"
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi
ok "Docker memory: ${DOCKER_MEM_GB}GB"

# ══════════════════════════════════════════════
# Step 1: Create KIND Cluster
# ══════════════════════════════════════════════
echo ""
log "${BOLD}Step 1/7: Creating KIND cluster...${NC}"
bash "$ROOT_DIR/infra/setup-cluster.sh"
ok "KIND cluster ready"

# ══════════════════════════════════════════════
# Step 2: Build LogStorm image & load into KIND
# ══════════════════════════════════════════════
echo ""
log "${BOLD}Step 2/7: Building LogStorm container image...${NC}"
cd "$ROOT_DIR/app/logstorm"
docker build -t logstorm:latest .
kind load docker-image logstorm:latest --name "$CLUSTER_NAME"
cd "$ROOT_DIR"
ok "LogStorm image built and loaded into KIND"

# ══════════════════════════════════════════════
# Step 3: Deploy OpenObserve
# ══════════════════════════════════════════════
echo ""
log "${BOLD}Step 3/7: Deploying OpenObserve...${NC}"
kubectl apply -f "$ROOT_DIR/deploy/openobserve/configmap.yaml"
kubectl apply -f "$ROOT_DIR/deploy/openobserve/statefulset.yaml"
kubectl apply -f "$ROOT_DIR/deploy/openobserve/service.yaml"
log "Waiting for OpenObserve to be ready..."
kubectl wait --for=condition=ready pod/openobserve-0 -n openobserve --timeout=180s
ok "OpenObserve is running"

# ══════════════════════════════════════════════
# Step 4: Deploy OpenSearch
# ══════════════════════════════════════════════
echo ""
log "${BOLD}Step 4/7: Deploying OpenSearch...${NC}"
kubectl apply -f "$ROOT_DIR/deploy/opensearch/configmap.yaml"
kubectl apply -f "$ROOT_DIR/deploy/opensearch/statefulset.yaml"
kubectl apply -f "$ROOT_DIR/deploy/opensearch/service.yaml"
log "Waiting for OpenSearch to be ready (JVM startup takes longer)..."
kubectl wait --for=condition=ready pod/opensearch-0 -n opensearch --timeout=300s
ok "OpenSearch is running"

# ══════════════════════════════════════════════
# Step 5: Deploy FluentBit
# ══════════════════════════════════════════════
echo ""
log "${BOLD}Step 5/7: Deploying FluentBit log collector...${NC}"
kubectl apply -f "$ROOT_DIR/deploy/fluentbit/configmap.yaml"
kubectl apply -f "$ROOT_DIR/deploy/fluentbit/daemonset.yaml"
log "Waiting for FluentBit pods..."
kubectl rollout status daemonset/fluentbit -n logging --timeout=120s
ok "FluentBit is running"

# ══════════════════════════════════════════════
# Step 6: Deploy LogStorm
# ══════════════════════════════════════════════
echo ""
log "${BOLD}Step 6/7: Deploying LogStorm log generator...${NC}"
kubectl apply -f "$ROOT_DIR/deploy/logstorm/deployment.yaml"
kubectl rollout status deployment/logstorm -n benchmark --timeout=60s
ok "LogStorm is generating logs"

# ══════════════════════════════════════════════
# Verify everything
# ══════════════════════════════════════════════
echo ""
log "Verifying all components..."
echo ""
kubectl get pods -A --field-selector=status.phase!=Succeeded | grep -E "(openobserve|opensearch|benchmark|logging)" || true
echo ""

# Quick API health checks
log "Checking API endpoints..."
sleep 5

O2_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "root@benchmark.local:BenchmarkPass123!" "http://localhost:5080/healthz" 2>/dev/null) || O2_STATUS="000"
OS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/_cluster/health" 2>/dev/null) || OS_STATUS="000"

if [[ "$O2_STATUS" == "200" ]]; then
  ok "OpenObserve API: HTTP $O2_STATUS"
else
  warn "OpenObserve API: HTTP $O2_STATUS (may need a moment)"
fi

if [[ "$OS_STATUS" == "200" ]]; then
  ok "OpenSearch API: HTTP $OS_STATUS"
else
  warn "OpenSearch API: HTTP $OS_STATUS (may need a moment)"
fi

# ══════════════════════════════════════════════
# Step 7: Run Benchmark
# ══════════════════════════════════════════════
echo ""
log "${BOLD}Step 7/7: Running benchmark...${NC}"
echo ""
bash "$ROOT_DIR/benchmark/run-benchmark.sh"

# ══════════════════════════════════════════════
# Done!
# ══════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}"
cat << 'DONE'
  ══════════════════════════════════════════════
  Benchmark complete!

  Results:
    results/report.txt            ← Full report
    results/benchmark-results.csv ← Raw metrics
    results/query-results.csv     ← Query latencies
    results/ingestion-timeline.csv← Ingestion over time

  OpenObserve UI:  http://localhost:5080
    User: root@benchmark.local
    Pass: BenchmarkPass123!

  OpenSearch API:  http://localhost:9200

  Cleanup: kind delete cluster --name o2-benchmark
  ══════════════════════════════════════════════
DONE
echo -e "${NC}"
