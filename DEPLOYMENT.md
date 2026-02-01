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

---

## Performance Tuning

### Choosing Sync vs Async Logging

**Synchronous (default):**
```ocaml
(* Simple, blocking I/O - good for low-volume logging *)
let logger =
  Configuration.create ()
  |> Configuration.write_to_file "app.log"
  |> Configuration.create_logger
```

**When to use synchronous:**
- Log volume < 100 events/second
- You need guaranteed durability
- Simpler debugging

**When async will be needed:** (Future feature)
- Log volume > 1000 events/second
- Cannot tolerate I/O blocking
- Heavy computation in log handlers

### Buffer Sizes

File sinks don't currently expose buffer configuration. To control buffering:

```ocaml
(* For immediate durability, flush after critical events *)
Log.information "Payment processed" ["amount", `Float amount];
Logger.flush logger  (* Force flush to disk *)
```

### Batching Configuration

Currently not implemented. Future versions will support:
```ocaml
(* Coming in future release *)
let logger =
  Configuration.create ()
  |> Configuration.with_batching ~max_batch_size:100 ~max_delay_ms:100
  |> Configuration.create_logger
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
| Buffered events | ~1 KB per event |

**Best practices:**
- Clean up context properties promptly
- Don't store large values in context
- Flush periodically in long-running operations

---

## Security Considerations

### PII Redaction

**Never log sensitive data:**
```ocaml
(* BAD - logs password! *)
Log.information "Login attempt" ["password", `String password]

(* GOOD - only log non-sensitive data *)
Log.information "Login attempt" ["username", `String username]
```

**Redact sensitive fields:**
```ocaml
(* Coming in future release - PII redaction *)
let sanitize props =
  List.map (fun (k, v) ->
    if String.lowercase_ascii k |> String.contains 'password'
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
          ["var", `String var; "value", `String value]
    | None -> ()
  ) safe_vars
```

**Correlation IDs and privacy:**
```ocaml
(* Correlation IDs can link user sessions - be careful with retention *)
Log_context.with_correlation_id request_id (fun () ->
  (* All events in this scope tagged with request_id *)
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
      if Logger.is_enabled logger Level.Information then
        Ok "Logger healthy"
      else
        Error "Logging disabled"
```

### Log Volume Metrics

Track log volume for capacity planning:

```ocaml
(* Simple counter using context *)
let log_with_counter level msg props =
  let counter = ref 0 in
  fun () ->
    incr counter;
    if !counter mod 1000 = 0 then
      Log.information "Log statistics"
        ["total_logs", `Int !counter];
    Log.write level msg props
```

### Queue Depth Alerts

Async queues not yet implemented, but planned:

```ocaml
(* Future feature *)
let check_queue_depth () =
  match Async_sink.get_queue_depth () with
  | depth when depth > 1000 ->
      Alert.send "Log queue backing up: %d events" depth
  | _ -> ()
```

### Structured Logging for Monitoring

Use JSON output for log aggregation:

```ocaml
let logger =
  Configuration.create ()
  |> Configuration.write_to_file ~rolling:File_sink.Daily "/var/log/app.json"
  |> Configuration.create_logger
```

Then query with tools like:
- **jq**: `jq 'select(.["@l"] == "Error")' /var/log/app.json`
- **Elasticsearch**: Index CLEF format directly
- **Loki**: Parse JSON streams

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
   let debug_logger =
     {logger with Logger.filters = []}
   ```

#### Issue: Disk full

**Solution:**
```ocaml
(* Implement circuit breaker *)
let disk_usage () =
  (* Check available disk space *)
  let stats = Unix.statvfs "/var/log" in
  let available = stats.f_bavail * stats.f_frsize in
  let total = stats.f_blocks * stats.f_frsize in
  float_of_int available /. float_of_int total

let safe_log msg props =
  if disk_usage () > 0.10 then  (* If < 10% free *)
    (* Switch to console only *)
    Console_io.print "LOG: %s\n" msg
  else
    Log.information msg props
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
    Log.information "Test message" ["i", `Int i]
  done;
  let elapsed = Unix.gettimeofday () -. start in
  Printf.printf "10k logs in %.3f seconds (%.0f logs/sec)\n"
    elapsed (10000.0 /. elapsed)
```

**Expected performance:**
- Sync console: ~50,000 logs/second
- Sync file: ~10,000 logs/second
- If slower: Check disk I/O, reduce logging volume

### Debug Mode

Enable detailed internal logging:

```ocaml
(* Not currently implemented - future feature *)
let () =
  Message_templates.Debug.set_level Verbose;
  Message_templates.Debug.enable ()
```

For now, enable verbose logging:
```ocaml
let logger =
  Configuration.create ()
  |> Configuration.verbose
  |> Configuration.write_to_console ()
  |> Configuration.create_logger
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

## Infrastructure
- [ ] File descriptor limits >= 4096
- [ ] Disk space monitoring (> 20% free)
- [ ] Log rotation configured
- [ ] Permissions set correctly (640 for files)

## Monitoring
- [ ] Health check endpoint configured
- [ ] Log volume alerts set up
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
       "/var/log/app/app.json"
  (* Human-readable for quick debugging *)
  |> Configuration.write_to_file
       ~rolling:File_sink.Daily
       "/var/log/app/app.log"
  |> Configuration.create_logger
```

### Emergency Procedures

**If logging is causing issues:**

```ocaml
(* 1. Switch to null sink immediately *)
Log.set_logger (Configuration.create () |> Configuration.create_logger)

(* 2. Or disable logging entirely *)
let null_logger =
  Configuration.create ()
  |> Configuration.write_to_null ()
  |> Configuration.create_logger
in
Log.set_logger null_logger
```

---

**Last Updated:** 2026-02-01  
**For Version:** 1.0+
