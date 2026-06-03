# Actionable — Phase 1 Plan

> Source-of-truth design and slice plan for the Actionable rebuild (v1.0.0).
> Lives alongside the original idea in `docs/origin/`. Update this file when
> locked decisions change. When anything elsewhere disagrees with this file,
> this file wins.

---

## Overview

**Actionable** is a small Ruby library for **service objects**: classes that
encapsulate one unit of business logic as an ordered sequence of **steps**. You
subclass `Actionable::Action`, declare its steps with a DSL, implement each step
as a method, and run it. Running returns a single **result** value object with a
`code`, a `message`, structured `errors`, a typed `output`, and an execution
`history`.

Actionable exists to move business logic out of Rails controllers/models, Sidekiq
workers, and rake tasks into a shared, composable, predictably-shaped set of
actions. It is consciously *not* a workflow engine, a state machine, or a
background-job framework. It is a thin, well-typed orchestration layer over plain
Ruby methods.

The public module is `Actionable`. Users get features by subclassing
`Actionable::Action`.

```ruby
class CreateInvoice < Actionable::Action
  input do
    required :amount, :big_decimal
    optional :name,   :string
  end

  output do
    required :invoice, Invoice          # FieldStruct schema; typed result payload
  end

  step :build
  step :validate
  step :persist

  def build
    @invoice = Invoice.new(amount: input.amount, name: input.name)
  end

  def validate
    fail! :invalid, 'Amount is required' if input.amount.nil?
  end

  def persist
    @invoice.save!
  end
end

result = CreateInvoice.run(amount: 19.99, name: 'Acme')
result.success?         # => true
result.code             # => :success
result.output.invoice   # => #<Invoice ...>  (typed)
result.invoice          # => same, via convenience delegation
```

---

## Phase 1 scope (v1.0.0)

### In scope

- `Actionable::Action` superclass; subclasses inherit step declarations and config.
- Step DSL: `step`, `case_step`, `on_success`, `on_failure`, `always`.
- Step types: **Method** (calls an instance method), **Action** (runs a nested
  action), **Case** (value-based branching).
- Step options: `:if`, `:unless` (Symbol method name or callable), and for nested
  Action steps `:input` (values to pass) and `:expose` (which outputs to absorb).
- Control flow via `fail` / `succeed` / `skip` (record, continue) and `fail!` /
  `succeed!` / `skip!` / `halt!` (record + stop) using `throw :actionable_halt`.
  **No `rescue Exception`** — genuine errors propagate. (`skip` is D17.)
- A single result value object hierarchy: `Actionable::Result` with `Success` and
  `Failure`, backed by FieldStruct. Carries `code`, `message`, `errors`, `output`,
  `history`.
- **Typed output**: an `output do … end` block declares a FieldStruct schema; the
  runner captures matching instance variables, coerces/validates them through
  FieldStruct, and exposes `result.output` plus convenience delegation on the result.
- **Typed input (optional)**: an `input do … end` block declares a FieldStruct
  schema; `.run` accepts the input attributes (or an input instance), validates, and
  the action reads `input.foo`. Absent an `input` block, the action defines its own
  `initialize` and `.run(*args)` stays free-form.
- Lifecycle hooks: `on_success`, `on_failure`, `always`.
- Execution `History`: per-step section/name/timing/code, nested action history,
  `measure :all | :none`. JSON via Oj.
- `Actionable.registry` — a registry of all defined `Action` subclasses.
- RSpec integration (`require 'actionable/rspec'`): a `perform_actionable` matcher
  and `stub_/allow_actionable_success|failure` helpers.
- Optional Rails adapter (`require 'actionable/rails'`): `transactional` macro for
  ActiveRecord transaction wrapping, and `Actionable::ProxyValidator`.
- Type signatures: YARD on the full public surface → Sord-generated
  `sig/actionable.rbs`; `Actionable::RBS.generate(klass)` for user actions.
- RSpec suite; Rubocop clean; SimpleCov coverage; doctested README/USAGE examples.

### Out of scope (Phase 2+)

