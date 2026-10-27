# Lab 3 — Exit Codes and Guardrails

**Goal:** Verify exit codes and safety guardrails.

## Steps (Bash)

```bash
# Guardrail refusal
/path/to/log_rotate.sh -f /etc/passwd -m 0; echo "exit=$?"   # 1

# Missing file
/path/to/log_rotate.sh -f /no/such/file.log; echo "exit=$?"   # 1

# Bad argument
/path/to/log_rotate.sh -f /tmp/x.log -m abc; echo "exit=$?"   # 1

# No-op success
f=$(mktemp); /path/to/log_rotate.sh -f "$f"; echo "exit=$?"    # 0
```

## Expected
- Protected/missing/invalid inputs exit 1.
- A within-threshold run exits 0 with "No rotation needed".