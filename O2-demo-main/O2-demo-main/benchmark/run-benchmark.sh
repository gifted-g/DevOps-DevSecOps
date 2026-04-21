#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/../results"
mkdir -p "$RESULTS_DIR"

O2_HOST="${O2_HOST:-localhost}"
O2_PORT="${O2_PORT:-5080}"
O2_USER="root@benchmark.local"
O2_PASS="BenchmarkPass123!"

OS_HOST="${OS_HOST:-localhost}"
OS_PORT="${OS_PORT:-9200}"

BENCH_DURATION="${BENCH_DURATION:-300}"
WARMUP_DURATION="${WARMUP_DURATION:-30}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"
QUERY_ITERATIONS="${QUERY_ITERATIONS:-10}"

CSV_FILE="$RESULTS_DIR/benchmark-results.csv"
RAW_FILE="$RESULTS_DIR/raw-data.json"

# ── Utility functions ─────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*"; }

o2_api() {
  curl -s -u "$O2_USER:$O2_PASS" "http://${O2_HOST}:${O2_PORT}$1" "${@:2}"
}

os_api() {
  curl -s "http://${OS_HOST}:${OS_PORT}$1" "${@:2}"
}

time_ms() {
  # Returns elapsed time in milliseconds for a curl call
  local start end
  start=$(python3 -c 'import time; print(int(time.time()*1000))')
  eval "$@" > /dev/null 2>&1
  end=$(python3 -c 'import time; print(int(time.time()*1000))')
  echo $(( end - start ))
}