- Async / background execution (returning a deferred result).
- Step retries, timeouts, circuit-breaking.
- Result composition combinators beyond nested-action steps (e.g. `and_then` chains).
- Persisted/queryable run history (history is in-memory per run only).
- Non-Rails ORM transaction adapters (Sequel, ROM) — design once Rails adapter lands.
- Auto-generated Markdown/HTML docs from action metadata.
- A CLI / generator for scaffolding action classes.
- I18n of messages.

---

## Locked design decisions

Each decision was settled in the redesign conversation. Where the *why* is
non-obvious it is recorded. Decisions are referenced by anchor (D1…D16) in commit
messages and other docs.

### D1. Clean-slate rebuild; names preserved

A from-scratch rewrite — the old implementation is scrapped, not refactored.
Breaking API changes are allowed and expected. The gem name stays `actionable`
and the module stays `Actionable`; users still subclass `Actionable::Action`. The
push host is `https://rubygems.pkg.github.com/Paymentbox-com` (changed from the
old `acima-credit` host). Authorship/email: Adrian Madrid, amadrid@pmtbox.com.
Versioning restarts at **v1.0.0** to signal the break.

### D2. Step DSL

```ruby
step :name                 # Method step — calls instance method #name
step OtherAction           # Action step — runs a nested action
case_step :value do …  end # Case step — branch on a value
on_success :name           # runs at the end iff the result is a success
on_failure :name           # runs at the end iff the result is a failure
always     :name           # runs at the end regardless
```

`step` is the primitive; the type (Method vs Action) is inferred from the
argument (Symbol/String → Method, Class → Action). **The redundant `action` /
`case_action` aliases from the old gem are dropped** — one name per concept keeps
the surface legible. Each declaration list is a `Set` keyed by `[type, name]`,
deduplicated, inherited by subclasses, and order-preserving.

### D3. Step types and options

Three concrete step types under `Actionable::Steps`:

| Type | Triggers on | Behavior |
|---|---|---|
| `Steps::Method` | Symbol/String | `instance.public_send(name)` |
| `Steps::Action` | `Class < Action` | runs the nested action, threads output |
| `Steps::Case` | `case_step` block | evaluates a value, runs the matching branch |

Common options:

- `:if` / `:unless` — a Symbol (instance method) or a callable `->(instance) { … }`.
  Skip the step when the guard says so.

Action-step-only options:

- `:input` — `Array<Symbol>` of the parent's output/ivar names to pass into the
  nested action's `.run` (replaces the old `:params`).
- `:expose` — `Array<Symbol>` limiting which of the nested action's outputs are
  absorbed back into the parent (replaces the old `:fixtures`). Default: all.

### D4. Control flow: `throw`/`catch` halt, never exceptions

The runner wraps the main-step loop in `catch(:actionable_halt) { … }`.

| Call | Records result? | Stops pipeline? | Mechanism |
|---|---|---|---|
| `fail(code, message = nil, **errors)` | yes (Failure) | no | sets `@result`, returns `false` |
| `succeed(message = nil, **output)` | yes (Success) | no | sets `@result`, returns `true` |
| `fail!(code, message = nil, **errors)` | yes (Failure) | **yes** | sets `@result` then `throw` |
| `succeed!(message = nil, **output)` | yes (Success) | **yes** | sets `@result` then `throw` |
| `skip(code = :skipped, message = nil)` | yes (Skipped) | no | sets `@result`, returns `false` |
| `skip!(code = :skipped, message = nil)` | yes (Skipped) | **yes** | sets `@result` then `throw` |
| `halt!` | no | **yes** | `throw` only; keeps current `@result` |

> `skip` / `skip!` were added later — see **D17** for the `:skip` outcome.

**`fail`/`succeed` (no bang) do NOT skip later steps** — this deliberately fixes the
old gem's inconsistency where a plain `fail` silently short-circuited because it set
the `finished?` flag. Last write wins: the final result reflects the most recent
`fail`/`succeed`, or auto-success if none was called. A `halt!` with no prior
`fail`/`succeed` lets finalization auto-succeed.

Genuine exceptions (`StandardError` and below) are **not** caught by the runner.
They propagate to the caller. The RSpec matcher (`and_raise`) is the supported way
to assert on them. This removes the old `rescue Exception` entirely.

### D5. Result value objects (FieldStruct-backed)

