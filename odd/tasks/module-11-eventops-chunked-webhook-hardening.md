# Module 11 — EventOps chunked-body parity + webhook secret hardening

Branch: fix/module11-eventops-chunked-webhook-hardening
Delivery strategy: ask-on-risk (PR stays open for GitHub Copilot review; **no merge** until the user decides)
Test runner: `uv run pytest` (EventOps) · `go test ./...` (EventOps-Go) · `ruff check` + `ruff format --check` · `go vet`

## Specs

Source: user request 2026-11-09 (L1, L3). User quoted verbatim in the Log; specs below restate the
request without adding requirements. Assumptions are marked **assumption**.

S1 — Chunked bodies are signed correctly (Python). `_read_body()` currently reads only
`Content-Length`; a request with `Transfer-Encoding: chunked` and no `Content-Length` yields
`content_length = 0`, so the HMAC is computed over an empty body and a correctly signed request is
rejected with `401`. Fix: when the request is chunked, decode the RFC 7230 chunked framing from
`socket`/`rfile` and verify the HMAC over the decoded payload bytes exactly as received (no
re-serialisation, no UTF-8 round-trip). The 1 MB cap (`MAX_BODY_BYTES`) applies to the decoded body
as well as to a declared `Content-Length`.

S2 — Chunked bodies signed correctly (Go). Go is verified, not assumed: `io.ReadAll(http.MaxBytesReader)`
already de-chunks, so a chunked request with a valid signature returns `200`. One test pins that
contract so a future refactor cannot regress it.

S3 — Malformed chunked framing is rejected generically (both languages). A chunked body whose framing
is invalid (bad chunk size, missing CRLF terminator, truncated stream) must produce `401` with the
generic `Missing or invalid signature` message — never a crash, never a 500, never a raw parsers
exception. The malformed payload must not reach the rule engine.

S4 — Body cap enforced identically on both paths (both languages). A decoded body over 1 MB returns
`413` with `Request body too large or invalid` (Python today) / `Request body too large or unreadable`
(Go today). Existing message strings are unchanged — additive behaviour only. A `Content-Length` over
the cap must be rejected without reading the body (Python today: already the case; Go: `MaxBytesReader`
already caps, behaviour verified by test).

- S5 — 401 vs 200 status contract, explicitly tested per language.
- valid signature + registered endpoint → `200` + action dispatched;
- missing header, bad hex, wrong secret, tampered body → `401`;
- valid signature + unknown endpoint → `404` (not `200`, not `401`);
- `GET` → `405`; other methods (`PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`) → `501` from the stdlib
  handler in Python, while Go answers `405` for every non-`POST` method. The docs state the per-language
  behaviour instead of claiming a uniform verdict. Widening the Python handler to answer every non-POST
  method with `405` is **not** part of this change: it would alter an existing response code nobody asked
  to change (recorded as an advisory).
The ordering is part of the contract: signature is verified **before** rule matching, so an
unauthenticated caller cannot probe which endpoints exist.

S6 — LAB1 secret file is not world-readable. `docs/labs/LAB1_WEBHOOK_AUTOMATION.md` currently does
`echo "$EVENTOPS_WEBHOOK_SECRET" > webhook.secret`, which under a typical umask `022` produces mode
`0644`. Fix: create it under `umask 077` and `chmod 600` explicitly, with a one-line *why* (the file
signs webhooks; a readable copy lets any local user forge triggers). Add `webhook.secret` to the lab's
cleanup note. No secret value is ever printed or committed.

S7 — Docs in the same PR. `SPECS.md` §5.2 (request handling gains the chunked path and the rejection
order), `README.md` (how to trigger still says `curl --data` — note that chunked is accepted),
`docs/SCENARIOS.md`, LAB1, `docs/ARCHITECTURE_COMPARISON.md`, wiki `02`/`03`/`04`, `CHANGELOG.md`,
`MODULES.md`. GitHub Wiki is synced **manually** after merge (AGENTS.md §9) — user decision.

S8 — Test-first. RED observed before implementation: one RED test per rule above, asserting status,
body payload and whether the action ran. Existing behaviour that shares changed code (signed `200`,
`401` variants, `404`, `405`, fail-closed startup without a secret) keeps a regression test. Suites:
`python -m pytest` in `EventOps/`, `go test ./...` in `EventOps-Go/`. Scratch data under `mktemp -d`,
never inside the worktree.