percentile() {
  # Calculate percentile from sorted array
  local -n arr=$1
  local p=$2
  local n=${#arr[@]}
  local idx=$(python3 -c "import math; print(int(math.ceil($p / 100.0 * $n) - 1))")
  echo "${arr[$idx]}"
}

# ── Pre-flight Checks ────────────────────────
preflight() {
  log "Running pre-flight checks..."

  log "  Checking OpenObserve..."
  local o2_status
  o2_status=$(o2_api "/healthz" -o /dev/null -w "%{http_code}" 2>/dev/null) || true
  if [[ "$o2_status" != "200" ]]; then
    log "  ERROR: OpenObserve not reachable (HTTP $o2_status)"
    return 1
  fi
  log "  OpenObserve: OK"

  log "  Checking OpenSearch..."
  local os_status
  os_status=$(os_api "/_cluster/health" -o /dev/null -w "%{http_code}" 2>/dev/null) || true
  if [[ "$os_status" != "200" ]]; then
    log "  ERROR: OpenSearch not reachable (HTTP $os_status)"
    return 1
  fi
  log "  OpenSearch: OK"

  log "  Checking LogStorm pod..."
  if ! kubectl get pods -n benchmark -l app=logstorm --no-headers 2>/dev/null | grep -q Running; then
    log "  WARNING: LogStorm pod not yet running"
  else
    log "  LogStorm: OK"
  fi

  log "Pre-flight checks passed!"
}

# ── Measure Startup Time ─────────────────────
measure_startup_times() {
  log "Measuring startup times..."

  local o2_start o2_ready os_start os_ready

  o2_start=$(kubectl get pod -n openobserve openobserve-0 -o jsonpath='{.status.startTime}' 2>/dev/null || echo "")
  o2_ready=$(kubectl get pod -n openobserve openobserve-0 -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null || echo "")

  os_start=$(kubectl get pod -n opensearch opensearch-0 -o jsonpath='{.status.startTime}' 2>/dev/null || echo "")
  os_ready=$(kubectl get pod -n opensearch opensearch-0 -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null || echo "")

  if [[ -n "$o2_start" && -n "$o2_ready" ]]; then
    O2_STARTUP_SEC=$(python3 -c "
from datetime import datetime
s = datetime.fromisoformat('${o2_start}'.replace('Z','+00:00'))
e = datetime.fromisoformat('${o2_ready}'.replace('Z','+00:00'))
print(int((e-s).total_seconds()))
")
    log "  OpenObserve startup: ${O2_STARTUP_SEC}s"
  else
    O2_STARTUP_SEC="N/A"
    log "  OpenObserve startup: N/A"
  fi

  if [[ -n "$os_start" && -n "$os_ready" ]]; then
    OS_STARTUP_SEC=$(python3 -c "
from datetime import datetime
s = datetime.fromisoformat('${os_start}'.replace('Z','+00:00'))
e = datetime.fromisoformat('${os_ready}'.replace('Z','+00:00'))
print(int((e-s).total_seconds()))
")
    log "  OpenSearch startup: ${OS_STARTUP_SEC}s"
  else
    OS_STARTUP_SEC="N/A"
    log "  OpenSearch startup: N/A"
  fi
}

# ── Ingestion Monitoring ─────────────────────
monitor_ingestion() {
  log "Monitoring ingestion for ${BENCH_DURATION}s (polling every ${POLL_INTERVAL}s)..."

  local start_time elapsed
  start_time=$(date +%s)
  local o2_counts=()
  local os_counts=()
  local timestamps=()

  while true; do
    elapsed=$(( $(date +%s) - start_time ))
    if (( elapsed >= BENCH_DURATION )); then
      break
    fi

    # OpenObserve log count
    local o2_count
    o2_count=$(o2_api "/api/default/default/_search" \
      -H "Content-Type: application/json" \
      -d '{"query":{"sql":"SELECT COUNT(*) as count FROM \"default\"","start_time":0,"end_time":'"$(date +%s000000)"'}}' 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hits',{}).get('total',d.get('total',0)))" 2>/dev/null) || o2_count=0

    # OpenSearch log count
    local os_count
    os_count=$(os_api "/logstorm/_count" 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null) || os_count=0

    o2_counts+=("$o2_count")
    os_counts+=("$os_count")
    timestamps+=("$elapsed")

    log "  [${elapsed}s] O2: ${o2_count} logs | OS: ${os_count} logs"

    sleep "$POLL_INTERVAL"
  done

  # Store final counts
  O2_FINAL_COUNT="${o2_counts[-1]:-0}"
  OS_FINAL_COUNT="${os_counts[-1]:-0}"
  O2_INGEST_RATE=$(python3 -c "print(round(${O2_FINAL_COUNT} / ${BENCH_DURATION}, 1))")
  OS_INGEST_RATE=$(python3 -c "print(round(${OS_FINAL_COUNT} / ${BENCH_DURATION}, 1))")

  log "Ingestion complete:"
  log "  OpenObserve: ${O2_FINAL_COUNT} logs (${O2_INGEST_RATE} logs/sec)"
  log "  OpenSearch:  ${OS_FINAL_COUNT} logs (${OS_INGEST_RATE} logs/sec)"

  # Write ingestion timeline to CSV
  echo "timestamp_sec,o2_count,os_count" > "$RESULTS_DIR/ingestion-timeline.csv"
  for i in "${!timestamps[@]}"; do
    echo "${timestamps[$i]},${o2_counts[$i]},${os_counts[$i]}"
  done >> "$RESULTS_DIR/ingestion-timeline.csv"
}

# ── Resource Monitoring ──────────────────────
monitor_resources() {
  log "Capturing resource snapshots..."

  local o2_cpu_samples=() o2_mem_samples=()
  local os_cpu_samples=() os_mem_samples=()
  local samples=5

  for (( i=0; i<samples; i++ )); do
    # OpenObserve resources
    local o2_top os_top
    o2_top=$(kubectl top pod -n openobserve openobserve-0 --no-headers 2>/dev/null || echo "openobserve-0 0m 0Mi")
    os_top=$(kubectl top pod -n opensearch opensearch-0 --no-headers 2>/dev/null || echo "opensearch-0 0m 0Mi")

    local o2_cpu o2_mem os_cpu os_mem
    o2_cpu=$(echo "$o2_top" | awk '{print $2}' | sed 's/m//')
    o2_mem=$(echo "$o2_top" | awk '{print $3}' | sed 's/Mi//')
    os_cpu=$(echo "$os_top" | awk '{print $2}' | sed 's/m//')
    os_mem=$(echo "$os_top" | awk '{print $3}' | sed 's/Mi//')

    o2_cpu_samples+=("${o2_cpu:-0}")
    o2_mem_samples+=("${o2_mem:-0}")
    os_cpu_samples+=("${os_cpu:-0}")
    os_mem_samples+=("${os_mem:-0}")

    log "  Sample $((i+1)): O2 CPU=${o2_cpu}m MEM=${o2_mem}Mi | OS CPU=${os_cpu}m MEM=${os_mem}Mi"
    sleep 10
  done

  # Calculate averages and peaks
  O2_AVG_CPU=$(python3 -c "d=[${o2_cpu_samples[*]// /,}]; print(round(sum(d)/len(d)))")
  O2_PEAK_CPU=$(python3 -c "d=[${o2_cpu_samples[*]// /,}]; print(max(d))")
  O2_AVG_MEM=$(python3 -c "d=[${o2_mem_samples[*]// /,}]; print(round(sum(d)/len(d)))")
  O2_PEAK_MEM=$(python3 -c "d=[${o2_mem_samples[*]// /,}]; print(max(d))")

  OS_AVG_CPU=$(python3 -c "d=[${os_cpu_samples[*]// /,}]; print(round(sum(d)/len(d)))")
  OS_PEAK_CPU=$(python3 -c "d=[${os_cpu_samples[*]// /,}]; print(max(d))")
  OS_AVG_MEM=$(python3 -c "d=[${os_mem_samples[*]// /,}]; print(round(sum(d)/len(d)))")
  OS_PEAK_MEM=$(python3 -c "d=[${os_mem_samples[*]// /,}]; print(max(d))")

  log "Resource summary:"
  log "  O2: CPU avg=${O2_AVG_CPU}m peak=${O2_PEAK_CPU}m | MEM avg=${O2_AVG_MEM}Mi peak=${O2_PEAK_MEM}Mi"
  log "  OS: CPU avg=${OS_AVG_CPU}m peak=${OS_PEAK_CPU}m | MEM avg=${OS_AVG_MEM}Mi peak=${OS_PEAK_MEM}Mi"
}

# ── Query Benchmark ──────────────────────────
run_query_benchmark() {
  log "Running query benchmark ($QUERY_ITERATIONS iterations per query)..."
  source "$SCRIPT_DIR/queries/openobserve-queries.sh"
  source "$SCRIPT_DIR/queries/opensearch-queries.sh"

  echo "query_name,platform,iteration,latency_ms" > "$RESULTS_DIR/query-results.csv"

  local query_names=("keyword_search" "field_filter" "time_range" "aggregation" "fulltext_search" "complex_query")

  for qname in "${query_names[@]}"; do
    log "  Query: $qname"
    local o2_latencies=() os_latencies=()

    for (( i=1; i<=QUERY_ITERATIONS; i++ )); do
      # OpenObserve query
      local o2_lat
      o2_lat=$(time_ms "run_o2_query_${qname}")
      o2_latencies+=("$o2_lat")
      echo "${qname},openobserve,${i},${o2_lat}" >> "$RESULTS_DIR/query-results.csv"

      # OpenSearch query
      local os_lat
      os_lat=$(time_ms "run_os_query_${qname}")
      os_latencies+=("$os_lat")
      echo "${qname},opensearch,${i},${os_lat}" >> "$RESULTS_DIR/query-results.csv"
    done

    # Sort for percentile calculation
    IFS=$'\n' o2_sorted=($(sort -n <<<"${o2_latencies[*]}")); unset IFS
    IFS=$'\n' os_sorted=($(sort -n <<<"${os_latencies[*]}")); unset IFS

    local o2_p50 o2_p95 o2_p99 os_p50 os_p95 os_p99
    o2_p50=$(percentile o2_sorted 50)
    o2_p95=$(percentile o2_sorted 95)
    o2_p99=$(percentile o2_sorted 99)
    os_p50=$(percentile os_sorted 50)
    os_p95=$(percentile os_sorted 95)
    os_p99=$(percentile os_sorted 99)

    log "    O2: p50=${o2_p50}ms p95=${o2_p95}ms p99=${o2_p99}ms"
    log "    OS: p50=${os_p50}ms p95=${os_p95}ms p99=${os_p99}ms"

    # Store in associative-like variables
    eval "O2_${qname}_P50=$o2_p50"
    eval "O2_${qname}_P95=$o2_p95"
    eval "O2_${qname}_P99=$o2_p99"
    eval "OS_${qname}_P50=$os_p50"
    eval "OS_${qname}_P95=$os_p95"
    eval "OS_${qname}_P99=$os_p99"
  done
}

# ── Storage Measurement ──────────────────────
measure_storage() {
  log "Measuring storage usage..."

  # OpenObserve storage via PVC
  O2_STORAGE_MB=$(kubectl exec -n openobserve openobserve-0 -- du -sm /data 2>/dev/null | awk '{print $1}') || O2_STORAGE_MB=0

  # OpenSearch storage via API
  OS_STORAGE_BYTES=$(os_api "/_cat/indices/logstorm?h=store.size&bytes=b" 2>/dev/null | tr -d '[:space:]') || OS_STORAGE_BYTES=0
  OS_STORAGE_MB=$(python3 -c "print(round(${OS_STORAGE_BYTES:-0} / 1048576, 1))")

  log "Storage usage:"
  log "  OpenObserve: ${O2_STORAGE_MB} MB"
  log "  OpenSearch:  ${OS_STORAGE_MB} MB"

  # Estimate compression ratio (assume ~500 bytes avg log size)
  local raw_mb
  raw_mb=$(python3 -c "
o2=$O2_FINAL_COUNT; os=$OS_FINAL_COUNT; avg=max(o2,os)
print(round(avg * 500 / 1048576, 1))
")
  O2_COMPRESSION=$(python3 -c "print(round($raw_mb / max(float($O2_STORAGE_MB), 0.1), 1))")
  OS_COMPRESSION=$(python3 -c "print(round($raw_mb / max(float($OS_STORAGE_MB), 0.1), 1))")

  log "Estimated compression:"
  log "  OpenObserve: ${O2_COMPRESSION}x"
  log "  OpenSearch:  ${OS_COMPRESSION}x"
}

# ── Export Results ────────────────────────────
export_results() {
  log "Exporting results to CSV..."

  cat > "$CSV_FILE" <<EOF
metric,openobserve,opensearch,unit,winner
startup_time,${O2_STARTUP_SEC},${OS_STARTUP_SEC},seconds,$(python3 -c "
o2='${O2_STARTUP_SEC}'; os='${OS_STARTUP_SEC}'
if o2=='N/A' or os=='N/A': print('N/A')
elif int(o2)<int(os): print('OpenObserve')
elif int(os)<int(o2): print('OpenSearch')
else: print('Tie')
")
total_logs_ingested,${O2_FINAL_COUNT},${OS_FINAL_COUNT},count,$(python3 -c "print('OpenObserve' if ${O2_FINAL_COUNT}>${OS_FINAL_COUNT} else 'OpenSearch' if ${OS_FINAL_COUNT}>${O2_FINAL_COUNT} else 'Tie')")
ingestion_rate,${O2_INGEST_RATE},${OS_INGEST_RATE},logs/sec,$(python3 -c "print('OpenObserve' if ${O2_INGEST_RATE}>${OS_INGEST_RATE} else 'OpenSearch' if ${OS_INGEST_RATE}>${O2_INGEST_RATE} else 'Tie')")
storage_used,${O2_STORAGE_MB},${OS_STORAGE_MB},MB,$(python3 -c "print('OpenObserve' if float('${O2_STORAGE_MB}')<float('${OS_STORAGE_MB}') else 'OpenSearch' if float('${OS_STORAGE_MB}')<float('${O2_STORAGE_MB}') else 'Tie')")
compression_ratio,${O2_COMPRESSION},${OS_COMPRESSION},x,$(python3 -c "print('OpenObserve' if float('${O2_COMPRESSION}')>float('${OS_COMPRESSION}') else 'OpenSearch' if float('${OS_COMPRESSION}')>float('${O2_COMPRESSION}') else 'Tie')")
avg_cpu,${O2_AVG_CPU},${OS_AVG_CPU},millicores,$(python3 -c "print('OpenObserve' if ${O2_AVG_CPU}<${OS_AVG_CPU} else 'OpenSearch' if ${OS_AVG_CPU}<${O2_AVG_CPU} else 'Tie')")
peak_cpu,${O2_PEAK_CPU},${OS_PEAK_CPU},millicores,$(python3 -c "print('OpenObserve' if ${O2_PEAK_CPU}<${OS_PEAK_CPU} else 'OpenSearch' if ${OS_PEAK_CPU}<${O2_PEAK_CPU} else 'Tie')")
avg_memory,${O2_AVG_MEM},${OS_AVG_MEM},MiB,$(python3 -c "print('OpenObserve' if ${O2_AVG_MEM}<${OS_AVG_MEM} else 'OpenSearch' if ${OS_AVG_MEM}<${O2_AVG_MEM} else 'Tie')")
peak_memory,${O2_PEAK_MEM},${OS_PEAK_MEM},MiB,$(python3 -c "print('OpenObserve' if ${O2_PEAK_MEM}<${OS_PEAK_MEM} else 'OpenSearch' if ${OS_PEAK_MEM}<${O2_PEAK_MEM} else 'Tie')")
keyword_search_p50,${O2_keyword_search_P50:-N/A},${OS_keyword_search_P50:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_keyword_search_P50:-999}<${OS_keyword_search_P50:-999} else 'OpenSearch' if ${OS_keyword_search_P50:-999}<${O2_keyword_search_P50:-999} else 'Tie')")
keyword_search_p95,${O2_keyword_search_P95:-N/A},${OS_keyword_search_P95:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_keyword_search_P95:-999}<${OS_keyword_search_P95:-999} else 'OpenSearch' if ${OS_keyword_search_P95:-999}<${O2_keyword_search_P95:-999} else 'Tie')")
field_filter_p50,${O2_field_filter_P50:-N/A},${OS_field_filter_P50:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_field_filter_P50:-999}<${OS_field_filter_P50:-999} else 'OpenSearch' if ${OS_field_filter_P50:-999}<${O2_field_filter_P50:-999} else 'Tie')")
field_filter_p95,${O2_field_filter_P95:-N/A},${OS_field_filter_P95:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_field_filter_P95:-999}<${OS_field_filter_P95:-999} else 'OpenSearch' if ${OS_field_filter_P95:-999}<${O2_field_filter_P95:-999} else 'Tie')")
time_range_p50,${O2_time_range_P50:-N/A},${OS_time_range_P50:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_time_range_P50:-999}<${OS_time_range_P50:-999} else 'OpenSearch' if ${OS_time_range_P50:-999}<${O2_time_range_P50:-999} else 'Tie')")
aggregation_p50,${O2_aggregation_P50:-N/A},${OS_aggregation_P50:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_aggregation_P50:-999}<${OS_aggregation_P50:-999} else 'OpenSearch' if ${OS_aggregation_P50:-999}<${O2_aggregation_P50:-999} else 'Tie')")
aggregation_p95,${O2_aggregation_P95:-N/A},${OS_aggregation_P95:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_aggregation_P95:-999}<${OS_aggregation_P95:-999} else 'OpenSearch' if ${OS_aggregation_P95:-999}<${O2_aggregation_P95:-999} else 'Tie')")
fulltext_search_p50,${O2_fulltext_search_P50:-N/A},${OS_fulltext_search_P50:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_fulltext_search_P50:-999}<${OS_fulltext_search_P50:-999} else 'OpenSearch' if ${OS_fulltext_search_P50:-999}<${O2_fulltext_search_P50:-999} else 'Tie')")
complex_query_p50,${O2_complex_query_P50:-N/A},${OS_complex_query_P50:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_complex_query_P50:-999}<${OS_complex_query_P50:-999} else 'OpenSearch' if ${OS_complex_query_P50:-999}<${O2_complex_query_P50:-999} else 'Tie')")
complex_query_p95,${O2_complex_query_P95:-N/A},${OS_complex_query_P95:-N/A},ms,$(python3 -c "print('OpenObserve' if ${O2_complex_query_P95:-999}<${OS_complex_query_P95:-999} else 'OpenSearch' if ${OS_complex_query_P95:-999}<${O2_complex_query_P95:-999} else 'Tie')")
EOF

  log "Results written to $CSV_FILE"
}

