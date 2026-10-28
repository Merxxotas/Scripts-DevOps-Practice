# Scenarios — Find and Kill High-CPU Processes

## Scenario 1: No high-CPU processes

```bash
./kill_high_cpu.sh
# → "No processes exceeding 50% CPU." exit 0
```

## Scenario 2: Dry run

```bash
./kill_high_cpu.sh --dry-run
# → lists candidates with [DRY RUN], no signal, exit 0
```

## Scenario 3: Interactive kill

```bash
./kill_high_cpu.sh -t 80
# → prompts per candidate (y/n)
```

## Scenario 4: Auto-kill

```bash
./kill_high_cpu.sh -t 80 --auto-kill
# → kills all candidates, exit 0 (or 2 on failure)
```

## Scenario 5: Force (SIGKILL)

```bash
./kill_high_cpu.sh -t 90 --auto-kill --force
```

## Scenario 6: Guardrails

```bash
# PID 1, self, parent and kernel threads are never targeted.
```

## Scenario 7: Audit log

```bash
./kill_high_cpu.sh --auto-kill --audit-log /tmp/khc.audit
```