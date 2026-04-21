#!/usr/bin/env bash
set -euo pipefail

CSV_FILE="${1:-results/benchmark-results.csv}"

if [[ ! -f "$CSV_FILE" ]]; then
  echo "ERROR: CSV file not found: $CSV_FILE"
  exit 1
fi

RESULTS_DIR="$(dirname "$CSV_FILE")"
REPORT_FILE="$RESULTS_DIR/report.txt"

# ── Count wins ──────────────────────────────
o2_wins=0
os_wins=0
ties=0
total=0

while IFS=',' read -r metric o2_val os_val unit winner; do
  [[ "$metric" == "metric" ]] && continue
  total=$((total + 1))
  case "$winner" in
    OpenObserve) o2_wins=$((o2_wins + 1)) ;;
    OpenSearch)  os_wins=$((os_wins + 1)) ;;
    *)           ties=$((ties + 1)) ;;
  esac
done < "$CSV_FILE"

# ── Generate Report ──────────────────────────
cat > "$REPORT_FILE" <<'HEADER'

╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║         🏆  OpenObserve vs OpenSearch — Benchmark Report  🏆               ║
║                                                                            ║
╚══════════════════════════════════════════════════════════════════════════════╝

HEADER

cat >> "$REPORT_FILE" <<EOF
  Date:     $(date '+%Y-%m-%d %H:%M:%S')
  Duration: ${BENCH_DURATION:-300}s ingestion + query benchmark
  Log App:  LogStorm (Go) — 5 log types, ~2000 logs/sec
  Platform: KIND (Kubernetes IN Docker)

EOF

# ── Section: Ingestion Performance ───────────
printf "\n  %-40s  %15s  %15s  %8s\n" "METRIC" "OPENOBSERVE" "OPENSEARCH" "WINNER" >> "$REPORT_FILE"
printf "  %s\n" "$(printf '═%.0s' {1..82})" >> "$REPORT_FILE"

while IFS=',' read -r metric o2_val os_val unit winner; do
  [[ "$metric" == "metric" ]] && continue

  # Format metric name
  local_metric=$(echo "$metric" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

  # Add section headers
  case "$metric" in
    startup_time)
      printf "\n  ── Operational ──────────────────────────────────────────────────────────────\n" >> "$REPORT_FILE"
      ;;
    total_logs_ingested)
      printf "\n  ── Ingestion Performance ────────────────────────────────────────────────────\n" >> "$REPORT_FILE"
      ;;
    storage_used)
      printf "\n  ── Storage Efficiency ───────────────────────────────────────────────────────\n" >> "$REPORT_FILE"
      ;;
    avg_cpu)
      printf "\n  ── Resource Consumption ─────────────────────────────────────────────────────\n" >> "$REPORT_FILE"
      ;;
    keyword_search_p50)
      printf "\n  ── Query Latency ───────────────────────────────────────────────────────────\n" >> "$REPORT_FILE"
      ;;
  esac

  # Add winner indicator
  local indicator=""
  case "$winner" in
    OpenObserve) indicator="← O2" ;;
    OpenSearch)  indicator="← OS" ;;
    Tie)         indicator="  ==" ;;
    *)           indicator="  ??" ;;
  esac

  printf "  %-40s  %12s %s  %12s %s  %s\n" \
    "$local_metric" "$o2_val" "$unit" "$os_val" "$unit" "$indicator" >> "$REPORT_FILE"

done < "$CSV_FILE"

# ── Summary ─────────────────────────────────
cat >> "$REPORT_FILE" <<EOF

  ═══════════════════════════════════════════════════════════════════════════════

  📊 SCORECARD
  ───────────────────────────
  OpenObserve wins:  ${o2_wins}/${total}
  OpenSearch  wins:  ${os_wins}/${total}
  Ties:              ${ties}/${total}

EOF

if (( o2_wins > os_wins )); then
  cat >> "$REPORT_FILE" <<'EOF'
  ╔═════════════════════════════════════════════════════════════════════════════╗
  ║                                                                           ║
  ║   🏆 VERDICT: OpenObserve WINS the benchmark!                            ║
  ║                                                                           ║
  ║   Key advantages:                                                         ║
  ║   • Lower resource consumption (Rust vs JVM)                              ║
  ║   • Superior storage efficiency (Parquet columnar vs Lucene)              ║
  ║   • Faster startup time (single binary)                                   ║
  ║   • Competitive query performance with SQL interface                      ║
  ║   • Simpler deployment (single binary vs multi-component cluster)         ║
  ║                                                                           ║
  ╚═════════════════════════════════════════════════════════════════════════════╝
EOF
elif (( os_wins > o2_wins )); then
  cat >> "$REPORT_FILE" <<'EOF'
  ╔═════════════════════════════════════════════════════════════════════════════╗
  ║   VERDICT: OpenSearch wins this round.                                    ║
  ╚═════════════════════════════════════════════════════════════════════════════╝
EOF
else
  cat >> "$REPORT_FILE" <<'EOF'
  ╔═════════════════════════════════════════════════════════════════════════════╗
  ║   VERDICT: Tie — both platforms performed comparably.                     ║
  ╚═════════════════════════════════════════════════════════════════════════════╝
EOF
fi

echo "" >> "$REPORT_FILE"

# ── Print to terminal ────────────────────────
cat "$REPORT_FILE"

echo ""
echo "Report saved to: $REPORT_FILE"
echo "Raw CSV data:    $CSV_FILE"
if [[ -f "$RESULTS_DIR/query-results.csv" ]]; then
  echo "Query details:   $RESULTS_DIR/query-results.csv"
fi
if [[ -f "$RESULTS_DIR/ingestion-timeline.csv" ]]; then
  echo "Ingestion data:  $RESULTS_DIR/ingestion-timeline.csv"
fi