# ── Main ─────────────────────────────────────
main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║   OpenObserve vs OpenSearch Benchmark Runner        ║"
  echo "║   Duration: ${BENCH_DURATION}s | Queries: ${QUERY_ITERATIONS} iterations       ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  preflight

  echo ""
  log "═══ Phase 1: Startup Time ═══"
  measure_startup_times

  echo ""
  log "═══ Phase 2: Warmup (${WARMUP_DURATION}s) ═══"
  log "Waiting for log pipeline to warm up..."
  sleep "$WARMUP_DURATION"

  echo ""
  log "═══ Phase 3: Ingestion Monitoring ═══"
  monitor_ingestion &
  local ingest_pid=$!

  log "═══ Phase 3b: Resource Monitoring (parallel) ═══"
  monitor_resources
  wait "$ingest_pid"

  echo ""
  log "═══ Phase 4: Query Benchmark ═══"
  run_query_benchmark

  echo ""
  log "═══ Phase 5: Storage Measurement ═══"
  measure_storage

  echo ""
  log "═══ Phase 6: Export Results ═══"
  export_results

  echo ""
  log "═══ Phase 7: Generate Report ═══"
  bash "$SCRIPT_DIR/generate-report.sh" "$CSV_FILE"

  echo ""
  log "Benchmark complete! Results in $RESULTS_DIR/"
}

main "$@"
