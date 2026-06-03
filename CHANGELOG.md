# Changelog

## [Unreleased]

### Tooling

- The repo is now a single-plugin Claude Code marketplace
  (`.claude-plugin/{plugin.json,marketplace.json}`), so the bundled skill installs
  via `/plugin marketplace add Paymentbox-com/actionable` +
  `/plugin install actionable@actionable` (the skill still ships in the gem for a
  no-marketplace copy). Mirrors the field_struct agent-harness setup.

## [1.2.1] - 2026-06-03

### Tooling

- The `rake docs:check` commit guard (decision D19) now detects a `git commit`
  invocation from the command itself rather than a prefix gate, so a compound
  `git add -A && git commit …` can no longer slip past the pre-commit hook. No
  library changes.

## [1.2.0] - 2026-06-03

Phase-2 ergonomics and adapters (decision D19), from real-world use fitting
Actionable into a polymorphic ingestion endpoint. All additive and
backward-compatible.

### Added

- **`fail_with(source, code: :invalid, message: nil)` / `fail_with!`** — record a
  `Failure` that absorbs an arbitrary FieldStruct's validation errors mid-step
  (the mechanism `:invalid_input` / `:invalid_output` use internally, now exposed
  as a verb via the shared `Failure#absorb_errors_from`).
- **`Result#to_h`, `#status`, `#to_api_h(index:, id_field:)`** — plain-Hash and
  HTTP/batch-element views of a result, so controllers don't hand-map the shape.
- **`Action.run_each(enumerable) { |item| run_args }`** — run the action once per
  item, collecting a `BatchResult` (Enumerable) with `all_ok?` / `any_failure?` /
  `partial?`, `successes` / `failures` / `skips`, and `to_api_h`. Items run
  independently.
- **`input_for(:discriminator) { on value, Shape; default Shape }`** — pick the
  input schema at run time from a discriminator value (typed polymorphic input);
  an unmatched value with no `default` is `Failure(:invalid_input)`. Backed by the
  shared `Actionable::ValueMatch` (also used by `case_step`).
- **`require 'actionable/job'`** — a framework-agnostic background-job helper:
  `Actionable::Job.disposition(result)` maps a result to `:ack` / `:retry` /
  `:discard`, and `Actionable::Job::Mixin` (included into a Sidekiq worker or
  ActiveJob job) runs an action in `perform` and raises `RetryableFailure` for a
  retryable failure.

### Changed

- **`skip` / `skip!` accept `**output` kwargs** (symmetric with `succeed`),
  captured best-effort and never validated — so an idempotent hit can return the
  existing record's data.
- **`measure :sampled, rate:`** — a third measurement mode recording history on a
  fraction of runs (rate between 0 and 1) for low-overhead production
  observability, alongside `:all` and `:none`.

## [1.1.0] - 2026-06-03

Developer-experience improvements (decision D18): fail loudly on misconfiguration
and make actions self-describing.

### Added

- `Actionable::Action.describe` — a structured summary (name, input/output field
  metadata, ordered steps with type, hooks, measure mode, transaction config) so
  humans and agents can understand an action without reading its source.
- `Actionable::DefinitionError` for misconfigured actions.

### Changed

- A reserved `output` field name — one that shadows a result attribute
  (`code`/`message`/`output`/`history`/`errors`) or a reserved instance variable
  (`result`/`input`) — now raises `DefinitionError` when declared, instead of
  silently returning `nil` or failing deep in the runner.
- A declared step whose method isn't implemented now raises a clear
  `DefinitionError` (naming the action and method) at run start, instead of a
  cryptic `NoMethodError`.

## [1.0.0] - 2026-06-03

First feature-complete cut of the clean-slate rebuild.

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
