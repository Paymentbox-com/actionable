# Changelog

## [Unreleased]

### Added

- **`Actionable::RBS.generate` types an action's input and output instance
  variables** (generated RBS only; no runtime change). For an action with a
  fixed `input` schema it emits a nested `class InputSchema < ::FieldStruct::Base`
  with a typed reader and writer per input field, `def input: () -> InputSchema`,
  and a `.run` overload `| (InputSchema input) -> ...` beside the keyword form.
  `InputSchema` exists only in RBS (the runtime schema is anonymous), so
  generation raises `ArgumentError` when Ruby already resolves
  `YourAction::InputSchema` (a constant on the action, an ancestor or an
  included module). It also declares each output field as a nullable
  instance variable (`@total: ::Integer?`), so a step that assigns
  `@total = ...` type-checks. **Upgrade note:** the generated RBS now owns
  those instance variables; delete any declaration of them from your own sig
  files, since RBS rejects an instance variable declared twice.

### Fixed

- **`Actionable::RBS.generate` declares the real superclass chain.** An action
  under an intermediate base (`class Codes::DecideMapping < ApplicationAction`)
  was declared `< ::Actionable::Action`, hiding its bases from the type
  checker, and a host that declared the real superclass got
  `NoSuperclassFoundError` / a failing `rbs validate` when the base had no
  signature. The action now names its nearest named superclass, and every
  named ancestor up to `Actionable::Action` is declared first, member-less
  (a typed one with its empty result classes), so the RBS resolves on its own.
  The declarations repeat byte-identically across files and merge. A namespace
  that is a class now opens as `class`, not `module`, which RBS rejected as a
  duplicate declaration.
  **Upgrade note:** if your own sig files declare one of those bases with a
  different superclass (e.g. `class ApplicationAction < ::Actionable::Action`
  while Ruby says otherwise), RBS now reports a superclass mismatch; make your
  declaration match Ruby's ancestry or drop it.

### Changed

- **Optional `.run` keywords are nullable in generated RBS** (`?note: ::String?`): an optional field may be passed `nil` explicitly, and the run succeeds.
- **A required input field with a default is an optional `.run` keyword** (`?amount: ::Integer`), since `run` succeeds without it. An action whose input is chosen by an `input_for` dispatch (including one inherited under a fixed `input`) gets `.run: (*untyped)`, since the dispatch decides the keywords at run time.
- **Requires field_struct >= 0.12.** The generator now takes every field type
  from `FieldStruct::RBS.type_for` instead of its own copy of the mapping, so
  generated action RBS matches `FieldStruct::RBS.generate`. Consumer-visible
  changes to generated RBS: writers on `Output` and the per-code output
  classes are typed `(T? value) -> T?` instead of `(untyped value) ->
  untyped`; scalar array elements are nullable (`::Array[::String?]`); a
  `:value` field is `untyped`, never `untyped?`; a bare generic `ruby_type`
  gets type arguments (`::Hash[untyped, untyped]`); and a field's `rbs_type:`
  override is honoured. A field typed by an anonymous nested struct class now
  raises `ArgumentError` (it previously emitted an invalid `::` name).
- **The committed signatures can only get more typed.** Contributor tooling
  only; the shipped `sig/actionable.rbs` is unchanged. `rake sigs:untyped`
  (part of the default task) fails when sig/ holds more or fewer than the
  committed ceiling of 46 non-comment `untyped`, so a typing change lowers
  the ceiling with it. `sigs:generate` / `sigs:check` fail on a sord
  `[OMIT]`/`[DUCK]` fallback that isn't in the committed allowlist (24
  today) and on allowlist entries sord no longer emits. sord runs without
  `--replace-errors-with-untyped` (the output is identical) and fails on any
  `SORD_ERROR_` type. `sigs:validate` validates the whole sig/ directory.
- **Optional, report-only Steep 2.x** via `gemfiles/types.gemfile` and a
  `types` CI job on Ruby 3.4 that never fails the build. The Steepfile now
  checks the core only (the RSpec and Rails adapters are ignored); Steep is
  no longer in the main Gemfile.