`Actionable::Result` is the base; `Actionable::Success`, `Actionable::Failure`, and
`Actionable::Skipped` (the third outcome — see **D17**) are subclasses. Each is a
FieldStruct with:

- `code` — `:success` for `Success`; an error Symbol for `Failure`; the skip
  reason (default `:skipped`) for `Skipped`.
- `message` — String, human-readable.
- `errors` — a structured errors object (`Hash`-like; integrates with FieldStruct
  and, under the Rails adapter, ActiveModel errors via `formatted_errors`).
- `output` — the action's declared output FieldStruct instance (see D6). Empty
  schema → empty struct.
- `history` — the `History` for the run (see D10).

Predicates: `success?` / `successful?`, `failure?` / `failed?`, `skipped?`, and
`ok?` (≡ `!failure?`, true for both `Success` and `Skipped`). `to_s` / `inspect`
give a compact, sorted, deterministic representation. JSON via Oj.

### D6. Typed output via a declared schema

```ruby
class CreateInvoice < Actionable::Action
  output do
    required :invoice, Invoice
    optional :receipt, Receipt
  end
end
```

The `output do … end` block builds an anonymous `FieldStruct::Base` subclass stored
as the action's **output schema** — a *single* schema shared by both outcomes. At
the end of a run the runner reads the instance variables whose names match declared
output fields, overlays any `succeed(**output)` keyword arguments (kwargs win on
conflict), coerces them through FieldStruct, and assigns the struct to
`result.output`.

- **Ergonomics preserved**: step methods still just set `@invoice = …`. No explicit
  "expose" call is needed — declaration + ivar name is the contract. `succeed`'s
  kwargs are a shorthand overlay on top of the captured ivars.
- **Convenience delegation**: `result.invoice` delegates to `result.output.invoice`
  for declared fields. Undeclared ivars are *not* surfaced (a deliberate change from
  the old "capture everything" behavior — output is now an explicit, typed contract).
