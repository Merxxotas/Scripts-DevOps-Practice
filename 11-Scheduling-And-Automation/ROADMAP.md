# EventOps - Development Roadmap

This roadmap follows Spec Driven Development (SDD) based on `SPECS.md`. It breaks down the technical architecture into actionable, sequential implementation steps.

## Phase 1: Foundation & Configuration
- [x] **Project Setup:** Create the base directory structure (`eventops/`, `eventops/triggers/`).
- [x] **Dependencies:** Create `requirements.txt` and add the `watchdog` library.
- [x] **Rule Engine:** Write the logic to parse, validate, and load `rules.json`.
- [x] **Logging:** Initialize the central logging system to record events to `eventops.log` with appropriate timestamps and log levels.

## Phase 2: Executor Module
- [x] **Subprocess Handler:** Build the function that accepts an `action` string and runs it using `subprocess.run(shell=True)`.
- [x] **Asynchronous Execution:** Wrap the subprocess execution in `threading.Thread` to ensure long-running scripts do not block the main daemon or triggers.
- [x] **Output Capture:** Pipe both `stdout` and `stderr` from the executed scripts directly into the central logger for auditability.

## Phase 3: Webhook Server Trigger
- [x] **Server Initialization:** Create `triggers/webhook_server.py` using Python's built-in `http.server`.
- [x] **Routing Logic:** Implement the `do_POST` method to extract the URI path.
- [x] **Rule Matching:** Query the Rule Engine to check if the incoming path matches any `webhook` rule in `rules.json`.
- [x] **Execution & Response:** If a match is found, trigger the Executor and return a `200 OK` JSON payload; otherwise, return `404 Not Found`.

## Phase 4: File Watcher Trigger
- [x] **Watcher Initialization:** Create `triggers/file_watcher.py` implementing `watchdog.events.FileSystemEventHandler`.
- [x] **Event Detection:** Catch `on_modified` events and extract the exact file path.
- [x] **Rule Matching:** Query the Rule Engine to see if the modified file matches a `watch_path` in `rules.json`.
- [x] **Debouncing Mechanism:** Implement a 2-second cooldown dictionary to prevent multiple fast OS-level modifications from triggering the action multiple times.
- [x] **Execution:** Pass the valid, debounced events to the Executor.

## Phase 5: Daemon Integration & Finalization
- [ ] **Main Loop:** Wire up `eventops.py` to start both the Webhook Server and the File Watcher as background daemon threads.
- [ ] **Graceful Shutdown:** Implement `try/except KeyboardInterrupt` to cleanly terminate the threads and close logs.
- [ ] **End-to-End Testing:** Create a dummy `rules.json` and a simple bash script. Fire a webhook and modify a file to ensure both triggers successfully route through the Executor and generate logs.
- [ ] **Cleanup:** Remove the obsolete `Linux-(Cron-Jobs).txt` and `Windows-(Task-Scheduler).txt` files.

## Phase 6: CI/CD Pipeline (GitHub Actions - Monorepo Filtered)
- [ ] **Workflow File:** Create `.github/workflows/ci-eventops.yml` in the global repo root.
- [ ] **Path Trigger:** Configure the workflow to trigger ONLY on paths: `'11-Scheduling-And-Automation/EventOps/**'`.
- [ ] **Linting Job:** Add a step to run `flake8` or `black` to enforce rules from `CODESTYLE.md`.
- [ ] **Testing Job:** Create basic tests (e.g., `pytest`) for the Rule Engine and Executor, and run them on Ubuntu, macOS, and Windows matrices.
