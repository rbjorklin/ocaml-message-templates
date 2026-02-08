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

- [ ] Choose log levels: Development=`Debug`, Production=`Information`
- [ ] Configure log rotation (Daily recommended)
- [ ] Set up multiple sinks: Console + File + JSON
- [ ] Enable correlation IDs for distributed tracing
- [ ] Review PII handling (no passwords/tokens)
- [ ] Test error scenarios (disk full, permissions)
- [ ] Configure circuit breakers for async logging

---

## Performance Tuning

### Benchmarks

**Template Rendering:**
- PPX with 2 variables: ~755ns
- PPX with format specifiers: ~1.1μs
- Printf simple: ~59ns

**Sinks:**
- Null sink: ~46ns
- Console sink: ~4.2μs (I/O bound)

**Operations:**
- Create event: ~45ns
- Event to JSON: ~1.1μs
- Context property: ~10ns

### Timestamp Caching

```ocaml
Timestamp_cache.set_enabled false
```

- With caching: ~50ns per timestamp
- Without caching: ~200ns per timestamp

### Running Benchmarks

```bash
dune exec benchmarks/benchmark.exe -- -ascii -q 0.5
```

### Optimization Strategies

1. Use `Information` or `Warning` minimum level for high volume
2. Filter at sink level, not logger level
3. Use async logging for > 1000 events/sec
4. Avoid large context properties
5. Use async sink queue for high-volume file logging

### Sync vs Async

**Synchronous:**
```ocaml
let logger =
  Configuration.create ()
  |> Configuration.write_to_file "app.log"
  |> Configuration.build
```

Use for: < 100 events/sec, guaranteed durability

**Asynchronous:**
```ocaml
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

Use for: > 1000 events/sec, cannot tolerate I/O blocking

### Buffer Sizes

```ocaml
Log.flush ()  (* Force flush to disk *)
```

### File Rolling

- `Infinite`: Single file (`app.log`)
- `Daily`: `app-20260131.log`
- `Hourly`: `app-2026013114.log`

Use `Daily` for most production workloads.

---

## Resource Management

### File Descriptors

```bash
ulimit -n 4096
```

systemd:
```ini
[Service]
LimitNOFILE=65535
```

### Disk Space

Logrotate:
```bash
/var/log/myapp/*.log {
    daily
    rotate 30
    compress
    create 644 appuser appgroup
}
```

### Memory Usage

| Component | Memory |
|-----------|--------|
| Logger | ~1 KB |
| Context property | ~100 bytes |
| Async queue (10k) | ~10 MB |
| Circuit breaker | ~500 bytes |

---

## Security

### PII Redaction

```ocaml
(* Don't log: *)
Log.information "Login" [("password", `String password)]  (* BAD *)
Log.information "Login" [("username", `String username)] (* GOOD *)
```

### Log Permissions

```bash
mkdir -p /var/log/myapp
chown appuser:appgroup /var/log/myapp
chmod 640 /var/log/myapp/*.log
```

### Environment Variables

```ocaml
let safe_vars = ["APP_ENV"; "APP_VERSION"; "HOSTNAME"] in
List.iter (fun var ->
  match Sys.getenv_opt var with
  | Some value -> Log.debug "Env {var}={value}" [("var", `String var); ("value", `String value)]
  | None -> ()
) safe_vars
```
```

---

## Monitoring

### Health Checks

```ocaml
let health_check () =
  match Log.get_logger () with
  | None -> Error "Logger not configured"
  | Some _ ->
      if Log.is_enabled Level.Information then Ok "Healthy"
      else Error "Logging disabled"
```

### Metrics

```ocaml
let metrics = Metrics.create () in
Metrics.record_event metrics ~sink_id:"file" ~latency_us:1.5;

match Metrics.get_sink_metrics metrics "file" with
| Some m ->
    Printf.printf "Events: %d, Dropped: %d, P95: %.2fμs\n"
      m.events_total m.events_dropped m.latency_p95_us
| None -> ()
```

### Async Queue

```ocaml
let depth = Async_sink_queue.get_queue_depth queue in
let stats = Async_sink_queue.get_stats queue in
if not (Async_sink_queue.is_alive queue) then
  Alert.send "Queue thread died!"
```

### Circuit Breaker

```ocaml
match Circuit_breaker.get_state circuit with
| Closed -> ()  (* Normal *)
| Open -> Alert.send "Circuit open"
| Half_open -> ()  (* Testing *)
```

### JSON Output

```ocaml
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

Query: `jq 'select(.["@l"] == "Error")' /var/log/app.clef.json`

---

## Troubleshooting

### Logs Not Appearing

```ocaml
match Log.get_logger () with
| None -> print_endline "Logger not set!"
| Some _ -> ()

if Log.is_enabled Level.Debug then
  print_endline "Debug enabled"
```

### Disk Full

```ocaml
let disk_usage () =
  let stats = Unix.statvfs "/var/log" in
  float_of_int stats.f_bavail /. float_of_int stats.f_blocks

if disk_usage () < 0.10 then
  print_endline "Disk full - logging to console"
```

### Permission Denied

```bash
chown -R appuser:appgroup /var/log/myapp/
chmod 755 /var/log
```

### Performance Issues

```ocaml
match Metrics.get_sink_metrics metrics "file" with
| Some m when m.events_dropped > 0 ->
    Printf.printf "Dropped: %d\n" m.events_dropped
| Some m when m.latency_p95_us > 1000.0 ->
    Printf.printf "High latency: %.0fμs\n" m.latency_p95_us
| _ -> ()
```

Expected: Sync console ~50k/s, Sync file ~10k/s, Async ~100k/s

---

## Quick Reference

### Production Configuration

```ocaml
let production_logger () =
  Configuration.create ()
  |> Configuration.information
  |> Configuration.write_to_console
       ~colors:(Unix.isatty Unix.stdout)
       ~stderr_threshold:Level.Error
       ()
  |> Configuration.write_to_file
       ~rolling:File_sink.Daily
       "/var/log/app/app.clef.json"
  |> Configuration.write_to_file
       ~rolling:File_sink.Daily
       ~output_template:"{timestamp} [{level}] {message}"
       "/var/log/app/app.log"
  |> Configuration.build
```

### High-Volume Async

```ocaml
let high_volume_logger () =
  let file_sink = File_sink.create ~rolling:File_sink.Daily "/var/log/app/app.log" in
  let queue = Async_sink_queue.create
    { Async_sink_queue.default_config with
      max_queue_size = 50000;
      flush_interval_ms = 50;
      batch_size = 100;
      back_pressure_threshold = 40000;
      error_handler = (fun exn -> Printf.eprintf "Log error: %s\n" (Printexc.to_string exn));
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
  |> Configuration.warning
  |> Configuration.write_to async_sink
  |> Configuration.build
```

### Emergency

```ocaml
let null_logger =
  Configuration.create ()
  |> Configuration.write_to_null ()
  |> Configuration.build
in
Log.set_logger null_logger
```
