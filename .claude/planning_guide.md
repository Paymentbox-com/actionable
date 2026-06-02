# Planning Guide

> How to plan and build features in Actionable. Follow this before writing code.

---

## Planning Workflow

```
UNDERSTAND ──► VALIDATE ──► DESIGN ──► IMPLEMENT
     │              │           │           │
  What problem?   In scope?   Components   TDD
  Which slice?    Phase 1?    Tests        Red→Green→Refactor
  Success =?      Decided?    Risks
```

"In scope" and "decided" both resolve against `docs/origin/plan.md`. Most Phase 1
work is already scoped into the 16-slice plan, and the locked decisions D1–D16 settle
the design questions. If your work doesn't map to a slice or contradicts a locked
decision, **surface it before starting** — the plan is not arbitrary.

---

## User Story Format

```markdown
## User Story
**As a** [persona],
**I want to** [action],
**So that** [benefit].

## Acceptance Criteria
Given [context],
When [action],
Then [expected result].

## Out of Scope
- [What this does NOT do]

## Technical Notes
- [Patterns to follow, implementation hints, relevant slice + decisions]
```

### Example

```markdown
**As a** developer using Actionable,
**I want to** compose an action out of another action with `step Notify, input: %i[invoice]`,
**So that** I reuse the notify pipeline without duplicating its steps.

**Given** `CreateInvoice` declares `step Notify, input: %i[invoice], expose: %i[receipt]`,
**When** I run `CreateInvoice.run(...)` and the build step set `@invoice`,
**Then** `Notify` runs with that invoice, only its `receipt` output is absorbed,
**And** a failure inside `Notify` fails `CreateInvoice` with the child's code/message.

**Out of Scope**: retries or async execution of the nested action (Phase 2).

**Technical Notes**: Slice 8, decisions D3 (`:input`/`:expose`) and D8 (nested
failure propagation). Mirror `Steps::Method`'s skip-guard handling in `Steps::Action`.
```

---

## Pre-Build Checklist

### Scope
- [ ] Falls within Phase 1 scope per `docs/origin/plan.md` (the in/out lists are authoritative).
- [ ] Aligns with the design invariants in `.claude/project_intent.md`.
- [ ] Maps to an existing slice — or has been surfaced as new work.

### Design
- [ ] Locked decisions (D1–D16) are not contradicted.
- [ ] Control flow uses `throw`/`catch` halt, never exceptions (D4).
- [ ] Output/input changes go through the FieldStruct schema, not ad-hoc ivar magic (D6/D7).
- [ ] Anything Rails-specific lives behind `require 'actionable/rails'`; anything
      RSpec-specific behind `require 'actionable/rspec'` (D8, D14). The core stays clean.
- [ ] New class config is inherited and overridable (D2, D9, D10).

### Technical
- [ ] Existing pattern to follow? (sibling step classes, the runner, the result objects).
- [ ] Tests identified (happy path + failure + halt + exception-propagation where relevant)?
- [ ] `require_relative` wired into `lib/actionable.rb` for any new **core** file?
- [ ] New step type implements the `Steps::Base` contract (`run(instance)`, equality, skip guard)?
- [ ] YARD comments on every new public method (params + return) — they feed Sord (D13).

### Risk
- [ ] What could go wrong? Does a raised exception still propagate (not get swallowed)?
- [ ] Does the change keep `result.output` a typed, declared contract?
- [ ] Reversible? (pre-1.0 churn is cheap, but document breaks in CHANGELOG).

---

## Anti-Patterns

| Pattern | Bad | Good |
|---------|-----|------|
| Exception control flow | `raise StopIt` to end a run | `fail!` / `halt!` (throw/catch) |
| Swallowing errors | `rescue Exception` in a step/runner | Let `StandardError` propagate; assert with `and_raise` |
| Magic output | Surface every ivar on the result | Declare `output` fields; only those are exposed |
| Rails creep | `require 'active_record'` in core | Keep it in `actionable/rails` |
| Gold plating | Add retries "while here" | Build exactly the slice |
| Premature abstraction | Generic step framework for one case | Concrete code; extract on the second use |
| Test-after | Code first, tests later | TDD: failing test first |
| Relitigating | Re-debate a locked D-decision mid-build | Surface it explicitly, get a new lock |

---

## Definition of Done

### Code
- [ ] Follows existing patterns (look at sibling files).
- [ ] Uses correct terminology (see glossary in `project_intent.md`).
- [ ] No Rubocop violations (`bundle exec rubocop`).
- [ ] YARD comments on public methods (params + return).
- [ ] `require_relative` added to `lib/actionable.rb` if a new core file was created.

### Testing
- [ ] TDD approach (failing test written first).
- [ ] Behavior-focused tests (see `tdd_guidelines.md`).
- [ ] Happy path + failure + halt + exception-propagation cases as applicable.
- [ ] All tests pass (`bin/rspec`); coverage hasn't regressed (`COVERAGE=1 bin/rspec`).

### Types & Docs
- [ ] `rake sigs:generate` run and the updated `sig/actionable.rbs` committed.
- [ ] `rake sigs:validate` passes; `rake sigs:check` would pass (no staleness).
- [ ] README/USAGE updated if public API changed; doctest examples still pass.
- [ ] CHANGELOG updated for a release-worthy change.

### Commits
- [ ] Atomic commits (one logical change each), conventional format.
- [ ] Tests included with the code they prove; tests pass at every commit.
- [ ] Commit messages explain *why*, not *what*.

---

## Incremental Delivery

Phase 1 is broken into 16 slices in `docs/origin/plan.md`. Each slice is a sequence
of small TDD cycles, each producing an atomic commit. A slice's commit history reads
like a changelog of the feature being built.

**Example: Slice 8 (nested Action step)**

| Step | TDD Cycle | Commit |
|------|-----------|--------|
| 1 | Failing spec: `step Child, input: %i[x]` runs child, threads `x` | (in progress) |
| 2 | Implement `Steps::Action#run`, `:input` threading | `feat: add nested action steps with input/expose` |
| 3 | (optional) extract output-absorption helper | `refactor: extract expose filtering` |

---

## When to Ask for Clarification

Ask (don't assume) when requirements are ambiguous, multiple valid approaches exist
*and the plan doesn't pick one*, scope is unclear, edge cases aren't covered, or a
locked decision (D1–D16) seems to conflict with the request.

```markdown
**Question:** When a plain `fail` is followed by a successful final step, should the
result be Failure or Success?
A) Failure — last `fail`/`succeed` wins; absent a later `succeed`, it stays Failure (D4)
B) Success — completing all steps overrides an earlier soft fail

**Recommendation:** A — D4 locks "last write wins, no auto-override." Flagging because
the request said "complete the run" which could be read as B.
```
