# ODD — Organic Driven Development (repository methodology)

> **Read this only when the task is large or the protocol itself is in question.** The seven-phase
> protocol ships with the agent harness. This file records the **repository-local** rules that
> specialise it — it is the expanded form of [`AGENTS.md` §2](../AGENTS.md).
>
> **Companion:** [`AGENTS.md`](../AGENTS.md) holds the invariants and the router;
> [`CONTRIBUTING.md`](../CONTRIBUTING.md) holds the contributor-facing summary.

---

## The seven phases, specialised for this repository

| Phase | Repository-local rule |
| :--- | :--- |
| **Authorize** | Investigation, explanation, review, audit and planning are **read-only** unless implementation was explicitly requested. Ambiguous intent → one question, then stop. |
| **Explore** | Inspect existing code first, proportionately. Do not explore files you will read anyway before writing inline. |
| **Resolve uncertainty** | Research only for a named uncertainty. One focused question for a genuine product decision, then stop and wait. |
| **Classify** | Small vs large by the **resume test** — could someone finish from the original request plus `git diff`? Never by file count, line count or todo length. |
| **Track** | Large work only: `odd/tasks/<feature-name>.md` plus an Engram mirror. Small work creates no durable artifacts. |
| **Implement** | Task by task, handed off **by reference** (document, task, `S#`), never by paraphrase. Observe RED → GREEN → REFACTOR. |
| **Close** | Report the verified outcome, every failed, skipped or pending check, and one `Risk:` line (`AGENTS.md` §2.6). |

---

## How ODD relates to the module artifacts (SDD)

This is the part that trips people up, so be explicit:

| | **ODD (process)** | **Module artifacts (deliverable)** |
| :--- | :--- | :--- |
| Question answered | *How do we get this built safely?* | *What exactly did we build, and how is it used?* |
| Lifetime | Per feature, per session | Per module, permanent |
| Content | Numbered `S#` specs from the **actual request**, task breakdown, risk lines, evidence log | `SPECS.md`, `ROADMAP.md`, `CODESTYLE.md`, `README.md`, `docs/` |
| Written when | Immediately before the first write, not weeks in advance | As the module is developed |

**Rule of thumb:** ODD governs *how the work happens*; `SPECS.md` / `ROADMAP.md` govern *what the
module is*. A module still ships `SPECS.md` and `ROADMAP.md` — they are the module's public contract
with a human reader. But you no longer write a 200-line specification **before** anyone has looked
at the code; ODD lets the specification crystallize from the real request as the work lands.

**Module contract (unchanged, still mandatory):** every module folder ships its own `SPECS.md`,
`ROADMAP.md`, `CODESTYLE.md`, `README.md`, tests, and `docs/`. See [`AGENTS.md` §3](../AGENTS.md).

---

## The feature document

Large work only, created **automatically before the first source write** — no permission prompt.

```
odd/tasks/<feature-name>.md          # the specification subagents read, by reference
```

Fixed section order, stable content first, growing log last:

| Section | Contents |
| :--- | :--- |
| *Header* | Two or three lines: objective, branch, delivery strategy, test runner. |
| `## Specs` | Numbered `S1..Sn` **quoting the user's exact strings, commands, error messages and examples verbatim**. Never reworded, never padded with unrequested requirements, assumptions marked as assumptions. |
| `## Tasks` | One line per task: ID, linked `S#`, route (inline or delegated), status, commit identity or RED/GREEN evidence. |
| `## Log` | The logbook. `L1` holds the user's original request **verbatim**; later corrections, evidence, rationale and progress are appended. |

A requirement change appends its verbatim Log entry, rewrites only the affected `S#`, and reopens
only its linked task. Accepted user, review or verification changes update affected intent and TODOs
automatically; findings alone never authorize scope expansion, and business scope changes still
require user authorization. Check a task off only after its outcome and checks were observed —
checkboxes grant no approval or receipt.

The Engram mirror lives under topic `odd/<feature-name>/tasks`, scoped to this project, and stores the
full current document plus its repository-relative locator. If Engram is unavailable, preserve local
progress and mark the mirror pending — never claim success. On resume, read the real file *and* the
full observation, reconcile them, then continue the next unfinished task.

---

## Task size

Small when **all three** hold:

1. **Understood** — the outcome is specified, what and where to change is known, and no product or
   design decision is open; provable within one bounded read batch (at most 3 calls, ~10k tokens).
2. **Contained risk** — it touches no high-risk item (`AGENTS.md` §2.6).
3. **Resumable from the diff** — if the session stopped now, someone could finish the work from the
   original request and `git diff` alone.

Large only when the resume test fails: several sessions, waiting on something external, separate
deliverables, or requirements too long to survive a compaction. File count, changed lines and todo
length never decide size.

| | Small | Large |
| :--- | :--- | :--- |
| Route | Direct inline | Inline **or** delegated |
| Feature document | None | `odd/tasks/<feature>.md` + Engram mirror |
| Commits | Only if asked | Work-unit commits on a feature branch |
| Engram mirror | Optional | Required |

---

## Test-first policy

Applies to **behaviour changes** when a runnable deterministic test and a clear expected outcome
exist.

- **Observe RED** before implementing, **implement GREEN**, then refactor while tests stay green.
- **One RED test per requested rule**, asserting *every* observable effect — output, exit code,
  persisted data — through the **public interface**, not internals.
- **For every existing command or option the change touches**, add one test proving the previous
  behaviour still holds; add no other cases. An existing behaviour counts as *touched* when it shares
  code you changed (shared options, parsers, helpers, validation). The presence of a test framework
  alone does **not** establish applicability.
- For passive documentation, an unavailable runner, or no meaningful runnable RED: **explain the
  exception** and run proportionate functional or structural checks.
- **Never invent RED/GREEN evidence or a runner.** Record what was actually observed.

---

## Routing and delegation

**Small understood changes stay inline** — read, edit, run the focused test and the suite. Delegate a
writer only for a named reason: **parallelism** (two or more independent units with disjoint edit
surfaces, each clearly heavier than starting a subagent) or the **long-session context backstop**.
Never for size, a large task alone, file count or a price ratio.

| Trigger | Fires when | Action |
| :--- | :--- | :--- |
| Ask | One genuine product decision is open | Ask one question, then stop and wait |
| Mapping | Understanding exceeds the inline budget | One read-only explorer (~2k tokens, `path:line` evidence) + one parent spot check |
| Verification | The change is high-risk (`AGENTS.md` §2.6) | Independent verifier after the change's own checks |
| Tracking | The task is large | Feature document + mirror + work-unit commits |
| Writer | A named reason exists | One bounded writer per unit — parallelism or the context backstop |
| Preparation | A write is delegated | Delegate the reading that prepares it too |
| Output budget | Parent shell output grows | Keep it to counts, `--stat`, `tail` or summaries |
| Route declaration | Large work | Record the route per task in the feature document |

**Parallel writers.** Work in another repository goes in a fresh worktree based on that repository's
main. Parallel units in the same local repository share the tree only with declared disjoint edit
surfaces; the parent owns git; no writer runs a repository-wide formatter, generator or install; a
shared file has one owner or the parent edits it at the end; and one seam check runs at the end.

---

## Related

- [`AGENTS.md`](../AGENTS.md) — invariants, module contract, CI model, known gotchas.
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — contributor-facing workflow and PR checklist.
