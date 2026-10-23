# Changelog

## [Unreleased]

### Documentation

- **UPGRADING.md, from a dry run against a large app (133 actions).** The guide
  now says which six Finds must run on a green suite (silent behaviour changes)
  and that the rest cover code the suite doesn't reach. The `describe` Find skips
  `RSpec.describe` (1,552 hits before). The code Finds skip receivers and
  non-Ruby files. The `@result` entry says a `Result` you build yourself is still
  allowed, with `halt!`. A new section lists the class-level API unchanged since
  1.5.1. The cop entry says to list every base class defined in its own file. The
  opt-out goes in `spec_helper`, not an initializer. The effort estimate counts
  suite runs, and there is a PCRE2 check. AGENTS.md and the skill follow.

## [1.8.1] - 2026-10-23

Housekeeping. The `Actionable/VerbNotLast` cop resolves superclass names the way
Ruby does, so same-named classes in one file no longer confuse it; the
UPGRADING.md drift guard is fixture-tested and now asks for an explicit
decision on every visible CHANGELOG entry. No runtime behaviour changes.

### Changed

- **`Actionable/VerbNotLast` resolves a superclass by its lexical full name.**
  It matched by the last name segment, so in one file `module B; class Base;
  end; class X < Base` counted as an action when `module A` held a `Base <
  Actionable::Action`, and a file's own `Legacy::ApplicationAction` counted as
  the listed base. It now looks the name up as Ruby does (enclosing `module` /
  `class` outwards, a compact `class A::B` opens only `A::B`, `::X` is the
  top level), so those classes are left alone, and a listed full name is
  found from inside its namespace (`module Ops; class X < BaseAction` with
  `Ops::BaseAction` listed). An offense it newly reports is a call the
  first-run check already raises on. <!-- upgrading: none -->

### Tests / CI

- **The UPGRADING.md drift guard asks for a decision on every visible
  change.** Each `[Unreleased]` bullet under `### Changed`, `### Removed` or
  `### Breaking…` must carry an `upgrading: <slug>` marker comment (with its
  guide entry, as before) or `upgrading: none`, so a change filed there
  without an upgrade note no longer slips past it. Released sections are not
  re-checked. The guard's own examples now run on fixtures, so they hold in
  any release state; one example still checks the live files.

## [1.8.0] - 2026-10-22

A guard against silently continuing runs, plus upgrade guidance. A plain
`fail` / `fail_with` / `skip` / `succeed` must now be the last thing its step
or hook does — checked once per action class on first run (Prism; turn it off
with `Actionable.verb_position_check = false`) and by a shipped RuboCop cop,
`Actionable/VerbNotLast`. `fail` / `skip` codes must be identifiers, so the
`fail 'card expired'` Kernel habit raises instead of recording a code. Both can
raise on code that used to run: read `UPGRADING.md`, which walks 1.5 → 1.8
change by change. CI now also runs real ActiveJob/Sidekiq and ActiveRecord 7.1
lanes. Still requires field_struct >= 0.12.

### Added