- **More precise signatures** (RBS only; no runtime change). Keyword splats
  are typed per value (`**Object options`, not `**::Hash[Symbol, Object]
  options`, which RBS reads as "every value is a Hash"); `.run`, `#initialize`
  and `Job::Mixin#run_actionable` take `*Object, **Object`; the gem's
  constants (`Actionable::HALT`, `VERSION`, `Action::GEM_FAILURE_CODES`, …)
  are declared; and the halt/measurement helpers declare their block. The
  DSL methods whose block runs with another `self` (`output`, `input`,
  `fails`, `skips`, `case_step`, `input_for`, and the `define` builders)
  gain a block overload with its self-type in the new
  `sig/actionable/dsl.rbs`. `untyped` in sig/ falls from 46 to 27, and the
  sord fallback allowlist from 24 entries to 4.

## [1.5.2] - 2026-10-22

Runner and nested-action fixes: hooks that halt, kwargs that survive hooks,
nested actions that neither wipe parent ivars nor commit failed writes.
Requires field_struct 0.11.0 or later.

### Changed

- **Requires field_struct >= 0.11.** It is the release whose numeric and input
  fixes this one is tested against; CI now pins it by tag.
- **CI runs Ruby 3.2, 3.3, 3.4 and 4.0** (was 3.3.6 only), plus the docs guard,
  behind one aggregate `ci` check that `main` requires.
- **The packaged gem leaves out contributor-only files** (`.claude/`,
  `CLAUDE.md`, `docs/origin/`, Rakefile/Steepfile/lint config). It still ships
  `lib/`, `sig/`, the user docs, `AGENTS.md` and the Claude skill.

### Fixed

- **A failed `transactional` action inside an outer transaction no longer
  commits its writes.** It joined the outer transaction, whose commit ignored
  the action's rollback, so a recorded `Failure` still committed its rows
  (measured on ActiveRecord 8.1 + SQLite). Inside an open transaction the action
  now takes its own savepoint (`requires_new: true`) unless `requires_new:` is
  given; `requires_new: false` keeps the old joining behaviour.
- **A nested action no longer wipes parent ivars it never set.** Absorbing a
  successful or skipped child copied every declared output field, so a field
  the child left nil (or at its default) overwrote the parent's value. Only
  fields the child actually set are absorbed now; `expose:` still narrows them.
- **Private step, hook and `case_step` methods work.** The definition check
  already accepted them, but the step then raised `NoMethodError`; they are
  now called like guards are. A step or hook named after a method the action
  only inherits from Ruby's core (`step :puts`, `always :exit`) raises
  `DefinitionError` up front instead of calling `Kernel`.
- **`Action.input` without a block reads the schema** instead of replacing it
  with an empty one, matching `output`.
- **A step that assigns `@result`** gets a clear `DefinitionError` instead of a
  `NoMethodError` deep in the runner.
- **`History#to_json` requires Oj itself** rather than relying on another file
  having loaded it.

- **A bang verb inside a lifecycle hook now sets the result.** `fail!`,
  `skip!` or `succeed!` in a hook used to be dropped: `fail!` in `on_success`
  returned `Success`, committed a `transactional` action and acked the job.
  The hook's result is now adopted before the halt stops the remaining hooks,
  as the docs always said. This includes a nested action used as a hook
  (`on_success ChildAction`): a failing child now fails the run and stops the
  remaining hooks.
- **`succeed`/`skip` kwargs survive lifecycle hooks.** After any hook
  refreshed the output, the kwargs were lost: a required field set only by
  kwarg turned the run into `Failure(:invalid_output)`, and a kwarg that
  overrode an ivar silently reverted to the ivar's value. Present since 1.0.0.
  A `Failure(:invalid_output)` also keeps the output that failed validation
  across hooks instead of having it rebuilt from ivars.
- **No spurious `errors[:output]` on a failure or skip.** The best-effort,
  unvalidated output of a non-typed failure or skip added
  `output: ["is invalid"]` to the result's errors. It no longer does; errors
  the failure recorded itself are kept.

## [1.5.1] - 2026-10-21

### Added

- **`Coverage.new_gap_hint`** sets the advice the baseline-mismatch message
  gives for a new gap. The default (`Coverage::DEFAULT_NEW_GAP_HINT`) is
  unchanged; a host whose baseline only shrinks can drop "or add it to the
  baseline".

### Fixed

- **RBS for a subclass of a typed action now resolves on its own.** Its result
  classes subclass the parent's (`< ::ApiAuth::BaseAction::Success`), which
  nothing declared when the parent is an abstract base that is never
  generated. `RBS.generate` now declares those parent classes, empty, up the
  chain of typed ancestors.
