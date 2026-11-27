#!/usr/bin/env bash
# Run the lab in a private, temporary child shell; never source this file.
set -eu
umask 077

base=${TMPDIR:-/tmp}
case $base in
    /*) ;;
    *) base=$PWD/$base ;;
esac
workspace=$(mktemp -d "$base/eventops-lab1.XXXXXXXX") || exit 1
readonly workspace
cleanup() { rm -rf -- "$workspace"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

cd -- "$workspace"
export EVENTOPS_WEBHOOK_SECRET
EVENTOPS_WEBHOOK_SECRET=$(openssl rand -hex 32)
[ -n "$EVENTOPS_WEBHOOK_SECRET" ] || exit 1
printf '%s' "$EVENTOPS_WEBHOOK_SECRET" > webhook.secret
cat > rules.json <<'JSON'
{
  "rules": [
    {
      "name": "Health Alert Webhook",
      "type": "webhook",
      "endpoint": "/alert",
      "action": "echo '[ALERT] System health check triggered!' >> alert.log"
    },
    {
      "name": "Deployment Webhook",
      "type": "webhook",
      "endpoint": "/deploy",
      "action": "echo '[DEPLOY] Automated build initiated.' >> deploy.log"
    }
  ]
}
JSON
printf 'Lab workspace: %s\n' "$workspace" >&2
if [ "$#" -gt 0 ]; then
    "$@"
else
    bash --noprofile --norc -i
fi