- **A plain recording verb must end its step or hook method (owner rulings
  R5, R10).** `fail :card_expired if card.expired?` followed by more code keeps
  running — almost always a `fail!` missing its bang. On an action's first
  run, every step method (case-step branch targets included) and lifecycle
  hook method (`on_success` / `on_failure` / `on_skip` / `always`, and
  `after_commit` with the Rails adapter) is parsed with Prism, and a plain
  `fail` / `fail_with` / `skip` / `succeed` (or `self.fail` …) that isn't the
  method's last expression raises `DefinitionError` naming the action, method, `file:line`,
  verb and fix. Branches, `return fail(...)`, a verb followed by `return`,
  and blocks whose call is last are allowed; USAGE (Control flow, "Where a
  plain verb may go") has the full table. Checked once per class: later runs
  pay one instance-variable read. Skipped without Prism >= 1.0 (Ruby 3.2
  without the `prism` gem; no new dependency) and for methods with no
  parseable source (`eval`, `define_method`).
- **`Actionable.verb_position_check = false`** turns that first-run check off
  for the process (on by default; `Actionable.verb_position_check?` reads it).
  Off, `run` never parses source or loads Prism. It is an escape hatch while
  upgrading, and leaves the cop as the only guard. The identifier check on
  `fail` / `skip` codes stays on: it's a per-call regex, not a parse.
- **`Actionable/VerbNotLast`, an opt-in RuboCop cop** with the same rules
  (one shared analyzer). Not loaded by `require 'actionable'`; enable it with
  `plugins: [{actionable: {require_path: actionable/rubocop}}]` (RuboCop >=
  1.72, via the gem's lint_roller plugin) or `require: [actionable/rubocop]`.
  It checks a class whose superclass is an action base and that declares
  `step` / `case_step`, and the methods that class names in its declarations.
  An action base is one of the cop's `ActionBaseClasses` (default
  `Actionable::Action`, `ApplicationAction`) or a class defined in the same
  file whose superclass chain reaches one, so a dry-transaction class with
  its own `step` gets no false positives (owner ruling R10).
- `rake bench` gains `fail! action` and `skip! action` scenarios.

### Changed

- **`fail` / `skip` codes must be identifiers.** A code that isn't a Symbol
  or String matching `/\A[[:alpha:]_][[:alnum:]_]*[?!]?\z/` (`'card
  expired'`, `:"not-found"`, `'payment.declined'`, a class) raises
  `ArgumentError` at the call, suggesting `raise` for `Kernel#fail` habit.
  Applies to `fail` / `fail!` / `fail_with` / `fail_with!` / `skip` / `skip!`.

**Upgrading:** both checks raise on code that used to run. <!-- upgrading: verb-position-guard --> <!-- upgrading: identifier-codes -->
- `DefinitionError` "… calls `fail` with more code after it …" on an action's
  first run: if the code after the verb should not run, use the bang verb
  (`fail!`); if it should, move the verb to the end of the method (or
  `return fail(...)`). Run the cop over your app to find them all up front.
  If you can't fix them all before deploying, set
  `Actionable.verb_position_check = false` in an initializer until you have.
- `ArgumentError` "… code "…" is not an identifier": use a Symbol code and
  pass the sentence as the message (`fail(:card_expired, 'card expired')`),
  or `raise` if you meant an exception.

### Tests / CI

- **Real-backend lanes.** Two new CI jobs feed the required `ci` check:
  `jobs (ActiveJob + Sidekiq)` runs the suite with `gemfiles/jobs.gemfile`, so
  `spec/actionable/job_backends/` proves `Job` + `honor_retry_metadata` on a
  real ActiveJob (`retry_on Actionable::Job::RetryableFailure`: `retry: true`
  re-enqueues until attempts run out, `retry: false` discards or acks, the
  default is unchanged) and that `RetryableFailure` propagates out of a Sidekiq
  job in inline testing mode (no Redis). `activerecord 7.1` runs the suite on
  ActiveRecord 7.1 (`gemfiles/activerecord_7_1.gemfile`, Ruby 3.3):
  `transactional` and savepoints work there, and declaring `after_commit`
  raises the `DefinitionError` naming 7.2. These specs skip in the default
  suite, where the gems or versions they need are absent.

### Documentation

- **`UPGRADING.md`: how to move an app from 1.5.x to 1.8.0** (owner ruling
  R9). A TL;DR with the order of work (field_struct first, then actionable,
  the cop, RBS), a straight 1.5-to-1.8 path, a symptom index, and a Symptom /
  Find / Fix / Why entry for every change a caller can see, each Find an `rg`
  pattern checked against its "before" code or the tool that finds it. AGENTS.md
  and the skill gain a numbered upgrade procedure for agents; README and
  getting_started link to it, and the gem ships it. `spec/upgrading_spec.rb`
  keeps it honest: every CHANGELOG upgrade note since 1.5.2 carries an
  invisible `upgrading:` slug comment that the guide must carry in that
  version's section, and the guide's declared range must reach the next
  release. Its runnable examples are doctested.
- README "Types (RBS)" says the adapter signatures (`transactional`,
  `after_commit`, the RSpec helpers, `Job`) are declared on `Actionable::Action`
  even when `actionable/rails` isn't required: RBS can't make a signature
  conditional and `rbs` loads a gem's whole `sig/`.

## [1.7.0] - 2026-10-22

Lifecycle and adapter hardening. `always` hooks now run even after an outcome
hook halts; redeclaring a step or hook overrides it in place; the Rails adapter
gains an opt-in `after_commit` hook (ActiveRecord >= 7.2) that runs only after
the outermost transaction commits; `Job` can opt in to honouring a failure's or
skip's declared `retry:`; the Rails, Job and RSpec surfaces now ship RBS. Two
behaviour changes have upgrade notes under Changed. Still requires
field_struct >= 0.12.

### Added

- **`benchmarks/` and `rake bench`.** A dependency-free script (monotonic
  clock, no `benchmark` / benchmark-ips) times a trivial run, a 5-step run with
  `measure :none` and `:all`, 5-field input coercion, a nested action with and
  without measurement, and `history.to_json`. `BENCH_ITERATIONS` sets the loop
  count. Not in the default task and not packaged in the gem; a smoke spec
  runs it with 5 iterations so it can't rot. README has a "Performance"
  section with indicative numbers.

### Documentation

- **`fail` is not `raise` inside an action.** USAGE (Control flow), README,
  getting_started, AGENTS.md and the skill now warn that the gem's `fail` verb
  replaces `Kernel#fail` in an action's instance methods: `fail 'boom'`
  records a `Failure` with code `:"boom"` and the run continues, and
  `fail SomeError, 'msg'` raises `NoMethodError`. Use `raise` for exceptions
  and `fail!(:code)` to stop with a failure. Behaviour is unchanged.
- README, getting_started, AGENTS.md and the skill now mention the 1.7.0
  topics where they list their neighbours: step/hook redeclaration (last
  wins), `always` hooks running after a hook halt, `after_commit`, and
  `honor_retry_metadata`, each linking to USAGE.

- **RBS for the adapters' public surface (owner ruling P11).** `sig/` now <!-- upgrading: adapter-rbs -->
  declares what clients call from the adapters: `transactional` /
  `transaction_config` and `after_commit` / `after_commit_hooks` on
  `Actionable::Action` (Rails adapter), and the RSpec matchers
  (`perform_actionable` and its chain) and stubs (`allow_actionable_*`,
  `stub_actionable_*`, `actionable_*_result`). They are generated from YARD by
  sord like the core's (`.yardopts` now excludes only `ProxyValidator`, the
  Railtie and `actionable/rspec/coverage`); the one runtime mix-in YARD cannot
  see, `after_commit`'s singleton-class prepend, is declared by hand in
  `sig/actionable/rails.rbs`. A spec compares each adapter type's public
  methods, by reflection, with its RBS so neither can drift. `Actionable::Job`
  was already generated. The report-only Steep lane now checks the adapters
  too.
