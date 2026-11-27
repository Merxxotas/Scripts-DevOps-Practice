"""Disposable, offline checks for the Lab 1 shell."""

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    os.name == "nt", reason="Lab shell requires Bash on Unix"
)
HELPER = Path(__file__).resolve().parents[2] / "docs/labs/webhook_lab_shell.sh"
BASH = shutil.which("bash")
WORKSPACE_CHECKS = r"""
printf "%s\n" "$PWD" &&
test "$(stat -c %a webhook.secret 2>/dev/null || stat -f %Lp webhook.secret)" = 600 &&
test "$(stat -c %a . 2>/dev/null || stat -f %Lp .)" = 700 &&
test -s webhook.secret &&
test -s rules.json
"""


@pytest.fixture(autouse=True)
def remove_fixture_directory(tmp_path):
    yield
    shutil.rmtree(tmp_path)


def run(script, cwd, env=None):
    return subprocess.run(
        [BASH, "-c", script, "test", str(HELPER)],
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        timeout=10,
        check=False,
    )


def test_private_workspace_and_caller_state(tmp_path):
    existing = tmp_path / "webhook.secret"
    existing.write_bytes(b"existing fixture bytes")
    existing.chmod(0o640)
    before = existing.stat()
    script = r"""
export EVENTOPS_WEBHOOK_SECRET=caller-fixture LAB=caller BODY=caller
umask 027
sign() { :; }
trap ':' USR1
before=$(pwd); oldtrap=$(trap -p USR1); oldfunc=$(declare -f sign)
bash "$1" bash -c __WORKSPACE_CHECKS__ || exit
[ "$PWD" = "$before" ] && [ "$(umask)" = 0027 ] &&
[ "$EVENTOPS_WEBHOOK_SECRET" = caller-fixture ] && [ "$LAB" = caller ] &&
[ "$BODY" = caller ] && [ "$(trap -p USR1)" = "$oldtrap" ] &&
[ "$(declare -f sign)" = "$oldfunc" ]
"""
    script = script.replace("__WORKSPACE_CHECKS__", shlex.quote(WORKSPACE_CHECKS))
    result = run(script, tmp_path)
    assert result.returncode == 0, result.stderr
    workspace = Path(result.stdout.strip())
    assert not workspace.exists()
    assert existing.read_bytes() == b"existing fixture bytes"
    after = existing.stat()
    assert (after.st_mode, after.st_ino, after.st_mtime_ns) == (
        before.st_mode,
        before.st_ino,
        before.st_mtime_ns,
    )


def test_rules_secret_and_second_terminal_signing(tmp_path):
    script = r"""
bash "$1" bash -c '
  python3 -c "import json; print(json.dumps(json.load(open(\"rules.json\"))))"
  bash -c '\''export EVENTOPS_WEBHOOK_SECRET="$(<webhook.secret)"; printf "%s" "{}" | openssl dgst -sha256 -hmac "$EVENTOPS_WEBHOOK_SECRET" -hex'\''
  python3 -c "import hashlib,hmac; s=open(\"webhook.secret\",\"rb\").read(); print(hmac.new(s,b\"{}\",hashlib.sha256).hexdigest())"
'
"""
    result = run(script, tmp_path)
    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    rules = json.loads(lines[0])["rules"]
    assert [(rule["name"], rule["endpoint"]) for rule in rules] == [
        ("Health Alert Webhook", "/alert"),
        ("Deployment Webhook", "/deploy"),
    ]
    assert all(rule["type"] == "webhook" and rule["action"] for rule in rules)
    assert lines[1].split()[-1] == lines[2]


def test_distinct_paths_and_reassigned_lab_cleanup(tmp_path):
    outside = tmp_path / "do not delete"
    outside.mkdir()
    (outside / "marker").write_text("safe")
    env = dict(os.environ, OUTSIDE=str(outside))
    script = r"""
for x in 1 2; do
  bash "$1" bash -c 'printf "%s\n" "$PWD"; LAB=$OUTSIDE; exit 7'
  [ "$?" = 7 ] || exit 1
done
"""
    result = run(script, tmp_path, env)
    assert result.returncode == 0, result.stderr
    paths = [Path(line) for line in result.stdout.splitlines()]
    assert len(set(paths)) == 2
    assert all(not path.exists() for path in paths)
    assert (outside / "marker").read_text() == "safe"


def test_allocation_failure_and_relative_tmpdir_with_cdpath(tmp_path):
    relative = tmp_path / "temporary space"
    relative.mkdir()
    env = dict(os.environ, TMPDIR="temporary space", CDPATH=str(tmp_path))
    result = run('bash "$1" bash -c \'printf "%s\\n" "$PWD"\'', tmp_path, env)
    assert result.returncode == 0, result.stderr
    workspace = Path(result.stdout.strip())
    assert workspace.parent == relative
    assert not workspace.exists()
    env["TMPDIR"] = "missing directory"
    failed = run('bash "$1" bash -c "exit 0"', tmp_path, env)
    assert failed.returncode != 0
    assert failed.stdout == ""
    assert list(relative.iterdir()) == []


def test_setup_failure_cleans_workspace(tmp_path):
    tools = tmp_path / "tools"
    tools.mkdir()
    fake = tools / "openssl"
    fake.write_text("#!/bin/sh\nexit 1\n")
    fake.chmod(0o755)
    parent = tmp_path / "workspaces"
    parent.mkdir()
    env = dict(
        os.environ, PATH=f"{tools}{os.pathsep}{os.environ['PATH']}", TMPDIR=str(parent)
    )
    result = run('bash "$1" bash -c "exit 0"', tmp_path, env)
    assert result.returncode != 0
    assert result.stdout == ""
    assert list(parent.iterdir()) == []


@pytest.mark.parametrize(
    "damage",
    [
        "chmod 644 webhook.secret",
        "chmod 755 .",
        ": > webhook.secret",
        ": > rules.json",
    ],
    ids=["secret-mode", "workspace-mode", "empty-secret", "empty-rules"],
)
def test_workspace_assertions_reject_damaged_fixtures(tmp_path, damage):
    child = f"{damage} || exit; {WORKSPACE_CHECKS}"
    script = 'bash "$1" bash -c ' + shlex.quote(child)
    env = dict(os.environ, TMPDIR=str(tmp_path) + "/")
    result = run(script, tmp_path, env)
    assert result.returncode == 1, result.stderr
    workspace = Path(result.stdout.strip())
    prefix = "Lab workspace: "
    assert result.stderr.startswith(prefix)
    diagnostic_path = result.stderr.removeprefix(prefix).removesuffix("\n")
    assert result.stderr == f"{prefix}{diagnostic_path}\n"
    assert "\n" not in diagnostic_path
    assert Path(diagnostic_path) == workspace
    assert workspace.is_absolute()
    assert not workspace.exists()
