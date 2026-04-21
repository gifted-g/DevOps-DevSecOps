package main

import (
	"fmt"
	"math/rand"
	"strings"
	"time"
)

// ── HTTP Access Logs (nginx combined format) ────────────────────

var (
	httpMethods  = []string{"GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"}
	httpPaths    = []string{"/api/v1/users", "/api/v1/orders", "/api/v1/products", "/api/v1/payments", "/api/v1/inventory", "/api/v2/search", "/api/v2/recommendations", "/health", "/metrics", "/api/v1/auth/login", "/api/v1/auth/logout", "/api/v1/cart", "/api/v1/checkout", "/api/v1/shipping", "/static/js/app.js", "/static/css/main.css", "/api/v1/notifications", "/api/v1/reviews", "/api/v1/wishlist", "/api/v1/coupons"}
	httpStatuses = []int{200, 200, 200, 200, 200, 201, 204, 301, 302, 400, 401, 403, 404, 404, 500, 502, 503}
	userAgents   = []string{
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/119.0.0.0 Safari/537.36",
		"Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/121.0",
		"curl/8.4.0",
		"python-requests/2.31.0",
		"Go-http-client/2.0",
		"PostmanRuntime/7.36.0",
		"Apache-HttpClient/4.5.14 (Java/17.0.9)",
		"okhttp/4.12.0",
	}
	referrers = []string{"-", "https://app.example.com/dashboard", "https://app.example.com/login", "https://www.google.com/", "https://app.example.com/products"}
)

func GenAccessLog(r *rand.Rand) string {
	ip := fmt.Sprintf("10.%d.%d.%d", r.Intn(256), r.Intn(256), r.Intn(256))
	method := httpMethods[r.Intn(len(httpMethods))]
	path := httpPaths[r.Intn(len(httpPaths))]
	status := httpStatuses[r.Intn(len(httpStatuses))]
	size := 100 + r.Intn(50000)
	ua := userAgents[r.Intn(len(userAgents))]
	ref := referrers[r.Intn(len(referrers))]
	duration := r.Float64() * 2.5
	ts := time.Now().Format("02/Jan/2006:15:04:05 -0700")

	return fmt.Sprintf(`%s - - [%s] "%s %s HTTP/1.1" %d %d "%s" "%s" rt=%.3f`,
		ip, ts, method, path, status, size, ref, ua, duration)
}

// ── JSON Structured Application Logs ────────────────────────────

var (
	logLevels = []string{"DEBUG", "DEBUG", "INFO", "INFO", "INFO", "INFO", "WARN", "WARN", "ERROR", "FATAL"}
	services  = []string{"api-gateway", "user-service", "payment-service", "order-service", "inventory-service", "notification-service", "auth-service", "search-service", "recommendation-engine", "shipping-service"}

	appMessages = []string{
		"Request processed successfully",
		"Database query executed",
		"Cache hit for key",
		"Cache miss, fetching from database",
		"User authentication successful",
		"Rate limit threshold approaching",
		"Connection pool exhausted, waiting for available connection",
		"Retry attempt for downstream service",
		"Message published to queue",
		"Message consumed from queue",
		"Health check passed",
		"Configuration reloaded",
		"Batch processing completed",
		"Scheduled task triggered",
		"WebSocket connection established",
		"Circuit breaker state changed to OPEN",
		"Graceful shutdown initiated",
		"TLS certificate rotation completed",
		"Feature flag evaluated",
		"A/B test variant assigned",
	}
)

func GenAppLog(r *rand.Rand) string {
	level := logLevels[r.Intn(len(logLevels))]
	svc := services[r.Intn(len(services))]
	msg := appMessages[r.Intn(len(appMessages))]
	traceID := fmt.Sprintf("%016x%016x", r.Int63(), r.Int63())
	spanID := fmt.Sprintf("%016x", r.Int63())
	ts := time.Now().Format(time.RFC3339Nano)
	thread := fmt.Sprintf("worker-%d", r.Intn(32))
	reqID := fmt.Sprintf("req-%08x", r.Int31())

	return fmt.Sprintf(`{"timestamp":"%s","level":"%s","service":"%s","message":"%s","trace_id":"%s","span_id":"%s","thread":"%s","request_id":"%s","version":"1.%d.%d","host":"pod-%s-%05d","duration_ms":%d}`,
		ts, level, svc, msg, traceID, spanID, thread, reqID,
		r.Intn(10), r.Intn(100),
		svc, r.Intn(99999),
		r.Intn(5000))
}

// ── Error Logs with Stack Traces ────────────────────────────────

