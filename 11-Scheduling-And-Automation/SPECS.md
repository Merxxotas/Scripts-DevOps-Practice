# EventOps - Technical Specification

## 1. System Overview
EventOps is a cross-platform, event-driven automation daemon written in Python. It replaces traditional time-based schedulers (like Cron or Task Scheduler) by reacting to system and network events in real-time. Instead of polling, EventOps executes shell commands exactly when an event occurs, ensuring immediate response and low resource usage.

## 2. Architecture
- **Daemon Process (`eventops.py`)**: The central engine that runs as a long-lived background process. It loads the configuration, initializes logging, and spawns concurrent listener threads.
- **Rule Engine**: Parses the `rules.json` configuration file, validates the schema, and routes incoming events to their corresponding executable actions.
- **Triggers**:
  - `file_watcher.py`: A filesystem monitor using `watchdog` to detect file modifications, creations, or deletions.
  - `webhook_server.py`: A lightweight HTTP server using the built-in `http.server` that listens for HMAC-authenticated incoming HTTP POST requests.
- **Executor**: A handler that safely spawns sub-processes (via `subprocess.run`) to execute the defined shell scripts or commands when a rule is triggered.

## 3. Technology Stack
- **Language**: Python 3.8+
- **Standard Libraries**: `json`, `subprocess`, `threading`, `http.server`, `logging`, `os`, `sys`, `time`
- **External Dependencies**: 
  - `watchdog`: Required for efficient, cross-platform filesystem event monitoring using native OS APIs (inotify, FSEvents, ReadDirectoryChangesW).

## 4. Configuration Schema (`rules.json`)
The system is entirely configured via a single JSON file. This allows for programmatic updates and easy version control.

```json
{
  "rules": [
    {
      "name": "String (Unique identifier for the rule)",
      "type": "Enum('webhook', 'file_change')",
      "endpoint": "String (Required if type=webhook. E.g., '/deploy')",
      "watch_path": "String (Required if type=file_change. E.g., '/var/log/app.log')",
      "action": "String (The shell command or script to execute)"
    }
  ]
}
```

## 5. Component Specifications

### 5.1 Main Daemon (`eventops.py`)
- **Initialization**: 
  - Parses CLI arguments (e.g., `start`).
  - Reads and validates `rules.json` against the required schema.
  - Initializes the central logger (writing to `eventops.log` with timestamp, log level, and message).
- **Execution**: 
  - Starts the Webhook Server in a separate daemon thread.
  - Starts the File Watcher Observer in a separate daemon thread.
  - Keeps the main thread alive via a `try/except KeyboardInterrupt` loop.

### 5.2 Webhook Server (`triggers/webhook_server.py`)
- Inherits from `http.server.BaseHTTPRequestHandler`.
- Binds to `127.0.0.1:8080` by default; `--host` changes the interface. Pass `0.0.0.0` only behind a firewall or reverse proxy.
- **Authentication (fail-closed)**: every POST must carry a valid `X-Hub-Signature-256: sha256=<hex>` header — HMAC-SHA256 of the raw request body keyed by the `EVENTOPS_WEBHOOK_SECRET` environment variable. When the secret is not set, the daemon refuses to start the webhook listener. Signatures are compared in constant time.
- Request bodies are capped at 1 MB and socket reads time out after 30 seconds, so oversized payloads and idle clients are rejected instead of pinning worker threads.
- **Both body framings are accepted**: a declared `Content-Length` and `Transfer-Encoding: chunked`. Webhook senders (GitHub among them) switch to chunked framing once a payload outgrows their in-memory buffer and then send no `Content-Length` at all; the chunked framing is decoded and the HMAC is taken over the payload bytes exactly as received, never over an empty body. The 1 MB cap applies to the decoded size, not to the transfer size.
- **Rejection order is part of the contract**: the signature is verified before rule matching, so an unauthenticated caller cannot probe which endpoints exist. A malformed or truncated chunked body is answered `401` with the generic signature error — the unparseable bytes are never handed to the rule engine.
- **Request Handling (`do_POST`)**:
  1. Reads the body (chunked or `Content-Length`) and enforces the 1 MB cap: over the cap → `413`, malformed framing → `401` (generic signature error), valid body → verify the HMAC signature (`401 Unauthorized` on failure).

  2. Extracts the URI path from the incoming request.
  3. Queries the Rule Engine to see if the path matches any rule with `type="webhook"`.
  4. If a match is found, invokes the `action` via the Executor in a non-blocking thread.
  5. Returns `200 OK` with a JSON success payload.
  6. If no match is found, returns `404 Not Found`.

Only `POST` triggers an action. Python answers `405` for `GET` and leaves the remaining methods
(`PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`) to the stdlib handler's `501 Not Implemented`; Go
answers `405` for every non-`POST` method. That asymmetry is the existing behaviour, documented
rather than hidden.

Python also enforces a second budget on the chunked framing itself (`MAX_BODY_BYTES + 65_536`,
counting chunk headers and trailers). Go caps only the decoded payload through
`http.MaxBytesReader`, so a body whose framing exceeds the Python budget is answered `413` by
Python and `200` by Go. The asymmetry is intentional: Go cannot count framing bytes without
wrapping the connection, and the Python budget bounds a flood of empty chunks that would
otherwise pin a worker thread.

### 5.3 File Watcher (`triggers/file_watcher.py`)
- Inherits from `watchdog.events.FileSystemEventHandler`.
- **Event Handling (`on_modified`)**:
  1. Extracts the path of the modified file.
  2. Checks if the path matches a `watch_path` in any rule with `type="file_change"`.
  3. **Debouncing Mechanism**: Prevents rapid-fire triggers (e.g., a file being saved might trigger 3-5 OS-level modification events in a single millisecond). Implements a 2-second cooldown per rule before it can be triggered again.
  4. Invokes the `action` via the Executor in a non-blocking thread.

### 5.4 Executor Module
- Receives the `action` string and executes it using `subprocess.run(action, shell=True, capture_output=True, text=True)`.
- **Asynchronous Execution**: Uses Python's `threading.Thread` to run the subprocess so that long-running scripts do not block the HTTP server or the filesystem watcher from receiving new events.
- **Logging**: Captures `stdout` and `stderr` from the shell script and pipes them securely into `eventops.log` for auditability.

## 6. Execution Flow Example
1. User runs `python eventops.py start`.
2. `eventops.py` reads `rules.json`.
3. Rule 1 is a webhook on `/deploy`. The `WebhookServer` registers this path.
4. Rule 2 is a file watcher on `/etc/config.ini`. The `watchdog.Observer` begins monitoring this file.
5. GitHub sends an automated POST request to `http://localhost:8080/deploy`, with an `X-Hub-Signature-256` header computed with the same webhook secret configured on both sides.
6. `WebhookServer` catches the request, verifies the HMAC signature and the endpoint, and spawns a thread to run `bash ../9-Automated-Git-Deployment/git_deploy.sh`.
7. The deployment script executes, outputting progress. The Executor captures this output and writes it to `eventops.log`.

## 7. CI/CD Pipeline (Monorepo Segregation)
This project lives inside a larger monorepo. As such, the EventOps CI/CD workflow (`ci-eventops.yml`) is completely segregated from the other scripts.
- **Path-Based Triggering:** The GitHub Action only runs when files inside `11-Scheduling-And-Automation/EventOps/**` are modified.
- **Testing Scope:** Tests and linting run exclusively on the EventOps codebase across Ubuntu, macOS, and Windows matrices.
