# Changelog

## [Unreleased]

Outcome coverage for test suites (decision D22). Opt-in with
`require 'actionable/rspec/coverage'`; nothing changes for a suite that
doesn't require it.

### Added

- **`Actionable::Coverage`** records every real `.run` of a named action as
  `[class name, outcome, code]`, nested runs and `run_each` included. It hooks
  `Action.run` by prepending onto its singleton class, so an RSpec stub of
  `.run` replaces it and a stubbed result never counts as the action tested.
- **The RSpec stub helpers note their runs** in `Coverage.stubbed` when
  coverage is loaded, so a report can show an outcome that was only ever
  stubbed. They record when the stub answers a call, not when it is set up.
- **`Coverage.expected_outcomes(action)`** lists what an action can end with,
  read from its declarations at run time: `success`, every `declared_failures`
  code, every `declared_skips` code on a gem that has them, and any
  `Coverage.gem_codes` that apply (`:invalid_input` when an input field is
  required, `:invalid_output` when an output field is). `gem_codes` defaults
  to `[]`.
- **`Coverage.actions`** lists the actions to report: named descendants of
  `Coverage.root` (default `Actionable::Action`) that have steps and whose
  name still resolves to them, filtered by `include_prefixes` and
  `exclude_prefixes`. `Coverage.loader` runs first so a host can eager-load.
- **`Coverage::Report`** compares the two: `rows` and `totals` (actions,
  expected outcomes, reached, missing), a text table (`to_s`) of each action's
  never-reached outcomes with a "Stubbed only" column, and `to_json`.
  `Coverage.only_observed = true` reports only actions with a real run, for a
  partial or targeted run.
- **A named baseline of known gaps.** `Coverage.baseline = path` points at a
  committed JSON or YAML file of `{"Action::Name" => [outcome keys]}`. Missing
  outcomes alone never fail; with a baseline, the report fails on a gap the
  baseline doesn't list and on an entry that is covered, no longer declared,
  or names an action that is gone, and its message lists each entry to add
  or remove. `Report#to_baseline` and `#write_baseline` produce the file.

## [1.4.0] - 2026-10-21

Declared skips (decision D21), the skip counterpart of 1.3.0's declared
failures. Additive: an action that declares no skips runs as before, and a
child skip still continues its parent. One edge can reach existing code, listed
under Changed: a skip's `to_h`, `inspect` and `attributes` have a `metadata`
key.

### Added

- **`skips(code, message = nil, **metadata)`** declares a skip code the action
  can end with, plus neutral per-code metadata, the skip counterpart of `fails`
  (decision D21). Declarations are inherited and a subclass can add to them.
  **`declared_skips`** reads them back as `{code => metadata}`, and
  **`skip_declarations`** as `{code => {message:, metadata:}}`.
- **`Skipped#metadata`** (default `{}`): a `skip` or `skip!` with a declared
  code carries its metadata, and its declared message when the call gives none.
  `Skipped#to_h` includes `metadata`.
- **Strict once declared.** An action that declares at least one skip code may
  only skip with declared codes; any other `skip` / `skip!` raises
  `Actionable::DefinitionError` at the call, including the implicit default
  `:skipped`. An action that declares no skips is unchecked, and declared
  failures don't make skips strict. **`allows_skip_code?(code)`** answers
  whether an action may skip with a code.
- **`describe` shows declared skips** as `skips: {code => {message:,
  metadata:}}`, and `describe_text` lists them under `Skips:`, after
  `Failures:`.
- **RSpec support follows the skip declarations.** On an action that declares
  skips, `allow_actionable_skip` / `stub_actionable_skip` build a skip carrying
  the code's declared metadata (and message, when none is given), and they and
  `and_skip` raise `ArgumentError` for a code the action doesn't declare,
  `:skipped` included. `actionable_skip_result` takes `metadata:`.
- **`Actionable::RBS` emits a `skip_code` type alias** for an action that
  declares skips, listing the declared codes, after `failure_code` when both
  are declared.

### Changed

- **`Skipped#to_h` includes `metadata`** (`{}` unless the code is declared),
  so code comparing a skip's `to_h` to an exact Hash sees one more key.
  `Skipped#inspect` and `#attributes` show it too.

## [1.3.0] - 2026-10-21

Declared failures (decision D20). Additive: an action that declares no
failures runs as before. Three edges can reach existing code, listed under
Changed: `metadata` is now a reserved output name, `Failure#to_h` has a
`metadata` key, and a nested failure no longer passes through an overridden
`fail`.

### Added

- **`fails(code, message = nil, **metadata)`** declares a failure code the
  action can end with, plus neutral per-code metadata (arbitrary keywords the
  gem stores and passes through but never interprets). Declarations are
  inherited and a subclass can add to them. **`declared_failures`** reads them
  back as `{code => metadata}`.
- **`Failure#metadata`** (default `{}`): a `fail`, `fail!`, `fail_with` or
  `fail_with!` with a declared code carries its metadata, and its declared
  message when the call gives none. Declaring `:invalid_input` or
  `:invalid_output` attaches metadata to the failures the gem builds itself.
  `Failure#to_h` includes `metadata`.

- **`describe` shows declared failures** as `failures: {code => {message:,
  metadata:}}`, and `describe_text` lists them under `Failures:`.
- **Strict once declared.** An action that declares at least one failure code
  may only fail with declared codes; any other `fail` / `fail_with` raises
  `Actionable::DefinitionError` at the call. Exempt: actions that declare none,
  and the codes the gem emits itself, `Actionable::Action::GEM_FAILURE_CODES`
  (`:invalid_input`, `:invalid_output`).

- **`allows_failure_code?(code)`** answers whether an action may fail with a
  code under those rules.
- **RSpec support follows the declarations.** On an action that declares
  failures, `allow_actionable_failure` / `stub_actionable_failure` build a
  failure carrying the code's declared metadata (and message, when none is
  given), and they and `and_fail` raise `ArgumentError` for a code the action
  doesn't declare. `actionable_failure_result` takes `metadata:`.

- **`Actionable::RBS.generate`** emits a `failure_code` type alias for an
  action that declares failures: the declared codes, then the codes the gem
  emits itself.

### Changed

- **A nested action's failure crosses intact.** `Steps::Action` used to re-fail
  the parent with `fail!(code, message, **errors)`, which dropped anything else
  on the child's failure and let a child error keyed like a keyword of an
  overridden `fail` (pbx's `kind:`) bind to that keyword. The parent now adopts
  the child's code, message, every error, its metadata and its result class
  directly, with the parent's declared metadata for the code filling in keys
  the child didn't set. A host override of `fail` no longer runs for a
  propagated failure.
- `metadata` joins the reserved output field names, since an output field of
  that name would be shadowed on a failure.
- `Failure#to_h` gains a `metadata` key (`{}` when the code isn't declared).

## [1.2.2] - 2026-06-03

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