type errorTemplate struct {
	exception string
	message   string
	stack     string
}

var errorTypes = []errorTemplate{
	{
		"java.lang.NullPointerException",
		"Cannot invoke method on null object reference",
		"at com.example.service.UserService.getUser(UserService.java:%d)\n\tat com.example.controller.UserController.handleRequest(UserController.java:%d)\n\tat org.springframework.web.servlet.FrameworkServlet.service(FrameworkServlet.java:897)",
	},
	{
		"java.sql.SQLException",
		"Connection refused: connect. Could not establish connection to database server",
		"at com.mysql.cj.jdbc.ConnectionImpl.connectOneTryOnly(ConnectionImpl.java:%d)\n\tat com.mysql.cj.jdbc.ConnectionImpl.createNewIO(ConnectionImpl.java:%d)\n\tat com.example.db.ConnectionPool.acquire(ConnectionPool.java:89)",
	},
	{
		"panic: runtime error",
		"index out of range [5] with length 3",
		"goroutine 42 [running]:\nmain.processItems(0xc000123000, 0x3, 0x5)\n\t/app/internal/processor/items.go:%d +0x1a2\nmain.handleBatch(0xc000456000)\n\t/app/internal/handler/batch.go:%d +0xef",
	},
	{
		"redis.ConnectionError",
		"Error 111 connecting to redis-master:6379. Connection refused.",
		"File \"/app/services/cache_service.py\", line %d, in get_cached_value\n    return self.redis_client.get(key)\n  File \"/usr/local/lib/python3.11/site-packages/redis/client.py\", line %d, in get\n    return self.execute_command(\"GET\", name)",
	},
	{
		"TimeoutError",
		"Operation timed out after 30000ms waiting for response from upstream service",
		"File \"/app/handlers/api_handler.py\", line %d, in call_upstream\n    response = await session.get(url, timeout=30)\n  File \"/usr/local/lib/python3.11/site-packages/aiohttp/client.py\", line %d, in _request\n    raise asyncio.TimeoutError()",
	},
	{
		"org.apache.kafka.common.errors.RecordTooLargeException",
		"The message is 2097152 bytes when serialized which is larger than 1048576",
		"at org.apache.kafka.clients.producer.KafkaProducer.doSend(KafkaProducer.java:%d)\n\tat org.apache.kafka.clients.producer.KafkaProducer.send(KafkaProducer.java:%d)\n\tat com.example.messaging.EventPublisher.publish(EventPublisher.java:123)",
	},
}

func GenErrorLog(r *rand.Rand) string {
	e := errorTypes[r.Intn(len(errorTypes))]
	svc := services[r.Intn(len(services))]
	ts := time.Now().Format(time.RFC3339Nano)
	stack := fmt.Sprintf(e.stack, 100+r.Intn(400), 50+r.Intn(200))

	return fmt.Sprintf(`{"timestamp":"%s","level":"ERROR","service":"%s","exception":"%s","message":"%s","stack_trace":"%s","error_code":"E%04d","correlation_id":"%08x-%04x-%04x-%04x-%012x"}`,
		ts, svc, e.exception, e.message,
		strings.ReplaceAll(strings.ReplaceAll(stack, "\n", "\\n"), "\t", "\\t"),
		1000+r.Intn(9000),
		r.Int31(), r.Int31n(0xffff), r.Int31n(0xffff), r.Int31n(0xffff), r.Int63n(0xffffffffffff))
}

// ── Audit / Security Logs ───────────────────────────────────────

var (
	auditEvents = []string{
		"LOGIN_SUCCESS", "LOGIN_FAILED", "LOGOUT", "PASSWORD_CHANGE",
		"MFA_ENABLED", "MFA_DISABLED", "MFA_CHALLENGE_PASSED", "MFA_CHALLENGE_FAILED",
		"API_KEY_CREATED", "API_KEY_REVOKED", "API_KEY_USED",
		"ROLE_ASSIGNED", "ROLE_REVOKED", "PERMISSION_DENIED",
		"USER_CREATED", "USER_DELETED", "USER_SUSPENDED", "USER_ACTIVATED",
		"DATA_EXPORT_REQUESTED", "DATA_DELETION_REQUESTED",
		"CONFIG_CHANGED", "FIREWALL_RULE_MODIFIED",
		"SUSPICIOUS_ACTIVITY_DETECTED", "BRUTE_FORCE_DETECTED",
		"SESSION_HIJACK_ATTEMPT", "IP_BLOCKED",
	}
	auditUsers     = []string{"admin@corp.com", "devops@corp.com", "alice@corp.com", "bob@corp.com", "charlie@corp.com", "service-account-ci", "service-account-deploy", "root", "api-gateway-svc", "monitoring-svc"}
	auditSources   = []string{"web-portal", "mobile-app", "cli-tool", "api-client", "admin-console", "sdk-python", "sdk-java", "terraform"}
	auditOutcomes  = []string{"SUCCESS", "SUCCESS", "SUCCESS", "FAILURE", "DENIED"}
	auditCountries = []string{"US", "GB", "DE", "JP", "IN", "BR", "AU", "CA", "FR", "SG"}
)