- **`describe` / `describe_text` list `after_commit` hooks.** With the Rails <!-- upgrading: describe-after-commit -->
  adapter loaded, `describe[:hooks][:after_commit]` names them, and
  `describe_text` adds an `after_commit:` hooks line when there are any.

- **`after_commit` hook kind (Rails adapter).** After `require 'actionable/rails'`,
  `after_commit :method` (or a nested action, with `:if` / `:unless` /
  `:input` like any hook) runs a side effect only after the database work
  really committed. It is registered with
  `ActiveRecord.after_all_transactions_commit` when a run ends in a `Success`,
  so it waits for the **outermost** open transaction (not the action's own
  savepoint), runs immediately when none is open, and never runs if an
  enclosing transaction rolls back. A `Failure` or `Skipped` never runs it.
  The run is over by then: the hook can't change the result, isn't recorded in
  the history, and an exception it raises propagates after the commit (from
  the outer `transaction` call, or `.run` when no transaction was open).
  Needs ActiveRecord >= 7.2; declaring it on an older one (or without
  ActiveRecord loaded) raises a `DefinitionError`. Existing hooks and the
  core are unchanged.

- **`honor_retry_metadata`: let `Actionable::Job` act on declared `retry:`
  metadata.** An action that calls it (the macro comes with
  `require 'actionable/job'`) has the `retry:` key of its declared failures and
  skips decide the job's disposition: `retry: true` retries (a skip or a
  permanent-code failure included) and `retry: false` does not (a failure is
  discarded, a skip acks). Codes without the key map as before. Retried skips
  raise the same `RetryableFailure`, carrying the `Skipped`. Inherited; a
  subclass backs out with `honor_retry_metadata(enabled: false)`.
  `Actionable::Job.disposition` takes the matching `honor_retry:` keyword.
  Off by default, so metadata stays neutral (D20/D21) and existing jobs behave
  exactly as before.

### Changed

- **Redeclaring a step or hook now overrides it.** A second `step :x`, <!-- upgrading: step-redeclaration -->
  `case_step :x`, nested `step SomeAction`, or `on_success` / `on_failure` /
  `on_skip` / `always :x` with the same type and name, in the same class or a
  subclass, replaces the earlier declaration's options (guards, `:input` /
  `:expose`, case branches) and keeps the earlier position. Before, the
  redeclaration was silently dropped and the first declaration's options won,
  so a subclass could not override an inherited step as invariant 5 promises.
  A subclass's override never changes the parent. **Upgrade note:** an action
  that redeclares a step with different options now runs the last options.