- **Asymmetric validation** (revised 2026-06; see note below). On a **success**, the
  captured output is validated through FieldStruct; if it fails (a `required` field
  was never set, or a value won't coerce), the run can't truly have succeeded, so it
  becomes a `Failure` with code `:invalid_output` carrying the validation errors. On a
  **failure**, output is captured best-effort and **never** validated — callers treat
  failure output as possibly incomplete (fields that were never set come back `nil`).
- An action with **no** `output` block is *free-form*: `result.output` keeps whatever
  was recorded (e.g. the `succeed(**output)` hash, default `{}`), with no schema,
  coercion, validation, or delegation.

> **Revision note (2026-06, during Slice 6).** D6 originally implied a single schema
> with uniform handling. Implementation surfaced the success-vs-failure question; the
> locked outcome is the single-schema, asymmetric-validation design above. A richer
> "shape per outcome / per failure code" was considered and **deferred** to a future
> decision, as was the division of labor between a typed *failure output* and the
> existing structured `errors` collection. For now, failure detail lives in
> `code` / `message` / `errors`; typed output is primarily a success-path contract.

### D7. Typed input via an optional schema

```ruby
class CreateInvoice < Actionable::Action
  input do
    required :amount, :big_decimal
    optional :name,   :string
  end
end

CreateInvoice.run(amount: 19.99, name: 'Acme')   # kwargs → input struct
CreateInvoice.run(CreateInvoice.input_schema.new(amount: 19.99))  # or an instance
```

When an `input` block is present, `.run` coerces its arguments into the input
FieldStruct, and the action reads values via `input.amount`. Validation errors on
required inputs surface as an immediate `Failure` (code `:invalid_input`) without
running any steps.

When there is **no** `input` block, the action defines its own `initialize` and
`.run(*args, **kwargs)` forwards verbatim — the free-form path, for actions whose
inputs don't fit a flat schema. Typed input is the path that unlocks a fully-typed
`.run` and richer RBS generation (D13).

Typed input stays **keyword-only**: `.run` takes keyword arguments (or a pre-built
input instance). Accepting positional arguments (mapped to declared fields by
order) was considered and **deferred** — keyword call sites are self-documenting
and immune to field reordering, which matters most for service objects. Revisit
after real-world usage; see Phase 2+ backlog and `scrap/positional_input_args.md`.

### D8. Rails decoupling: pure-Ruby core + optional adapter

The core gem depends only on `field_struct` (which itself pulls `bigdecimal` and
`oj`). No ActiveModel/ActiveSupport/ActiveRecord in the core load path.

`require 'actionable/rails'` loads the adapter, which adds:

- the `transactional` macro and transaction wrapping (D9);
- `Actionable::ProxyValidator` (ActiveModel validations over a delegate);
- integration of ActiveModel error objects into `Failure#errors` /
  `formatted_errors`.

The adapter auto-loads when ActiveRecord is already defined; otherwise it is an
explicit require. Calling `transactional` without the adapter raises a clear,
actionable error at class-definition time.

### D9. Transactions (Rails adapter only)

```ruby
transactional model: :invoice                       # wrap run in Invoice.transaction
transactional model: :invoice, requires_new: true   # nested-safe savepoint
```

Replaces the old `set_model` / `set_transactional_model` /
`set_safely_nesting_transactional_model` trio with one macro taking options. The
runner wraps the entire step pipeline in `model.transaction(**options)` so a raised
exception (or, optionally, a failure) rolls everything back. `model:` resolves a
class from a Symbol (`:invoice` → `Invoice`) or takes a class directly. Inherited by
subclasses; overridable.

### D10. History and measurement

`Actionable::History` records, per step: section (`:main` / `:success` / `:failure`
/ `:always`), name, start time, duration, result code, and the nested action's
history (for Action steps). Timing uses a monotonic clock corrected to wall-clock.

`measure :all` enables recording; `measure :none` (default) disables it for zero
overhead. `History#as_json` / `#to_json` serialize via Oj. `History#took` sums step
durations.

### D11. Registry

`Actionable.registry` is an `Actionable::Registry` mapping action class name →
class. The `Action.inherited` hook registers every subclass. Read-only iteration
(`each`, `[]`, `keys`, `values`, `size`, `empty?`). Used for discovery and tooling
(e.g. the RBS generator can sweep all registered actions).

### D12. RSpec integration

`require 'actionable/rspec'` mixes in:

- **Matcher** `perform_actionable(*args, **kwargs)` with `.and_succeed(message)`,
  `.and_fail(code, message)`, `.and_raise(klass, message)`, plus an optional block
  yielding `(result, exception)`. Rich failure messages with trimmed backtraces
  (`ACTIONABLE_BACKTRACE_QTY`, `ACTIONABLE_SHORT_BACKTRACE`).
- **Stubs** `stub_actionable_success` / `allow_actionable_success` /
  `stub_actionable_failure` / `allow_actionable_failure`, building real `Success` /
  `Failure` objects from a fixtures/output hash so callers can assert on
  `result.code` etc. without running the action.

### D13. RBS generation strategy (two tracks)

1. **Library classes** — Sord generates `sig/actionable.rbs` from YARD comments.
   Maintained by `rake sigs:generate | sigs:check | sigs:validate`; the committed
   sig file is guarded against staleness in CI. A short, documented `SORD_FIXUPS`
   list patches known Sord gaps.
2. **User actions** — `Actionable::RBS.generate(klass)` walks an action's declared
   `input`/`output` schemas (via FieldStruct's own metadata) and emits:
   - a typed `.run` signature (from the input schema, or `(*untyped) -> Result` when
     free-form),
   - typed `output` accessors and result-delegation methods (from the output schema),
   - namespaced module nesting for namespaced action classes.
   Reuses FieldStruct's `ruby_type` mapping for field → Ruby type.

### D14. Source layout: explicit requires, no Zeitwerk

Standard `lib/actionable.rb` entry point with an explicit `require_relative` for
every file. No autoload, no Zeitwerk. New files under `lib/actionable/` get a
matching `require_relative` line. The Rails adapter and RSpec integration live under
`lib/actionable/rails*` and `lib/actionable/rspec*` and are **not** required by the
core entry point.

```
lib/
  actionable.rb                      # entry: require_relative the core
  actionable/
    version.rb
    errors.rb                        # exception hierarchy + halt symbol
    result.rb                        # Result (FieldStruct base)
    results/
      success.rb
      failure.rb
    steps.rb                         # Steps factory
    steps/
      base.rb
      method.rb
      action.rb
      case.rb
    action.rb                        # Actionable::Action
    runner.rb                        # Actionable::Runner (catch/halt loop)
    history.rb
    registry.rb
    schema.rb                        # input/output FieldStruct plumbing
    rbs.rb                           # Actionable::RBS.generate for user actions
    rails.rb                         # OPTIONAL adapter: transactions + ProxyValidator
    rails/
      transactions.rb
      proxy_validator.rb
    rspec.rb                         # OPTIONAL: matcher + stubs
    rspec/
      matchers.rb
      stubs.rb
```

### D15. Conventions

- **Oj** for JSON — never `JSON.parse` / built-in `to_json`. Use `Oj.load` / `Oj.dump`.
- **Ruby 3.2+** (`required_ruby_version >= 3.2`).
- **TDD non-negotiable** — every behavior ships with the spec that proves it, in the
  same commit. See `.claude/tdd_guidelines.md`.
- **Conventional, atomic commits** — `feat:` / `fix:` / `refactor:` / `test:` /
  `docs:` / `chore:`. Tests pass at every commit.
- **Branching** — `main` = released; `develop` = integration; per-feature branches
  off `develop`. Release = `develop` → `main` via PR.

### D16. Doctested documentation

README and USAGE code examples are wrapped in `<!-- doctest -->` blocks and executed
by `spec/docs_examples_spec.rb`, so published examples can't rot. `rake release:check`
runs specs + rubocop + sig staleness/validity guards + a strict YARD build.

### D17. The `:skip` outcome (added 2026-06; revises D4/D5)

A third run outcome beyond Success/Failure: **skip** — the action had nothing to
do (a field isn't created yet, a condition isn't ready). It is *not* a failure
(no error, no retry/alert) and *not* a success (no real work), so conflating it
with either loses information for observability, retries, and composition.

- `Actionable::Skipped < Result`, with `skipped?` true and `success?` /
  `failure?` both false (a **strict** third state). Every result also gains
  `ok?` (≡ `!failure?` — true for `Success` and `Skipped`) for the "didn't
  fail" check. `code` defaults to `:skipped` and carries the reason.
- Verbs `skip(code = :skipped, message = nil)` (record, continue) and `skip!`
  (record + halt), mirroring `fail`. No output/errors payload — a skip produces
  neither.
- Lifecycle: a new `on_skip` hook; the runner dispatches a skipped run to
  `on_skip` (never `on_success`/`on_failure`), then `always`.
- Output: only a **strict** `Success` is validated. A `Skipped` (like a
  `Failure`) captures output best-effort and is never validated, so a skip with
  a declared output schema does not flip to `:invalid_output`.
- Nested: a skipped child action is not a failure, so it continues the parent
  like a success (absorb best-effort output, don't halt) — the parent decides
  its own outcome.
- Transactions: a skip commits (not a failure → no rollback).
- RSpec: `perform_actionable.and_skip(code, message)`, plus
  `allow_actionable_skip` / `stub_actionable_skip`.

### D18. DX guardrails + introspection (added 2026-06)

Serves the core "easily understood by humans and agents" goal by failing loudly
on misconfiguration and making actions self-describing.

- `Actionable::DefinitionError < Error` for misconfigured actions.
- **Reserved output field guard (definition time):** declaring an `output`
  field that shadows a result attribute (`code`/`message`/`output`/`history`/
  `errors`) or a reserved ivar (`result`/`input`) raises `DefinitionError` when
  `output` is declared. (Input fields are read via `input.x` and don't collide,
  so they aren't guarded.)
- **Missing step method guard (run start):** before running, every method a step
  needs — method steps, case value sources + method branch targets (via
  `Steps#required_methods`), and hook steps — must exist on the instance, or a
  clear `DefinitionError` names the action and method instead of a deep
  `NoMethodError`. Run-start is the earliest reliable point (steps are declared
  above the methods that implement them).
- **`Action.describe`** — a structured Hash summary: name, input/output field
  metadata, ordered steps (each tagged with `Steps#kind`), hooks by section,
  measure mode, and transaction config. Complements the Registry and
  `Actionable::RBS`.

_Considered in this review but **not** taken: `Result#to_h` and documenting the
`succeed`/`fail`/`skip` signature asymmetry — see `scrap/dx_review.md`._

---

## Slice plan

16 slices (plus Slice 17, the post-plan `:skip` outcome), ordered so each is
independently testable and unblocks the next. Foundation first (results → control
flow → steps → action/runner), then output/input schemas, lifecycle, composition,
ergonomics, the optional adapters, and finally the type/doc toolchain and release.
Every slice produces one or more atomic commits; every test ships with the code it
proves.

### Slice 1 — Result value objects
`Actionable::Result` (FieldStruct base) + `Success` / `Failure` with
`code`/`message`/`errors`/`output`/`history`, predicates, and deterministic
`to_s`/`inspect`. No Action yet.
Commit: `feat: add result value objects backed by field_struct`

### Slice 2 — Exceptions and the halt primitive
`Actionable::Error` hierarchy; the `:actionable_halt` throw tag and a `catch_halt`
helper. Specs prove halt unwinds to the catch point and that `StandardError`
propagates past it.
Commit: `feat: add error hierarchy and throw/catch halt primitive`

### Slice 3 — Step base + Method step
`Steps::Base` (name, options, equality/hash for Set dedup, `:if`/`:unless` skip
logic) + `Steps::Method`. Tested in isolation against a fake instance.
Commit: `feat: add step base and method step`

### Slice 4 — Action base + `step` DSL + Runner main loop
`Actionable::Action` with `step`, class-level step `Set`, inheritance; `Runner`
runs main steps inside `catch(:actionable_halt)` and auto-succeeds when no result
was set.
Commit: `feat: introduce Action with step DSL and runner main loop`

### Slice 5 — Control flow
`fail` / `succeed` / `fail!` / `succeed!` / `halt!` per D4. Specs cover record-only
vs record-and-halt, last-write-wins, auto-success, and exception propagation.
Commit: `feat: add fail/succeed control flow with throw/catch halt`

### Slice 6 — Output schema
`output do … end` builds a FieldStruct subclass; runner captures matching ivars
(overlaid by `succeed` kwargs), coerces, assigns `result.output`, and result
delegates declared fields. Single schema; validated on success (failure →
`:invalid_output`), best-effort and unvalidated on failure. See revised D6.
Commit: `feat: add typed output schema with field_struct`

### Slice 7 — Lifecycle hooks
`on_success` / `on_failure` / `always` lists, run after main steps based on outcome;
output refreshed after each.
Commit: `feat: add on_success/on_failure/always lifecycle steps`

### Slice 8 — Nested Action step
`Steps::Action` with `:input` and `:expose`; threads parent output into the child's
`.run` and absorbs selected child outputs. Nested failure fails the parent.
Commit: `feat: add nested action steps with input/expose`

### Slice 9 — Case step
`Steps::Case` with `on(value, target)` and `default(target)`; value compared by
`==`, Regexp, or Array membership; target is a method or nested action.
Commit: `feat: add case_step branching`

### Slice 10 — History and measurement
`History` + `History::Step`; `measure :all|:none`; nested history; Oj serialization;
runner records sections/timings/codes.
Commit: `feat: add execution history and measurement`

### Slice 11 — Registry
`Actionable::Registry` + `inherited` hook + `Actionable.registry`.
Commit: `feat: add action registry`

### Slice 12 — Typed input schema
`input do … end`; `.run` coerces args into the input struct, validates, and exposes
`input`; `:invalid_input` failure on bad required inputs; free-form fallback when no
`input` block.
Commit: `feat: add optional typed input schema`

### Slice 13 — Rails adapter
`actionable/rails`: `transactional` macro + transaction wrapping; `ProxyValidator`;
ActiveModel error integration. Core stays Rails-free; adapter is opt-in and
auto-loads when ActiveRecord is present.
Commits: `feat: add rails adapter with transactional macro`,
`feat: add proxy validator to rails adapter`

### Slice 14 — RSpec integration
`actionable/rspec`: `perform_actionable` matcher (`and_succeed`/`and_fail`/`and_raise`
+ block) with trimmed-backtrace failure messages; stub/allow helpers building real
result objects.
Commits: `feat: add perform_actionable matcher`, `feat: add actionable rspec stubs`

### Slice 15 — Type/doc toolchain
Wire Sord + RBS + YARD: Rakefile `sigs:*` / `docs:*` / `release:check`,
`rbs_collection.yaml`, `.yardopts`, CI guards. Add `Actionable::RBS.generate(klass)`
for user actions, driven off input/output schemas.
Commits: `chore: wire sord/rbs/yard toolchain`, `feat: add RBS generator for user actions`

### Slice 16 — Docs + release
README/USAGE/getting_started rewrite with doctested examples; `skills/actionable/SKILL.md`;
CHANGELOG; gemspec metadata (Paymentbox push host); coverage + rubocop + `rake release:check`
green; tag v1.0.0.
Commits: `docs: add usage guide and examples`, `chore: fill gemspec metadata`,
`chore: release v1.0.0`

### Slice 17 — The `:skip` outcome (added post-plan; see D17)

`Actionable::Skipped` + `skip` / `skip!` + `ok?` + `on_skip` hook; skip output is
best-effort/unvalidated; nested skip continues the parent; skip commits under
`transactional`; `and_skip` matcher + skip stubs. Not in the original 16; added
on request and specified by decision **D17**.
Commits: `feat: add :skip outcome status`,
`feat: add skip support to the rspec matcher and stubs`,
`docs: document the :skip outcome (D17)`

---

## Phase 2+ backlog

Surfaced during design, explicitly deferred. Roughly by likely value:

1. **Async / deferred results** — run an action in the background, return a handle.
2. **Step retries / timeouts** — declarative resilience options on steps.
3. **Result combinators** — `and_then`-style chaining across independent actions.
4. **Non-Rails transaction adapters** — Sequel, ROM.
5. **Persisted run history** — opt-in storage of `History` for observability.
6. **Auto-generated docs** — Markdown/HTML from action input/output/step metadata.
7. **Generators** — a Rails generator / CLI for scaffolding action classes.
8. **Positional input arguments** — let typed-`input` `.run` accept positionals
   (mapped to declared fields by order) in addition to keywords. Considered and
   **deferred** (see D7): keyword stays canonical; revisit after real-world usage
   shows it's wanted. Tradeoffs in `scrap/positional_input_args.md`.

---

## Glossary

| Term | Meaning |
|---|---|
| **Action** | A subclass of `Actionable::Action` encapsulating one unit of business logic as an ordered list of steps. |
| **Step** | A single unit in an action's pipeline. One of: Method, Action (nested), or Case. |
| **Method step** | A step that calls an instance method on the action. |
| **Action step** | A step that runs another action, threading values in (`:input`) and out (`:expose`). |
| **Case step** | A step that branches to different targets based on a value. |
| **Lifecycle hook** | `on_success` / `on_failure` / `always` step that runs at the end of a run depending on outcome. |
| **Runner** | `Actionable::Runner` — executes an action's steps inside `catch(:actionable_halt)`, runs lifecycle hooks, wraps in a transaction when configured, and returns the result. |
| **Result** | The single FieldStruct-backed value object returned by a run: `Success`, `Failure`, or `Skipped`. Carries code, message, errors, output, history. |
| **Skip** | A third outcome (D17): the action had nothing to do. `Skipped` result; `skipped?` true, neither success nor failure; recorded via `skip`/`skip!`. |
| **Output** | The action's declared, typed result payload (a FieldStruct). Populated from matching instance variables at the end of a run. |
| **Input** | The action's optional declared, typed argument schema (a FieldStruct). Enables typed `.run` and richer RBS. |
| **Halt** | Stopping the main pipeline early via `throw :actionable_halt` (from `fail!`/`succeed!`/`skip!`/`halt!`). Distinct from a raised exception. |
| **History** | Per-run record of each step's section, name, timing, code, and nested history. Enabled by `measure :all`. |
| **Registry** | `Actionable.registry` — the map of all defined action classes. |
| **Rails adapter** | The optional `actionable/rails` layer adding transactions and `ProxyValidator`. The core never depends on it. |
| **Slice** | An atomic, independently shippable unit of work in the Phase 1 plan. Maps to one or more conventional commits. |
