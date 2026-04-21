#!/usr/bin/env python3
"""Query benchmark: runs 6 query types x 10 iterations against both platforms."""

import json
import math
import time
import subprocess
import sys

O2_USER = "root@benchmark.local"
O2_PASS = "BenchmarkPass123!"
ITERS = 10

def o2_query(sql):
    now_us = int(time.time() * 1000000)
    start_us = now_us - 3600000000
    body = json.dumps({
        "query": {
            "sql": sql,
            "start_time": start_us,
            "end_time": now_us
        }
    })
    result = subprocess.run(
        ["curl", "-s", "-u", f"{O2_USER}:{O2_PASS}",
         "http://localhost:5080/api/default/_search",
         "-H", "Content-Type: application/json",
         "-d", body],
        capture_output=True, text=True
    )
    return result.stdout

def os_query(body):
    result = subprocess.run(
        ["curl", "-s",
         "http://localhost:9200/logstorm/_search",
         "-H", "Content-Type: application/json",
         "-d", body],
        capture_output=True, text=True
    )
    return result.stdout

def time_query(func, *args):
    start = time.time()
    func(*args)
    end = time.time()
    return int((end - start) * 1000)

def percentile(arr, pct):
    s = sorted(arr)
    idx = max(0, int(math.ceil(pct / 100.0 * len(s))) - 1)
    return s[idx]

queries = [
    {
        "name": "keyword_search",
        "o2_sql": "SELECT * FROM default WHERE match_all('ERROR') LIMIT 100",
        "os_body": json.dumps({"size": 100, "query": {"match": {"log": "ERROR"}}})
    },
    {
        "name": "field_filter",
        "o2_sql": "SELECT * FROM default WHERE match_all('level') AND match_all('ERROR') LIMIT 100",
        "os_body": json.dumps({"size": 100, "query": {"bool": {"must": [{"match": {"log": "ERROR"}}, {"match": {"log": "level"}}]}}})
    },
    {
        "name": "time_range",
        "o2_sql": "SELECT * FROM default ORDER BY _timestamp DESC LIMIT 200",
        "os_body": json.dumps({"size": 200, "sort": [{"@timestamp": {"order": "desc", "unmapped_type": "date"}}], "query": {"match_all": {}}})
    },
    {
        "name": "aggregation",
        "o2_sql": "SELECT COUNT(*) as count FROM default",
        "os_body": json.dumps({"size": 0, "aggs": {"total": {"value_count": {"field": "_id"}}}})
    },
    {
        "name": "fulltext_search",
        "o2_sql": "SELECT * FROM default WHERE match_all('Connection refused') LIMIT 50",
        "os_body": json.dumps({"size": 50, "query": {"match_phrase": {"log": "Connection refused"}}})
    },
    {
        "name": "complex_query",
        "o2_sql": "SELECT COUNT(*) FROM default WHERE match_all('ERROR') AND match_all('payment-service')",
        "os_body": json.dumps({"size": 0, "query": {"bool": {"must": [{"match": {"log": "ERROR"}}, {"match": {"log": "payment-service"}}]}}, "aggs": {"error_count": {"value_count": {"field": "_id"}}}})
    },
]

results = []

for q in queries:
    name = q["name"]
    print(f"  Running: {name} ...", end="", flush=True)

    o2_times = []
    os_times = []

    for i in range(ITERS):
        o2_t = time_query(o2_query, q["o2_sql"])
        os_t = time_query(os_query, q["os_body"])
        o2_times.append(o2_t)
        os_times.append(os_t)

    o2_p50 = percentile(o2_times, 50)
    o2_p95 = percentile(o2_times, 95)
    o2_p99 = percentile(o2_times, 99)
    os_p50 = percentile(os_times, 50)
    os_p95 = percentile(os_times, 95)
    os_p99 = percentile(os_times, 99)

    print(f" O2 p50={o2_p50}ms p95={o2_p95}ms | OS p50={os_p50}ms p95={os_p95}ms")
    results.append({
        "name": name,
        "o2_p50": o2_p50, "o2_p95": o2_p95, "o2_p99": o2_p99,
        "os_p50": os_p50, "os_p95": os_p95, "os_p99": os_p99
    })

# Output as JSON for easy parsing
output_file = "/tmp/query_results.json"
with open(output_file, "w") as f:
    json.dump(results, f, indent=2)
print(f"\nQuery results saved to {output_file}")

# Also print parseable lines
for r in results:
    print(f"QDATA|{r['name']}|{r['o2_p50']}|{r['o2_p95']}|{r['o2_p99']}|{r['os_p50']}|{r['os_p95']}|{r['os_p99']}")
