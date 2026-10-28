# Lab 3 — Guardrails and Exit Codes

**Goal:** verify the safety contract.

1. Protected app dir:
   ```bash
   ./git_deploy.sh -a /; echo "exit=$?"
   ```
   Expected: exit 1.
2. Invalid branch:
   ```bash
   ./git_deploy.sh -b "bad branch"; echo "exit=$?"
   ```
   Expected: exit 1.
3. Help:
   ```bash
   ./git_deploy.sh -h; echo "exit=$?"
   ```
   Expected: exit 0.