S9 — Lint clean. `ruff check .` and `ruff format --check .` in `EventOps/`; `go vet ./...` and
`gofmt -l .` empty in `EventOps-Go/`.

S10 — Delivery. Branch from `main` @ `a2ea1f0`, test-first, one PR, CI green. **The PR stays open**:
the maintainer expects GitHub Copilot review suggestions, and each suggestion is triaged with the
user before it is taken or declined (L3). No merge, no `--admin` in this session unless the user
explicitly asks. RDD assess → preflight STATUS → consent relayed to the user → reviewers → ack;
receipts bind to bytes, so any post-assessment fix re-rolls the candidate.

S11 — Risk. `Risk: item 3` for every commit in this batch: the 401 → 200 verdict for chunked requests
is an observable HTTP contract that webhook senders (GitHub above its payload threshold) depend on,
and the rejection ordering of unauthenticated callers is part of that contract. Independent verifier
runs after the change's own checks, per the item-3 escalation.

Assumption (not requested, recorded so it can be rejected): the Python chunked decoder is written
against the stdlib only — no new runtime dependency — because `requirements.txt` is a shipped
artifact and adding a parser library would be a supply-chain change beyond this request.

## Tasks

- [x] T1: Feature document + Engram mirror + branch from clean `main`. S10. route: inline
- [x] T2: Python RED — raw-socket suite: chunked signed → 200, split chunks → 200, empty signed chunked → 200, signature-over-empty rejected, malformed framing → 401, over-cap → 413, exactly-at-cap → 200. RED observed: 6 failed / 6 passed. S1, S3, S4, S5. route: inline
- [x] T3: Python implementation to GREEN — RFC 7230 decoder (`read_chunked_body`), cap on decoded size, `_BodyTooLarge` for 413 vs malformed → 401. 38 passed. S1, S3, S4. route: inline
- [x] T4: Go RED — raw-socket suite pins the already-correct chunked path and exposes the real gap: malformed framing and truncated bodies both answered `413`. RED observed: 2 failed / 6 passed. S2, S3, S4, S5. route: inline
- [x] T5: Go implementation to GREEN — `errors.As(*http.MaxBytesError)` separates 413 (too big) from every other read error (framing untrustworthy → 401). `go test ./...` all green. S3, S4. route: inline
- [x] T6: LAB1 secret hardening — `umask 077` + explicit `chmod 600` + why + cleanup step. Verified by running the whole lab end to end (perms `600`, 200/200/401/404/200). S6. route: inline
- [x] T7: Lint clean — `ruff check`, `ruff format --check`, `go vet`, `gofmt -l`. S9. route: inline
- [x] T8: Docs — SPECS, README, SCENARIOS, ARCHITECTURE_COMPARISON, wiki 02/03/04, CHANGELOG, MODULES. S7. route: inline
- [ ] T9: Independent verifier over S1–S9. S11. route: delegated
- [ ] T10: Delivery — PR opened with CI green, Copilot suggestions triaged with the user, **no merge**. S10. route: inline
- [x] T11: macOS over-cap test robustness — RED reproduced (`BrokenPipeError` under a forced 4 KB send buffer), fix sends the first chunk + oversized size line then reads the 413. S4, S8. route: inline
- [x] T12: Copilot second-round hardening — trailer fields validated, socket timeout mapped to 401, `Transfer-Encoding` restricted to exactly `chunked`, wire-budget asymmetry documented + Go test. S3, S4. route: inline

## Log