- **RBS readers on `Failure` are nullable.** An `invalid_output` failure
  carries the output that broke its schema, so a required field can be
  missing; the readers were typed non-nil.

## [1.5.0] - 2026-10-21

Typed outcomes (decision D23). Opt-in with `typed_outcomes`: an action that
doesn't turn it on runs as before, except that a code whose `fails` or `skips`
declaration carries a block (new syntax) has its output validated.

### Added

- **`typed_outcomes`** turns typed outcomes on for an action and its
  descendants (`typed_outcomes enabled: false` turns them off for a subclass);
  `typed_outcomes?` reads it.
- **A block on `fails` / `skips`** declares the output a result with that code
  carries, in the `output` DSL. **`failure_output_schema(code)`** and
  **`skip_output_schema(code)`** read it back, and `describe` shows its fields.
  Such output is built from the call's keywords alone, never from instance
  variables, and validated: output that breaks the schema ends the run as
  `invalid_output`. The block also ends instance-variable capture for that
  code, typed outcomes or not.
- **`output:` on `fail` / `fail!` / `fail_with` / `fail_with!`**, under typed
  outcomes only: the failure's output, a Hash or a FieldStruct
  (`ArgumentError` otherwise). Without them `output:` on `fail` is still an
  error, and `fail_with` refuses it. Under typed outcomes, output for a code
  with no schema raises `DefinitionError`, naming the code.
- **Per-action result classes.** Under typed outcomes `.run` returns the
  action's own `Success`, `Failure` or `Skipped`, each a subclass of the gem
  class (or of the parent action's own). A nested failure becomes the parent's
  own `Failure`, judged by the parent's schema for its code; a parent without
  typed outcomes gets a plain `Actionable::Failure`. The RSpec stub helpers
  return them too, with output shaped through the code's schema (or empty
  without one) as a real run would.
- **RBS:** `Actionable::RBS.generate` types a typed action's `.run` as
  `(Success | Skipped | Failure)`, with each `code` and `output` narrowed and
  the output's readers declared on each class. A host's own result subclass,
  which `.run` still returns as it is, is not described: a known gap.

### Changed

- Under typed outcomes, a skip or failure whose code has no schema carries an
  empty output, where it used to carry a best-effort capture into the success
  schema. The gem's own `invalid_input` / `invalid_output` keep theirs.
- Under typed outcomes, results compare by class: `Act::Success` is not `==`
  to an `Actionable::Success` with the same output, and the stub helpers
  return a new object of the action's own class. Specs that compare results
  with `==` need to compare against the action's class.

## [1.4.0] - 2026-10-21

Declared skips (decision D21), the skip counterpart of 1.3.0's declared
failures. Additive: an action that declares no skips runs as before, and a
child skip still continues its parent. One edge can reach existing code, listed
under Changed: a skip's `to_h`, `inspect` and `attributes` have a `metadata`
key.

Outcome coverage for test suites (decision D22). Opt-in with
`require 'actionable/rspec/coverage'`; nothing changes for a suite that
doesn't require it.

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
- **`Actionable::Coverage`** records every real `.run` of a named action as
  `[class name, outcome, code]`, nested runs and `run_each` included. It hooks
  `Action.run` by prepending onto its singleton class, so an RSpec stub of
  `.run` replaces it and a stubbed result never counts as the action tested.
- **The RSpec stub helpers note their runs** in `Coverage.stubbed` when
  coverage is loaded, so a report can show an outcome that was only ever
  stubbed. They record when the stub answers a call, not when it is set up.
- **`Coverage.expected_outcomes(action)`** lists what an action can end with,
  read from its declarations at run time: `success`, every `declared_failures`
  code, every `declared_skips` code, and any
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
- **Sharded suites.** `Coverage.write(path)` dumps a shard's runs as JSON and
  `Report.new(files:)` merges any number of them (a glob that matches no file
  raises rather than reporting everything missing). `Coverage.report!` prints
  the report, writes JSON to `ACTIONABLE_COVERAGE_JSON` when set, rewrites
  the baseline under `ACTIONABLE_COVERAGE_UPDATE_BASELINE=true`, and otherwise
  raises `Coverage::BaselineMismatch` when the gaps differ from it.
- **`require 'actionable/rspec/coverage'`** turns it all on: it starts
  recording and adds an RSpec `after(:suite)` hook that writes the shard file
  named by `ACTIONABLE_COVERAGE_FILE` when that is set, and otherwise prints
  the report and fails the suite on a baseline mismatch.

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