- **`always` hooks now run even after an outcome hook halts.** A bang verb <!-- upgrading: always-after-halt -->
  (`fail!` / `skip!` / `succeed!`), `halt!`, or a failing nested action inside
  an `on_success` / `on_failure` / `on_skip` hook still has its result adopted
  and still stops the remaining hooks of that category, but it no longer skips
  the `always` hooks: they run next and see the adopted result. Before, one
  halt stopped every remaining hook, so cleanup and audit hooks could be
  silently skipped. A halt inside an `always` hook is adopted the same way and
  stops only the remaining `always` hooks. Under `transactional`, `always`
  hooks still run inside the transaction and the adopted result still decides
  commit or rollback, so an `always` hook's writes roll back with a failed run.
  When measuring, those `always` hooks appear in the history as usual.
  **Upgrade note:** an `always` hook that assumed it would not run after a hook
  failure must now check `result` itself.

## [1.6.0] - 2026-10-22

Valid, guarded RBS. The gem's own signatures can only get more typed (CI
ratchet, `untyped` 46 → 27); generated RBS for your actions declares the real
superclass chain, a typed `InputSchema`, typed `.run` keywords and output
ivars, built on field_struct 0.12's `FieldStruct::RBS.type_for`. Requires
field_struct >= 0.12. No runtime behaviour changes.

### Added

- **`Actionable::RBS.generate` types an action's input and output instance <!-- upgrading: rbs-output-ivars --> <!-- upgrading: rbs-input-schema -->
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

- **`Actionable::RBS.generate` declares the real superclass chain.** An action <!-- upgrading: rbs-superclass-chain -->
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
- **Requires field_struct >= 0.12.** The generator now takes every field type <!-- upgrading: field-struct-0-12 --> <!-- upgrading: rbs-stricter-types -->
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

- **Requires field_struct >= 0.11.** It is the release whose numeric and input <!-- upgrading: field-struct-0-11 -->
  fixes this one is tested against; CI now pins it by tag.
- **CI runs Ruby 3.2, 3.3, 3.4 and 4.0** (was 3.3.6 only), plus the docs guard,
  behind one aggregate `ci` check that `main` requires.
- **The packaged gem leaves out contributor-only files** (`.claude/`,
  `CLAUDE.md`, `docs/origin/`, Rakefile/Steepfile/lint config). It still ships
  `lib/`, `sig/`, the user docs, `AGENTS.md` and the Claude skill.

### Fixed

- **A failed `transactional` action inside an outer transaction no longer <!-- upgrading: transactional-savepoint -->
  commits its writes.** It joined the outer transaction, whose commit ignored
  the action's rollback, so a recorded `Failure` still committed its rows
  (measured on ActiveRecord 8.1 + SQLite). Inside an open transaction the action
  now takes its own savepoint (`requires_new: true`) unless `requires_new:` is
  given; `requires_new: false` keeps the old joining behaviour.
- **A nested action no longer wipes parent ivars it never set.** Absorbing a <!-- upgrading: nested-absorb-set-fields --> <!-- upgrading: stub-set-fields -->
  successful or skipped child copied every declared output field, so a field
  the child left nil (or at its default) overwrote the parent's value. Only
  fields the child actually set are absorbed now; `expose:` still narrows them.
- **Private step, hook and `case_step` methods work.** The definition check <!-- upgrading: core-method-steps -->
  already accepted them, but the step then raised `NoMethodError`; they are
  now called like guards are. A step or hook named after a method the action
  only inherits from Ruby's core (`step :puts`, `always :exit`) raises
  `DefinitionError` up front instead of calling `Kernel`.
- **`Action.input` without a block reads the schema** instead of replacing it
  with an empty one, matching `output`.
- **A step that assigns `@result`** gets a clear `DefinitionError` instead of a <!-- upgrading: result-ivar -->
  `NoMethodError` deep in the runner.
- **`History#to_json` requires Oj itself** rather than relying on another file
  having loaded it.

- **A bang verb inside a lifecycle hook now sets the result.** `fail!`, <!-- upgrading: hook-bang-verb -->
  `skip!` or `succeed!` in a hook used to be dropped: `fail!` in `on_success`
  returned `Success`, committed a `transactional` action and acked the job.
  The hook's result is now adopted before the halt stops the remaining hooks,
  as the docs always said. This includes a nested action used as a hook
  (`on_success ChildAction`): a failing child now fails the run and stops the
  remaining hooks.
- **`succeed`/`skip` kwargs survive lifecycle hooks.** After any hook <!-- upgrading: hook-kwargs -->
  refreshed the output, the kwargs were lost: a required field set only by
  kwarg turned the run into `Failure(:invalid_output)`, and a kwarg that
  overrode an ivar silently reverted to the ivar's value. Present since 1.0.0.
  A `Failure(:invalid_output)` also keeps the output that failed validation
  across hooks instead of having it rebuilt from ivars.
- **No spurious `errors[:output]` on a failure or skip.** The best-effort, <!-- upgrading: no-spurious-output-error -->
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