L1 (verbatim, 2026-11-09): "Retomo Scripts-DevOps-Practice en máquina nueva (git clone fresco, sin Engram).
Repo: https://github.com/Merxxotas/Scripts-DevOps-Practice.git → /root/Scripts-Bash-Powershell_DevOps (o tu path).
Estado bueno: main @ a2ea1f0 (2026-11-09). Módulos 7,8,9 cerrados (PR #59, #60, #62, #64 --admin --rebase, ODD + RDD APPROVED). Feature doc cerrado en odd/tasks/module-9-git-deploy-failure-safety.md (L6). Wiki sincronizado @ 7dc583c. Sin PRs abiertos.
Invariantes: ODD (Specs S# / Tasks T# / Log L#, test-first RED→GREEN, Risk: item N, Conventional Commits sin Co-Authored-By), RDD ON opt-out, rama por tanda desde main, merge por PR con CI verde, wiki sync manual post-merge (AGENTS.md §9).
Siguiente: EventOps Módulo 11 — chunked 401 vs 200 + LAB1 secret chmod 600 (detalle arriba). Leé AGENTS.md y odd/METHODOLOGY.md, explorá y proponé enfoque con feature doc antes de tocar código."

L2 (verbatim, 2026-11-09): "Si, dale, empecemos a trabajar. Cuando hagas el PR, dejalo ahí un momento (es decir, no hagas el merge si todo salió bien por parte de los pipelines). Esto es porque espero que github copilot haga sus sugerencias, para que las revises y trabajemos sobre esas sugerencias, si tomarlas o no."

L3 (verbatim, 2026-11-09): "1. Cuál detalle? No te entiendo.
2. El scope debe incluir todo: Python, el chunk malformado y el cap en Go"
  Reading: (a) the "detalle arriba" from L1 never arrived in the session — the scope is the one the
  operator derived from the code and the user confirmed with "Si, dale". (b) The full scope is
  authorized: Python chunked path, malformed chunked framing, and the Go body cap. New decision from
  L2: the PR stays open for GitHub Copilot review; triage of its suggestions is a shared step with the
  user; no merge in this delivery.

L4 (2026-11-09): Ground truth verified before the first write. `main @ a2ea1f0`, clean tree, 0 open
PRs, RDD `on (decided by global)`, repo already cloned at
`/home/merxxcloud/Projects/Scripts-DevOps-Practice`. Code findings: Python `_read_body()` honours only
`Content-Length` (`webhook_server.py:48-61`) → chunked requests sign an empty body and get `401`;
Go `io.ReadAll(http.MaxBytesReader)` de-chunks already → `200`, so the gap is a Python/Go parity
break, not a shared bug. Signature is verified before rule matching on both sides, so the
"endpoint exists" oracle is already closed. LAB1 line 54 writes `webhook.secret` with the default
umask → `0644`. Environment: `uv` absent on this host (CI installs it), `python3` 3.12.3, `go` 1.22.2
with `GOTOOLCHAIN=auto` downloading `go1.26.5` from `go.mod` — first build is slow, not broken.

L5 (2026-11-09): Baseline before any change: Python 22 passed, ruff clean; `go vet`/`go test ./...`
green, `gofmt` clean. Host has no `uv` and no `python3.12-venv` (ensurepip missing), so the suite runs
in a scratch venv bootstrapped with get-pip under `/tmp/user/1002/opencode/` — outside the worktree,
never committed. Go resolves `go1.26.5` through `GOTOOLCHAIN=auto`.

L6 (2026-11-09): RED observed. Python: the first draft used `urllib` with `Transfer-Encoding: chunked`,
but CPython's HTTP client does not actually frame the body that way, so the test was lying — replaced by
a raw-socket suite (`tests/test_webhook_chunked.py`). Real RED: 6 failed / 6 passed. Go: raw-socket
suite (`pkg/triggers/webhook_raw_test.go`) showed the chunked-signed path already green and the real
gap — malformed framing and truncated bodies both answered `413`. RED: 2 failed / 6 passed.

L7 (2026-11-09): GREEN. Python `read_chunked_body()` (RFC 7230, size-line cap, trailer skip, decoded-size
cap) + `_BodyTooLarge` separating 413 from malformed-framing 401 → 38 passed. Go: `errors.As` on
`*http.MaxBytesError` separates the two verdicts → `go test ./...` green. Two empirical findings recorded
because they shaped the design: (a) `http.Server` cannot report a client that stops mid-chunk — it waits
on the connection instead of erroring, so the truncated case is driven through the handler with a reader
that ends before the terminating chunk; (b) answering 401 without draining makes `http.server` skip its
`shutdown(SHUT_WR)`, so half the clients hang — the handler now sets `close_connection` on a chunked
decode failure, and the raw client reads exactly `Content-Length` instead of waiting for EOF.

L8 (2026-11-09): LAB1 verified end to end in a throwaway workspace against the real daemon: secret mode
`600`, signed `/alert` 200, signed `/deploy` 200, unsigned 401, signed unknown endpoint 404, chunked
signed 200, both action files written, cleanup removes the secret. Port 8080 was busy on this host
(unrelated service), so the verification ran on 18080; the lab text keeps 8080 as documented.

L9 (2026-11-09): Independent verifier returned S2/S3/S4/S6/S8/S9 MET, S1 **NOT MET** with two real
blockers, S5 NOT MET as a doc-scope claim. All three accepted, none of the verifier's proposed test code
taken verbatim — the probes were rewritten against the public interface plus the decoder's own contract.
B1: `read_chunked_body` gated only on accumulated payload, so a flood of zero-size chunks added no bytes
and never tripped the cap — measured 11 MB accepted against a 1 MB cap, no response, one worker thread
pinned. Fix: a separate wire budget (`MAX_CHUNKED_WIRE_BYTES = MAX_BODY_BYTES + 65_536`) counting framing
bytes and trailers too. B2: `int(size_field, 16)` is looser than RFC 7230 `1*HEXDIG` — it accepts `1_0`,
`0x10` and `+a`, which Go rejects with 401, so the two implementations diverged on the same bytes. Fix:
explicit charset check before conversion. New suite `tests/test_webhook_chunked_limits.py` attacks the
decoder directly; RED observed for both fixes by temporarily reverting each one (flood: "decoder read past
its own budget"; non-hex: `1_0` and `0x10` accepted), then GREEN at 47 passed. A1 (PUT/DELETE/PATCH/HEAD/
OPTIONS answer 501, not 405) reproduced independently on both baseline and current: pre-existing, so the
docs were corrected to state what the code does rather than widening the handler — changing an existing
response code is not in this request. A2 (`webhook.secret` not gitignored) accepted: the lab now writes
that file, so `.gitignore` covers it.

L10 (2026-11-09): Verifier scratch left at `/tmp/user/1002/opencode/verify-scratch.HQJE32` and my own
venv/scripts in the same directory; all outside the worktree, none committed.

L11 (2026-11-09): macOS CI red on `test_chunked_body_over_cap_returns_413` — `BrokenPipeError` at
`tests/test_webhook_chunked.py:61` (`sock.sendall`) on all three macos-26 jobs; Ubuntu and Windows green.
Root cause: the server answers 413 and closes while the client is still sending the 1 MB body; Linux
loopback buffers absorb the whole write, so the test only fails where the send blocks (macOS). RED
reproduced deterministically on Linux with a forced 4 KB `SO_SNDBUF` (`/tmp/opencode/repro_brokenpipe.py`):
`BrokenPipeError: [Errno 32] Broken pipe`, and the 413 response was still readable (227 bytes). Fix: the
server rejects on the declared chunk size before reading the payload, so the test now sends the first
chunk plus the oversized size line and reads the 413, instead of racing the early close with a full 1 MB
send. GREEN: 47 passed, ruff clean; the fixed body also passes under the forced 4 KB buffer
(`/tmp/opencode/repro_fixed.py`). Scratch scripts live in `/tmp/opencode`, outside the worktree.

L12 (2026-11-09): GitHub Copilot review (17:55) returned 8 suggestions; all verified against the code and
accepted by the user, one by one. Two were code hardening: `_read_chunk_size` accepted whitespace-padded
size lines (` 1 `, `1 `, `\t1`) and a bare-LF terminator, and the trailer section accepted a bare LF, all
of which Go rejects. RED observed (5 new decoder tests failed, 9 passed), fix requires CRLF and parses the
size without trimming → 52 passed, ruff clean. Six were doc corrections: the ROADMAP Phase 7 heading was
restored; SPECS, the feature doc and wiki 02 now state that Python answers 501 for non-GET methods while Go
answers 405 for every non-POST method; the CHANGELOG count was corrected 38 → 47; wiki 04 gained the
chunked-body/rejection contract. The PR description's Risk section was missing and was added.

L13 (2026-11-09): Copilot re-review (18:54, effort Lite) on `211c551` found 4 medium issues in code that
had not changed since the first review; all verified against the code and accepted by the user.
(1) Python enforces a wire budget on the chunked framing that Go does not: documented as an intentional
asymmetry in SPECS, wiki 02 and here, and pinned by `TestRawChunkedWireBudgetAsymmetry` (Go answers 200
for a 200 KB payload whose framing exceeds the Python budget; Go rejects trailers over 64 KB, so the
asymmetry is pinned with many small chunks instead). (2) The trailer loop accepted any CRLF line: it now
requires a valid header field. (3) A socket timeout escaped `do_POST` without a response: it now maps to
the generic 401. (4) `Transfer-Encoding` accepted any list containing `chunked`: it now requires exactly
`chunked` and rejects other codings. RED observed for (2)-(4) (3 new tests failed), GREEN at 55 passed;
Go suite, `go vet` and `gofmt` clean.
