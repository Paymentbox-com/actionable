# Changelog

## [Unreleased]

First feature-complete cut of the clean-slate rebuild (pending the v1.0.0 tag).

### Added

- **Core action model** — `Actionable::Action` with an ordered, inherited `step`
  DSL and an `Actionable::Runner` that runs steps inside `catch(:actionable_halt)`,
  auto-succeeding when no result was recorded.
- **Result value objects** — FieldStruct-backed `Success`, `Failure`, and
  `Skipped`, with `success?`/`failure?`/`skipped?`/`ok?` predicates, structured
  `errors`, and a compact, deterministic `inspect`.
- **Control flow** — `succeed` / `fail` / `skip` (record, continue) and
  `succeed!` / `fail!` / `skip!` / `halt!` (record + halt) via `throw`/`catch`;
  genuine exceptions propagate (no `rescue`).
- **The `:skip` outcome** (decision D17) — a third, first-class result for "nothing
  to do": not a success, not a failure; `on_skip` hook; commits under
  `transactional`; best-effort, unvalidated output.
- **Typed output** — `output do … end` schema; matching ivars captured and coerced,
  `succeed` kwargs overlaid; only a strict success is validated (else
  `Failure(:invalid_output)`); declared fields delegate off the result.
- **Typed input** — `input do … end` schema; `.run` coerces and validates kwargs,
  exposes `input`, and short-circuits to `Failure(:invalid_input)` on bad input.
- **Step types** — method steps, nested action steps (`:input` / `:expose`,
  failure propagation), and `case_step` branching (`==`, `Regexp`, Array
  membership) with `:if` / `:unless` guards.
- **Lifecycle hooks** — `on_success` / `on_failure` / `on_skip` / `always`.
- **History & measurement** — `measure :all` records per-step section/name/timing/
  code and nested history, cascading into nested actions; Oj serialization.
- **Registry** — `Actionable.registry` of all named actions.
- **Optional Rails adapter** (`require 'actionable/rails'`) — `transactional`
  macro (rollback on failure or exception, commit on success/skip) and
  `Actionable::ProxyValidator`.
- **Optional RSpec integration** (`require 'actionable/rspec'`) — the
  `perform_actionable` matcher (`and_succeed` / `and_fail` / `and_skip` /
  `and_raise` + block) and `allow_/stub_actionable_*` helpers.
- **Types & docs** — Sord/RBS/YARD toolchain (`sig/actionable.rbs`,
  `rake sigs:* / docs:* / release:check`), `Actionable::RBS.generate` for user
  actions, and doctested README/USAGE examples.

## [0.1.0] - 2026-06-02

- Initial release
