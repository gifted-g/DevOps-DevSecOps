#!/usr/bin/env bash
set -euo pipefail

O2_USER="root@benchmark.local"
O2_PASS="BenchmarkPass123!"

o2_search() {
  local sql="$1"
  local now_us=$(python3 -c 'import time; print(int(time.time()*1000000))')
  local start_us=$((now_us - 3600000000))
  curl -s -u "$O2_USER:$O2_PASS" 'http://localhost:5080/api/default/_search' \
    -H 'Content-Type: application/json' \
    -d "{\"query\":{\"sql\":\"$sql\",\"start_time\":$start_us,\"end_time\":$now_us}}"
}

os_search() {
  local body="$1"
  curl -s 'http://localhost:9200/logstorm/_search' \
    -H 'Content-Type: application/json' \
    -d "$body"
}

time_cmd() {
  local start end
  start=$(python3 -c 'import time; print(int(time.time()*1000))')
  eval "$@" > /dev/null 2>&1
  end=$(python3 -c 'import time; print(int(time.time()*1000))')
  echo $((end - start))
}

echo "============================================"
echo "  BENCHMARK RESULTS"
echo "============================================"
echo ""

# 1. Ingestion counts
echo "=== INGESTION ==="
O2_COUNT=$(o2_search "SELECT COUNT(*) as count FROM default" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hits'][0]['count'])")
OS_COUNT=$(curl -s 'http://localhost:9200/logstorm/_count' | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
echo "O2_TOTAL=$O2_COUNT"
echo "OS_TOTAL=$OS_COUNT"

# Wait 60 seconds for throughput measurement
echo "Measuring throughput over 60s..."
sleep 60
O2_COUNT2=$(o2_search "SELECT COUNT(*) as count FROM default" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hits'][0]['count'])")
OS_COUNT2=$(curl -s 'http://localhost:9200/logstorm/_count' | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")
O2_RATE=$(python3 -c "print(round(($O2_COUNT2 - $O2_COUNT) / 60, 1))")
OS_RATE=$(python3 -c "print(round(($OS_COUNT2 - $OS_COUNT) / 60, 1))")
echo "O2_RATE=${O2_RATE}/sec"
echo "OS_RATE=${OS_RATE}/sec"
echo "O2_TOTAL_FINAL=$O2_COUNT2"
echo "OS_TOTAL_FINAL=$OS_COUNT2"

# 2. Resources - 5 samples, 5s apart
echo ""
echo "=== RESOURCES ==="
> /tmp/resource_samples.txt
for i in 1 2 3 4 5; do
  kubectl top pod -n openobserve openobserve-0 --no-headers 2>/dev/null >> /tmp/resource_samples.txt || echo "openobserve-0 0m 0Mi" >> /tmp/resource_samples.txt
  kubectl top pod -n opensearch opensearch-0 --no-headers 2>/dev/null >> /tmp/resource_samples.txt || echo "opensearch-0 0m 0Mi" >> /tmp/resource_samples.txt
  sleep 5
done

python3 /Users/abhishekveeramalla/Downloads/O2-demo/benchmark/parse_resources.py

# 3. Storage
echo ""
echo "=== STORAGE ==="
O2_STORAGE=$(kubectl exec -n openobserve openobserve-0 -- du -sm /data 2>/dev/null | awk '{print $1}')
OS_STORAGE_BYTES=$(curl -s 'http://localhost:9200/_cat/indices/logstorm?h=store.size&bytes=b' | tr -d '[:space:]')
OS_STORAGE=$(python3 -c "print(round(${OS_STORAGE_BYTES:-0}/1048576,1))")
echo "O2_STORAGE=${O2_STORAGE}MB"
echo "OS_STORAGE=${OS_STORAGE}MB"

# 4. Query benchmark - 6 queries x 10 iterations
echo ""
echo "=== QUERY BENCHMARK ==="
ITERS=10

run_query_bench() {
  local name="$1"
  local o2_cmd="$2"
  local os_cmd="$3"

  local o2_times=""
  local os_times=""

  for i in $(seq 1 $ITERS); do
    o2_t=$(time_cmd $o2_cmd)
    os_t=$(time_cmd $os_cmd)
    if [ -z "$o2_times" ]; then
      o2_times="$o2_t"
      os_times="$os_t"
    else
      o2_times="$o2_times,$o2_t"
      os_times="$os_times,$os_t"
    fi
  done

  python3 -c "
import math
o2 = sorted([${o2_times}])
os_ = sorted([${os_times}])
def p(arr, pct):
    idx = max(0, int(math.ceil(pct/100.0 * len(arr))) - 1)
    return arr[idx]
print(f'  ${name:<25s} O2 p50={p(o2,50)}ms p95={p(o2,95)}ms p99={p(o2,99)}ms | OS p50={p(os_,50)}ms p95={p(os_,95)}ms p99={p(os_,99)}ms')
print(f'QDATA|${name}|{p(o2,50)}|{p(o2,95)}|{p(o2,99)}|{p(os_,50)}|{p(os_,95)}|{p(os_,99)}')
"
}

# Q1: Keyword search
echo "  Running: keyword_search"
run_query_bench "keyword_search" \
  "o2_search 'SELECT * FROM default WHERE match_all_raw_ignore_case(log, '\"'\"'ERROR'\"'\"') LIMIT 100'" \
  "os_search '{\"size\":100,\"query\":{\"match\":{\"log\":\"ERROR\"}}}'"

# Q2: Field filter
echo "  Running: field_filter"
run_query_bench "field_filter" \
  "o2_search 'SELECT * FROM default WHERE match_all_raw_ignore_case(log, '\"'\"'level'\"'\"') LIMIT 100'" \
  "os_search '{\"size\":100,\"query\":{\"bool\":{\"must\":[{\"match\":{\"log\":\"ERROR\"}},{\"match\":{\"log\":\"level\"}}]}}}'"

# Q3: Time range
echo "  Running: time_range"
run_query_bench "time_range" \
  "o2_search 'SELECT * FROM default ORDER BY _timestamp DESC LIMIT 200'" \
  "os_search '{\"size\":200,\"sort\":[{\"@timestamp\":{\"order\":\"desc\",\"unmapped_type\":\"date\"}}],\"query\":{\"match_all\":{}}}'"

# Q4: Aggregation
echo "  Running: aggregation"
run_query_bench "aggregation" \
  "o2_search 'SELECT COUNT(*) as count FROM default'" \
  "os_search '{\"size\":0,\"aggs\":{\"total\":{\"value_count\":{\"field\":\"_id\"}}}}'"

# Q5: Full-text search
echo "  Running: fulltext_search"
run_query_bench "fulltext_search" \
  "o2_search 'SELECT * FROM default WHERE match_all_raw_ignore_case(log, '\"'\"'Connection refused'\"'\"') LIMIT 50'" \
  "os_search '{\"size\":50,\"query\":{\"match_phrase\":{\"log\":\"Connection refused\"}}}'"

# Q6: Complex query
echo "  Running: complex_query"
run_query_bench "complex_query" \
  "o2_search 'SELECT COUNT(*) FROM default WHERE match_all_raw_ignore_case(log, '\"'\"'ERROR'\"'\"') AND match_all_raw_ignore_case(log, '\"'\"'payment'\"'\"')'" \
  "os_search '{\"size\":0,\"query\":{\"bool\":{\"must\":[{\"match\":{\"log\":\"ERROR\"}},{\"match\":{\"log\":\"payment-service\"}}]}},\"aggs\":{\"error_count\":{\"value_count\":{\"field\":\"_id\"}}}}'"

echo ""
echo "=== DONE ==="
