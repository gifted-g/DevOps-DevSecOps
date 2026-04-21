package main

import (
	"fmt"
	"math/rand"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

var totalLogsGenerated atomic.Int64

func main() {
	ratePerType := getEnvInt("LOG_RATE", 400)  // logs/sec per generator
	duration := getEnvInt("LOG_DURATION", 300) // seconds (5 min default)

	fmt.Fprintf(os.Stderr, "LogStorm starting: %d logs/sec per type (5 types = %d total), duration=%ds\n",
		ratePerType, ratePerType*5, duration)

	ctx := make(chan struct{})
	var wg sync.WaitGroup

	generators := []struct {
		name string
		fn   func(r *rand.Rand) string
	}{
		{"access", GenAccessLog},
		{"app", GenAppLog},
		{"error", GenErrorLog},
		{"audit", GenAuditLog},
		{"metric", GenMetricLog},
	}

	for _, g := range generators {
		wg.Add(1)
		go func(name string, fn func(r *rand.Rand) string) {
			defer wg.Done()
			runGenerator(name, fn, ratePerType, ctx)
		}(g.name, g.fn)
	}

	// Stats reporter
	wg.Add(1)
	go func() {
		defer wg.Done()
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		start := time.Now()
		for {
			select {
			case <-ticker.C:
				total := totalLogsGenerated.Load()
				elapsed := time.Since(start).Seconds()
				fmt.Fprintf(os.Stderr, "[stats] %d logs generated, %.0f logs/sec avg, elapsed=%.0fs\n",
					total, float64(total)/elapsed, elapsed)
			case <-ctx:
				return
			}
		}
	}()

	// Shutdown on duration or signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	timer := time.NewTimer(time.Duration(duration) * time.Second)
	select {
	case <-timer.C:
		fmt.Fprintf(os.Stderr, "LogStorm: duration reached (%ds), shutting down\n", duration)
	case sig := <-sigCh:
		fmt.Fprintf(os.Stderr, "LogStorm: received signal %v, shutting down\n", sig)
	}

	close(ctx)
	wg.Wait()

	total := totalLogsGenerated.Load()
	fmt.Fprintf(os.Stderr, "LogStorm finished: %d total logs generated\n", total)
}

func runGenerator(name string, fn func(r *rand.Rand) string, ratePerSec int, stop chan struct{}) {
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	interval := time.Second / time.Duration(ratePerSec)
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			line := fn(r)
			fmt.Println(line)
			totalLogsGenerated.Add(1)
		case <-stop:
			return
		}
	}
}

func getEnvInt(key string, defaultVal int) int {
	if v, ok := os.LookupEnv(key); ok {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return defaultVal
}
