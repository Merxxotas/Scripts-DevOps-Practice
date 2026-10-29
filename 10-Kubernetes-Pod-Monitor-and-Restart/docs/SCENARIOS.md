# Scenarios — Kubernetes Pod Monitor and Restart

## Scenario 1 — Basic monitoring

```bash
./k8s_monitor.sh
```

Expected: lists pods, deletes those exceeding threshold, exit 0.

## Scenario 2 — Dry run

```bash
./k8s_monitor.sh --dry-run
```

Expected: lists pods + which would be deleted, no deletion, exit 0.

## Scenario 3 — Custom namespace/selector/threshold

```bash
./k8s_monitor.sh -n production -l app=api -r 5
```

## Scenario 4 — Hard delete

```bash
./k8s_monitor.sh --force
```

## Scenario 5 — kubectl missing

Expected: error message, exit 1.

## Scenario 6 — Audit log

```bash
./k8s_monitor.sh --audit-log /tmp/k8s.log
cat /tmp/k8s.log
```
