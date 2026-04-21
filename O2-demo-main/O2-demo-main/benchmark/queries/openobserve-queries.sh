#!/usr/bin/env bash
# OpenObserve query functions for benchmarking
# Each function runs a single query via the OpenObserve API

O2_HOST="${O2_HOST:-localhost}"
O2_PORT="${O2_PORT:-5080}"
O2_USER="root@benchmark.local"
O2_PASS="BenchmarkPass123!"

_o2_search() {
  local sql="$1"
  local now_us=$(python3 -c "import time; print(int(time.time()*1000000))")
  local start_us=$(( now_us - 600000000 ))  # last 10 minutes

  curl -s -u "$O2_USER:$O2_PASS" \
    "http://${O2_HOST}:${O2_PORT}/api/default/_search" \
    -H "Content-Type: application/json" \
    -d "{
      \"query\": {
        \"sql\": \"${sql}\",
        \"start_time\": ${start_us},
        \"end_time\": ${now_us}
      }
    }"
}

# Query 1: Simple keyword search for "ERROR"
run_o2_query_keyword_search() {
  _o2_search "SELECT * FROM \"default\" WHERE log LIKE '%ERROR%' LIMIT 100"
}

# Query 2: Field filter — level=ERROR
run_o2_query_field_filter() {
  _o2_search "SELECT * FROM \"default\" WHERE str_match(log, 'level') AND str_match(log, 'ERROR') LIMIT 100"
}

# Query 3: Time range query — last 5 minutes
run_o2_query_time_range() {
  _o2_search "SELECT * FROM \"default\" ORDER BY _timestamp DESC LIMIT 200"
}

# Query 4: Aggregation — count by service
run_o2_query_aggregation() {
  _o2_search "SELECT COUNT(*) as count FROM \"default\" GROUP BY _timestamp"
}

# Query 5: Full-text search — specific error message
run_o2_query_fulltext_search() {
  _o2_search "SELECT * FROM \"default\" WHERE str_match(log, 'Connection refused') LIMIT 50"
}

# Query 6: Complex query — multi-field filter + aggregation
run_o2_query_complex_query() {
  _o2_search "SELECT COUNT(*) as count FROM \"default\" WHERE str_match(log, 'ERROR') AND str_match(log, 'payment-service')"
}
