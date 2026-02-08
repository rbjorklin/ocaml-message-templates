# Production Deployment Guide

This guide covers best practices for deploying Message Templates in production environments.

## Table of Contents

- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Performance Tuning](#performance-tuning)
- [Resource Management](#resource-management)
- [Security Considerations](#security-considerations)
- [Monitoring & Health Checks](#monitoring--health-checks)
- [Troubleshooting](#troubleshooting)

---

## Pre-Deployment Checklist

Before deploying to production:

- [ ] **Choose appropriate log levels**
  - Development: `Debug` or `Verbose`
  - Production: `Information` or `Warning`

- [ ] **Configure log rotation**
  - Daily rotation recommended for high-volume applications
  - Monitor disk space usage

- [ ] **Set up multiple sinks**
  - Console for container/stdout capture
  - File for persistent logs
  - JSON for structured log aggregation

- [ ] **Enable correlation IDs**
  - Essential for distributed tracing
  - Pass through HTTP headers

- [ ] **Review PII handling**
  - Never log passwords, tokens, or credit cards
  - Use property redaction if needed

- [ ] **Test error scenarios**
  - Disk full
  - Permission denied
  - Network timeouts (for remote sinks)

- [ ] **Configure circuit breakers** (for async logging)
  - Protect against cascade failures
  - Set appropriate failure thresholds

---

## Performance Tuning & Benchmarking

### Performance Baseline

The Message Templates library has been benchmarked using `core_bench`. Here are the key performance characteristics:

**Template Rendering:**
- PPX with 2 variables: ~755ns
- PPX with 5 variables: ~800ns
- PPX with format specifiers: ~1.1μs
- PPX JSON output: ~1.0μs

**vs Alternatives:**
- Printf simple: ~59ns (13x faster)
- String concat: ~34ns (22x faster)
- **Trade-off**: PPX is slower but provides type safety and JSON output

**Sink Performance:**
- Null sink: ~46ns
- Console sink: ~4.2μs (I/O bound)
- Composite sink (3): ~51ns total
- **Finding**: Sink coordination is negligible; console I/O is the bottleneck

**Event Operations:**
- Create event: ~45ns
- Create with 4 properties: ~45ns
- Event to JSON: ~1.1μs
- **Finding**: JSON conversion is the hotspot

**Context Operations:**
- Single property: ~10ns
- Nested (3 levels): ~25ns
- **Finding**: Context overhead is negligible

**Filter Operations:**
- Level filter: ~48ns
- Property filter: ~50ns
- Combined filters: ~60ns
- **Finding**: Filtering is extremely fast

### Timestamp Caching

For high-frequency logging, millisecond timestamp caching is enabled by default:

```ocaml
(* Enabled by default - reduces Ptime.of_float_s overhead *)
(* Disable if you need unique timestamps for every log entry *)
Timestamp_cache.set_enabled false
```

**Performance impact:**
- With caching: ~50ns per timestamp
- Without caching: ~200ns per timestamp
- Effective for logs within the same millisecond

### Running Benchmarks

To measure performance in your environment:

```bash
# Quick benchmark (0.5 second per test)
dune exec benchmarks/benchmark.exe -- -ascii -q 0.5

# Longer benchmark with error estimates
dune exec benchmarks/benchmark.exe -- -ascii -q 2 +time

# View all options
dune exec benchmarks/benchmark.exe -- -help
```

**Common options:**
- `-ascii`: Use ASCII tables (vs Unicode)
- `-q SECS`: Time per benchmark (default: 10s)
- `-cycles`: Show CPU cycles
- `+time`: Show 95% confidence intervals
- `alloc`: Show memory allocation
- `gc`: Show garbage collection

### Performance Optimization Strategies

1. **Template-heavy workloads**
   - Use string concatenation for simple messages
   - Reserve templates for complex structured data
   - Benchmark your specific usage pattern

2. **High-volume logging**
   - Use `Information` or `Warning` minimum level (not `Debug`)
   - Filter at the sink level, not the logger level
   - Use async logging with queue for > 1000 events/sec

3. **Minimize allocations**
   - Avoid creating large context properties
   - Use format specifiers instead of string formatting
   - Clean up context properties promptly

4. **I/O bottlenecks**
   - Console output is ~100x slower than in-memory operations
   - Use async sink queue for high-volume file logging
   - Use `Null_sink` for tests

### Choosing Sync vs Async Logging

**Synchronous (default):**
```ocaml
(* Simple, blocking I/O - good for low-volume logging *)
let logger =
  Configuration.create ()
  |> Configuration.write_to_file "app.log"
  |> Configuration.build
```

**When to use synchronous:**
- Log volume < 100 events/second
- You need guaranteed durability
- Simpler debugging

**Asynchronous (with queue):**
```ocaml
(* Non-blocking enqueue with background flush *)
let file_sink = File_sink.create "app.log" in
let queue = Async_sink_queue.create
  { Async_sink_queue.default_config with
    max_queue_size = 10000;
    flush_interval_ms = 100 }
  (fun event -> File_sink.emit file_sink event)
in
let async_sink =
  { Composite_sink.emit_fn = Async_sink_queue.enqueue queue
  ; flush_fn = (fun () -> Async_sink_queue.flush queue)
  ; close_fn = (fun () -> Async_sink_queue.close queue) }
in

let logger =
  Configuration.create ()
  |> Configuration.write_to async_sink
  |> Configuration.build
```

**When to use async:**
- Log volume > 1000 events/second
- Cannot tolerate I/O blocking
- Background processing acceptable

### Buffer Sizes

File sinks use standard OCaml channel buffering. To control buffering:

```ocaml
(* For immediate durability, flush after critical events *)
Log.information "Payment processed" [("amount", `Float amount)];
Log.flush ()  (* Force flush to disk *)
```

### File Rolling Strategies

| Strategy | Use Case | Example Filename |
|----------|----------|------------------|
| `Infinite` | Low volume, simple setup | `app.log` |
| `Daily` | Production standard | `app-20260131.log` |
| `Hourly` | High volume, detailed analysis | `app-2026013114.log` |

**Recommendation:** Use `Daily` for most production workloads.

---

## Resource Management

### File Descriptor Limits

Each file sink opens one file descriptor:

```bash
# Check current limit
ulimit -n

# Recommended minimum for production
ulimit -n 4096
```

If using systemd:
```ini
# /etc/systemd/system/myapp.service
[Service]
LimitNOFILE=65535
```

### Disk Space Management

**Logrotate configuration:**
```bash
# /etc/logrotate.d/myapp
/var/log/myapp/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 appuser appgroup
    sharedscripts
    postrotate
        # Signal application to reopen logs if needed
        kill -HUP $(cat /var/run/myapp.pid)
    endscript
}
```

**Monitor disk usage:**
```bash
# Set up alerting when > 80% full
df -h /var/log | awk 'NR==2 {if($5+0 > 80) print "WARNING: Log disk > 80%"}'
```

### Memory Usage Patterns

Typical memory overhead:

| Component | Memory Usage |
|-----------|--------------|
| Logger (no context) | ~1 KB |
| Per context property | ~100 bytes |
| Async queue (10k events) | ~10 MB |
| Per circuit breaker | ~500 bytes |

**Best practices:**
- Clean up context properties promptly
- Don't store large values in context
- Monitor async queue depth
- Set appropriate queue size limits

---

## Security Considerations

### PII Redaction

**Never log sensitive data:**
```ocaml
(* BAD - logs password! *)
Log.information "Login attempt" [("password", `String password)]

(* GOOD - only log non-sensitive data *)
Log.information "Login attempt" [("username", `String username)]
```

**Redact sensitive fields:**
```ocaml
(* Manual redaction before logging *)
let sanitize props =
  List.map (fun (k, v) ->
    let lower_k = String.lowercase_ascii k in
    if String.contains lower_k 'password' ||
       String.contains lower_k 'token' ||
       String.contains lower_k 'secret'
    then (k, `String "***")
    else (k, v)
  ) props

Log.information "Request" (sanitize properties)
```

### Log File Permissions

```bash
# Create log directory with restricted permissions
mkdir -p /var/log/myapp
chown appuser:appgroup /var/log/myapp
chmod 755 /var/log/myapp

# Log files should be readable only by owner and group
chmod 640 /var/log/myapp/*.log
```

### Sensitive Data Handling

**Environment variables:**
```ocaml
(* Don't log environment variables that may contain secrets *)
let log_env () =
  let safe_vars = ["APP_ENV"; "APP_VERSION"; "HOSTNAME"] in
  List.iter (fun var ->
    match Sys.getenv_opt var with
    | Some value ->
        Log.debug "Environment {var}={value}"
          [("var", `String var); ("value", `String value)]
    | None -> ()
  ) safe_vars
```

**Correlation IDs and privacy:**
```ocaml
(* Correlation IDs can link user sessions - be careful with retention *)
Log_context.with_correlation_id request_id (fun () ->
  (* All events in this scope tagged with @i field *)
  process_request ()
)
```

---

## Monitoring & Health Checks

### Sink Health Monitoring

```ocaml
(* Check if logger is configured and working *)
let health_check () =
  match Log.get_logger () with
  | None -> Error "Logger not configured"
  | Some logger ->
      if Log.is_enabled Level.Information then
        Ok "Logger healthy"
      else
        Error "Logging disabled"
```

### Metrics and Observability

Use the built-in Metrics module for per-sink monitoring:

```ocaml
(* Create metrics tracker *)
let metrics = Metrics.create () in

(* Record event emission manually or integrate with sinks *)
Metrics.record_event metrics ~sink_id:"file" ~latency_us:1.5;

(* Get sink-specific metrics *)
match Metrics.get_sink_metrics metrics "file" with
| Some m ->
    Printf.printf "Events: %d, Dropped: %d, P95: %.2fμs\n"
      m.events_total m.events_dropped m.latency_p95_us
| None -> ()

(* Export as JSON for monitoring systems *)
let json = Metrics.to_json metrics
```

**Metrics include:**
- Event counts (total, dropped, failed)
- Bytes written
- Latency percentiles (p50, p95)
- Last error timestamp

### Async Queue Monitoring

Monitor async sink queue health:

```ocaml
(* Get queue depth *)
let depth = Async_sink_queue.get_queue_depth queue in
if depth > 1000 then
  Alert.send "Log queue backing up: %d events" depth;

(* Get statistics *)
let stats = Async_sink_queue.get_stats queue in
Printf.printf "Enqueued: %d, Emitted: %d, Dropped: %d, Errors: %d\n"
  stats.total_enqueued
  stats.total_emitted
  stats.total_dropped
  stats.total_errors

(* Check if queue is alive *)
if not (Async_sink_queue.is_alive queue) then
  Alert.send "Log queue thread died!"
```

### Circuit Breaker Monitoring

Monitor circuit breaker state:

```ocaml
(* Check circuit state *)
match Circuit_breaker.get_state circuit with
| Closed -> (* Normal operation *)
| Open -> (* Failing fast - check for issues *)
| Half_open -> (* Testing recovery *)

(* Get statistics *)
let (failures, state, last_failure) = Circuit_breaker.get_stats circuit in
Printf.printf "Failures: %d, State: %s, Last: %.0f\n"
  failures
  (match state with Closed -> "closed" | Open -> "open" | Half_open -> "half_open")
  last_failure
```

### Structured Logging for Monitoring

Use JSON output for log aggregation:

```ocaml
(* Create JSON sink for CLEF output *)
let json_sink_instance = Json_sink.create "/var/log/app.clef.json" in
let json_sink =
  { Composite_sink.emit_fn = (fun event -> Json_sink.emit json_sink_instance event)
  ; flush_fn = (fun () -> Json_sink.flush json_sink_instance)
  ; close_fn = (fun () -> Json_sink.close json_sink_instance) }
in

let logger =
  Configuration.create ()
  |> Configuration.write_to json_sink
  |> Configuration.build
```

Then query with tools like:
- **jq**: `jq 'select(.["@l"] == "Error")' /var/log/app.clef.json`
- **Elasticsearch**: Index CLEF format directly
- **Loki**: Parse JSON streams
- **Datadog/Splunk**: Structured log aggregation

---

## Troubleshooting

### Common Issues

#### Issue: Logs not appearing

**Checklist:**
1. Is the logger configured?
   ```ocaml
   match Log.get_logger () with
   | None -> print_endline "ERROR: Logger not set!"
   | Some _ -> ()
   ```

2. Is the level enabled?
   ```ocaml
   if Log.is_enabled Level.Debug then
     print_endline "Debug logging is enabled"
   ```

3. Are filters blocking events?
   ```ocaml
   (* Temporarily remove filters for debugging *)
   let debug_config =
     Configuration.create ()
     |> Configuration.write_to_console ()
     |> Configuration.build
   in
   Log.set_logger debug_config
   ```

#### Issue: Disk full

**Solution:**
```ocaml
(* Implement disk space check *)
let disk_usage () =
  (* Check available disk space *)
  let stats = Unix.statvfs "/var/log" in
  let available = stats.f_bavail * stats.f_frsize in
  let total = stats.f_blocks * stats.f_frsize in
  float_of_int available /. float_of_int total

let safe_log msg props =
  if disk_usage () > 0.10 then  (* If < 10% free *)
    (* Switch to console only *)
    print_endline ("LOG: " ^ msg)
  else
    Log.information msg props
```

**Alternative with circuit breaker:**
```ocaml
let disk_cb = Circuit_breaker.create ~failure_threshold:1 ~reset_timeout_ms:60000 () in

let logged_write event =
  match Circuit_breaker.call disk_cb (fun () ->
    (* Try to write - will throw if disk full *)
    File_sink.emit sink event
  ) with
  | Some () -> ()
  | None -> (* Circuit open - disk likely full *)
      print_endline "WARNING: Log disk full, logging to console"
```

#### Issue: Permission denied

**Solution:**
```bash
# Check file ownership
ls -la /var/log/myapp/

# Fix permissions
chown -R appuser:appgroup /var/log/myapp/

# Ensure parent directory is writable
chmod 755 /var/log
```

#### Issue: Performance degradation

**Profile logging overhead:**
```ocaml
let benchmark_logging () =
  let start = Unix.gettimeofday () in
  for i = 1 to 10000 do
    Log.information "Test message" [("i", `Int i)]
  done;
  let elapsed = Unix.gettimeofday () -. start in
  Printf.printf "10k logs in %.3f seconds (%.0f logs/sec)\n"
    elapsed (10000.0 /. elapsed)
```

**Expected performance:**
- Sync console: ~50,000 logs/second
- Sync file: ~10,000 logs/second
- Async queue: ~100,000+ logs/second (enqueue only)
- If slower: Check disk I/O, reduce logging volume

**Check metrics:**
```ocaml
(* Look for dropped events or high latency *)
match Metrics.get_sink_metrics metrics "file" with
| Some m when m.events_dropped > 0 ->
    Printf.printf "WARNING: %d events dropped!\n" m.events_dropped
| Some m when m.latency_p95_us > 1000.0 ->
    Printf.printf "WARNING: High latency %.0fμs\n" m.latency_p95_us
| _ -> ()
```

### Debug Mode

Enable verbose internal logging:

```ocaml
(* Enable timestamp caching diagnostics *)
let () =
  (* Set minimum level to Verbose for maximum output *)
  let logger =
    Configuration.create ()
    |> Configuration.verbose
    |> Configuration.write_to_console ()
    |> Configuration.build
  in
  Log.set_logger logger
```

### Performance Diagnostics

```ocaml
(* Measure context overhead *)
let test_context_overhead () =
  let iterations = 1_000_000 in

  (* Without context *)
  let t1 = Unix.gettimeofday () in
  for i = 1 to iterations do
    Log.information "Test" []
  done;
  let without_context = Unix.gettimeofday () -. t1 in

  (* With context *)
  let t2 = Unix.gettimeofday () in
  Log_context.with_property "key" (`String "value") (fun () ->
    for i = 1 to iterations do
      Log.information "Test" []
    done
  );
  let with_context = Unix.gettimeofday () -. t2 in

  Printf.printf "Context overhead: %.2f%%\n"
    ((with_context -. without_context) /. without_context *. 100.0)
```

---

## Production Checklist

```markdown
## Before Deploying
- [ ] Set minimum level to Information or Warning
- [ ] Enable daily log rotation
- [ ] Configure both console and file sinks
- [ ] Set up log aggregation (JSON output)
- [ ] Enable correlation IDs
- [ ] Review all log statements for PII
- [ ] Configure circuit breaker if using async logging

## Infrastructure
- [ ] File descriptor limits >= 4096
- [ ] Disk space monitoring (> 20% free)
- [ ] Log rotation configured
- [ ] Permissions set correctly (640 for files)

## Monitoring
- [ ] Health check endpoint configured
- [ ] Metrics collection enabled
- [ ] Queue depth alerts (if async)
- [ ] Circuit breaker state monitoring
- [ ] Error rate monitoring
- [ ] Disk space alerts

## Security
- [ ] No secrets in logs
- [ ] Log files readable only by owner
- [ ] Correlation IDs don't expose sensitive info
- [ ] Environment-specific data reviewed
```

---

## Quick Reference

### Recommended Production Configuration

```ocaml
let production_logger () =
  Configuration.create ()
  |> Configuration.information  (* Or Warning for very high volume *)
  (* Console for container/stdout capture *)
  |> Configuration.write_to_console
       ~colors:(Unix.isatty Unix.stdout)
       ~stderr_threshold:Level.Error
       ()
  (* Structured JSON for aggregation *)
  |> Configuration.write_to_file
       ~rolling:File_sink.Daily
       "/var/log/app/app.clef.json"
  (* Human-readable for quick debugging *)
  |> Configuration.write_to_file
       ~rolling:File_sink.Daily
       ~output_template:"{timestamp} [{level}] {message}"
       "/var/log/app/app.log"
  |> Configuration.build
```

### High-Volume Async Configuration

```ocaml
let high_volume_logger () =
  (* Create file sink *)
  let file_sink = File_sink.create ~rolling:File_sink.Daily "/var/log/app/app.log" in

  (* Wrap with async queue *)
  let queue = Async_sink_queue.create
    { Async_sink_queue.default_config with
      max_queue_size = 50000;      (* Larger queue for bursts *)
      flush_interval_ms = 50;       (* Faster flush *)
      batch_size = 100;             (* Batch writes *)
      back_pressure_threshold = 40000;  (* Warn at 80% *)
      error_handler = (fun exn ->
        Printf.eprintf "Log error: %s\n" (Printexc.to_string exn));
      circuit_breaker = Some (
        Circuit_breaker.create ~failure_threshold:5 ~reset_timeout_ms:30000 ()
      )
    }
    (fun event -> File_sink.emit file_sink event)
  in

  let async_sink =
    { Composite_sink.emit_fn = Async_sink_queue.enqueue queue
    ; flush_fn = (fun () -> Async_sink_queue.flush queue)
    ; close_fn = (fun () -> Async_sink_queue.close queue) }
  in

  Configuration.create ()
  |> Configuration.warning  (* High volume - only warnings and above *)
  |> Configuration.write_to async_sink
  |> Configuration.build
```

### Emergency Procedures

**If logging is causing issues:**

```ocaml
(* 1. Switch to null sink immediately *)
let null_logger =
  Configuration.create ()
  |> Configuration.write_to_null ()
  |> Configuration.build
in
Log.set_logger null_logger

(* 2. Or flush and close current logger *)
Log.close_and_flush ()
```

---

**Last Updated:** 2026-02-07
**For Version:** 1.0+
