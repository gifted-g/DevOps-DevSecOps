# OpenObserve vs OpenSearch — Benchmark Suite

A self-contained benchmarking suite that compares **OpenObserve** and **OpenSearch** performance on a local KIND (Kubernetes-in-Docker) cluster.

The centrepiece is **LogStorm**, a purpose-built Go application that generates high-volume, realistic log traffic across five distinct log types simultaneously.

---

## LogStorm — The Log Generator

LogStorm is a lightweight Go application designed to be *extremely* log-intensive. It runs **5 concurrent goroutines**, each producing a different log format at a configurable rate (default **400 logs/sec per type**), totalling **~2 000 logs/sec** to stdout.

### Why It's Log-Intensive

| Property | Detail |
|---|---|
| **Throughput** | 2 000 logs/sec sustained (configurable via `LOG_RATE` env var) |
| **Concurrency** | 5 parallel goroutines, each with its own random seed |
| **Variety** | 5 distinct log formats with realistic payloads (see below) |
| **Payload size** | 200–800 bytes per line depending on type — stack traces and JSON bodies push volume |
| **Duration** | Runs for 5 minutes by default (`LOG_DURATION` env var), producing **~600 000 logs per run** |

### Five Log Types

1. **HTTP Access Logs** — Nginx combined format with randomised IPs, methods, paths, status codes, user agents, and response times. Simulates a busy API gateway.

2. **Structured Application Logs** — JSON payloads with `level`, `service`, `message`, `request_id`, `trace_id`, `span_id`, and `duration_ms`. Covers 10 microservices and realistic messages (cache misses, retries, circuit breakers, etc.).

3. **Error / Stack-Trace Logs** — Multi-line stack traces mimicking Java, Go, and Python exceptions (NullPointerException, connection refused, timeout, OOM). These are deliberately large and complex to stress log parsing.

4. **Audit Logs** — Security-event JSON with `event_type`, `actor`, `resource`, `ip_address`, `outcome`, and `details`. Covers login, permission changes, API key operations, and data exports.

5. **Metric Logs** — JSON lines with `metric_name`, `value`, `unit`, `tags`, and `host`. Simulates application-level metrics (request latency, queue depth, CPU usage, heap size, active connections, error rate).

### Configuration

| Env Variable | Default | Description |
|---|---|---|
| `LOG_RATE` | `400` | Logs per second *per generator* (total = 5×) |
| `LOG_DURATION` | `300` | Seconds to run before graceful shutdown |

---

## Repository Structure

```
.
├── app/logstorm/          # LogStorm Go application
│   ├── main.go            # Entry point, goroutine orchestration, stats reporter
│   ├── generators.go      # 5 log-type generator functions
│   ├── Dockerfile          # Multi-stage build (golang → scratch)
│   └── go.mod
├── deploy/
│   ├── openobserve/       # StatefulSet, Service, ConfigMap for OpenObserve
│   ├── opensearch/        # StatefulSet, Service for OpenSearch
│   ├── fluentbit/         # DaemonSet + ConfigMap (dual output to both platforms)
│   └── logstorm/          # Deployment manifest
├── infra/
│   ├── kind-config.yaml   # KIND cluster (1 control-plane + 1 worker)
│   └── setup-cluster.sh   # Bootstrap script (cluster, namespaces, metrics-server)
├── benchmark/
│   ├── query_benchmark.py # 6 query types × 10 iterations, p50/p95/p99
│   ├── parse_resources.py # Resource-sample parser
│   └── queries/           # O2 SQL + OS DSL query definitions
├── benchmarking.md        # Full benchmark results
├── run-all.sh             # Master orchestration script
└── .gitignore
```

## Quick Start

### Prerequisites

- Docker Desktop (8 GB RAM allocated)
- [KIND](https://kind.sigs.k8s.io/)
- `kubectl`, `jq`, `python3`

### Run Everything

```bash
./run-all.sh
```

This will:
1. Create a 2-node KIND cluster
2. Build and load the LogStorm container image
3. Deploy OpenObserve, OpenSearch, Fluent Bit, and LogStorm
4. Wait for all pods to become ready

### Run the Benchmark Manually

```bash
# Query latency benchmark (6 queries × 10 iterations)
python3 benchmark/query_benchmark.py
```

### Access the UIs

| Service     | URL                          | Credentials                                   |
|-------------|------------------------------|-----------------------------------------------|
| OpenObserve | http://localhost:5080        | `root@benchmark.local` / `BenchmarkPass123!`  |
| OpenSearch  | http://localhost:9200        | No auth (security plugin disabled)            |

### Teardown

```bash
kind delete cluster --name o2-benchmark
```

---

## Results

See [benchmarking.md](benchmarking.md) for the full report. TL;DR:

- **Memory**: OpenObserve uses **2.5× less RAM** at the same ingestion rate
- **Tail latency**: OpenObserve p95 stays under **82 ms**; OpenSearch spikes to **978 ms**
- **Startup**: OpenObserve boots **30 % faster**
- **Ingestion**: Both sustain **~3 000 logs/sec** — no difference