func GenAuditLog(r *rand.Rand) string {
	event := auditEvents[r.Intn(len(auditEvents))]
	user := auditUsers[r.Intn(len(auditUsers))]
	source := auditSources[r.Intn(len(auditSources))]
	outcome := auditOutcomes[r.Intn(len(auditOutcomes))]
	ip := fmt.Sprintf("10.%d.%d.%d", r.Intn(256), r.Intn(256), r.Intn(256))
	ts := time.Now().Format(time.RFC3339Nano)
	sessionID := fmt.Sprintf("sess-%012x", r.Int63())
	country := auditCountries[r.Intn(len(auditCountries))]

	return fmt.Sprintf(`{"timestamp":"%s","event_type":"AUDIT","event":"%s","actor":"%s","source":"%s","outcome":"%s","ip_address":"%s","session_id":"%s","country":"%s","user_agent":"%s","resource":"/org/%d/resource/%d","details":{"attempt":%d,"mfa_used":%v}}`,
		ts, event, user, source, outcome, ip, sessionID, country,
		userAgents[r.Intn(len(userAgents))],
		1+r.Intn(100), 1000+r.Intn(9000),
		1+r.Intn(5), r.Intn(2) == 1)
}

// ── Metric-Style Logs ───────────────────────────────────────────

var (
	metricNames = []string{
		"http_request_duration_ms", "http_request_size_bytes", "http_response_size_bytes",
		"db_query_duration_ms", "db_connection_pool_active", "db_connection_pool_idle",
		"cache_hit_ratio", "cache_evictions_total", "cache_memory_bytes",
		"queue_depth", "queue_consumer_lag", "queue_processing_time_ms",
		"cpu_usage_percent", "memory_usage_bytes", "disk_io_read_bytes",
		"gc_pause_duration_ms", "gc_collections_total", "goroutine_count",
		"error_rate_per_minute", "request_rate_per_second", "active_connections",
	}
	metricEndpoints = []string{"/api/users", "/api/orders", "/api/products", "/api/payments", "/api/search", "/api/auth", "/api/cart", "/api/shipping"}
	metricMethods   = []string{"GET", "POST", "PUT", "DELETE"}
	metricRegions   = []string{"us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"}
)

func GenMetricLog(r *rand.Rand) string {
	metric := metricNames[r.Intn(len(metricNames))]
	svc := services[r.Intn(len(services))]
	ts := time.Now().Format(time.RFC3339Nano)
	endpoint := metricEndpoints[r.Intn(len(metricEndpoints))]
	method := metricMethods[r.Intn(len(metricMethods))]
	region := metricRegions[r.Intn(len(metricRegions))]
	instance := fmt.Sprintf("i-%08x", r.Int31())

	var value float64
	switch {
	case strings.Contains(metric, "duration"):
		value = r.Float64() * 5000
	case strings.Contains(metric, "bytes"):
		value = float64(r.Intn(10485760))
	case strings.Contains(metric, "ratio"):
		value = r.Float64()
	case strings.Contains(metric, "percent"):
		value = r.Float64() * 100
	case strings.Contains(metric, "count") || strings.Contains(metric, "total"):
		value = float64(r.Intn(100000))
	default:
		value = float64(r.Intn(10000))
	}

	return fmt.Sprintf(`{"timestamp":"%s","type":"metric","name":"%s","value":%.2f,"service":"%s","tags":{"endpoint":"%s","method":"%s","region":"%s","instance":"%s","env":"production"},"unit":"%s"}`,
		ts, metric, value, svc, endpoint, method, region, instance,
		guessUnit(metric))
}

func guessUnit(metric string) string {
	switch {
	case strings.Contains(metric, "_ms"):
		return "milliseconds"
	case strings.Contains(metric, "_bytes"):
		return "bytes"
	case strings.Contains(metric, "_percent"):
		return "percent"
	case strings.Contains(metric, "_ratio"):
		return "ratio"
	default:
		return "count"
	}
}
