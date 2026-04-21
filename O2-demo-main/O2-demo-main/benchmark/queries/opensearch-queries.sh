#!/usr/bin/env bash
# OpenSearch query functions for benchmarking
# Each function runs a single query via the OpenSearch REST API

OS_HOST="${OS_HOST:-localhost}"
OS_PORT="${OS_PORT:-9200}"

_os_search() {
  local body="$1"
  curl -s "http://${OS_HOST}:${OS_PORT}/logstorm/_search" \
    -H "Content-Type: application/json" \
    -d "$body"
}

# Query 1: Simple keyword search for "ERROR"
run_os_query_keyword_search() {
  _os_search '{
    "size": 100,
    "query": {
      "match": {
        "log": "ERROR"
      }
    }
  }'
}

# Query 2: Field filter — level=ERROR in log content
run_os_query_field_filter() {
  _os_search '{
    "size": 100,
    "query": {
      "bool": {
        "must": [
          {"match": {"log": "ERROR"}},
          {"match": {"log": "level"}}
        ]
      }
    }
  }'
}

# Query 3: Time range query — last 5 minutes
run_os_query_time_range() {
  _os_search '{
    "size": 200,
    "sort": [{"@timestamp": {"order": "desc", "unmapped_type": "date"}}],
    "query": {
      "match_all": {}
    }
  }'
}

# Query 4: Aggregation — count by time buckets
run_os_query_aggregation() {
  _os_search '{
    "size": 0,
    "aggs": {
      "logs_over_time": {
        "date_histogram": {
          "field": "@timestamp",
          "fixed_interval": "30s"
        }
      }
    }
  }'
}

# Query 5: Full-text search — specific error message
run_os_query_fulltext_search() {
  _os_search '{
    "size": 50,
    "query": {
      "match_phrase": {
        "log": "Connection refused"
      }
    }
  }'
}

# Query 6: Complex query — multi-field filter + aggregation
run_os_query_complex_query() {
  _os_search '{
    "size": 0,
    "query": {
      "bool": {
        "must": [
          {"match": {"log": "ERROR"}},
          {"match": {"log": "payment-service"}}
        ]
      }
    },
    "aggs": {
      "error_count": {
        "value_count": {
          "field": "_id"
        }
      }
    }
  }'
}
