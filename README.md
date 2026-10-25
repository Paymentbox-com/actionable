# Actionable

Typed, composable Ruby **service objects**. Subclass `Actionable::Action`,
declare an ordered list of **steps**, implement each as a method, and run it. A
run returns a single value object — a `Success`, `Failure`, or `Skipped` — with a
`code`, `message`, structured `errors`, a typed `output`, and an execution
`history`.

- **Pure-Ruby core** — depends only on [`field_struct`](https://github.com/Paymentbox-com/field_struct). Rails (transactions, validators) is an optional adapter.
- **Typed in and out** — declared `input`/`output` schemas, coerced and validated through FieldStruct, with full RBS via Sord + YARD.
- **Three honest outcomes** — success, failure, and *skip* (nothing to do — neither).

## Installation

The gem is named **`actionable-rb`** (the `actionable` gem on rubygems.org is
an unrelated 2014 project). You still `require 'actionable'` and use the
`Actionable` module; `Bundler.require` loads it from the gem name. Until both
gems are on rubygems.org, install them from GitHub, pinned to a release tag:

```ruby
# Gemfile
gem 'field_struct',  git: 'https://github.com/Paymentbox-com/field_struct', tag: 'v0.15.0'
gem 'actionable-rb', git: 'https://github.com/Paymentbox-com/actionable',   tag: 'v1.9.0'
```

Bundler matches a git source by the gem's name: tags up to `v1.8.2` name it
`actionable`, so an app moving from those renames its Gemfile line (see
[UPGRADING.md](UPGRADING.md)).

Requires Ruby 3.3+. Upgrading from an earlier release? See [UPGRADING.md](UPGRADING.md).

## Quick start

<!-- doctest -->
```ruby
class Greet < Actionable::Action
  output { required :greeting, :string }

  step :build

  def build
    @greeting = "Hello, #{name}!"
  end

  def name = 'World'
end

result = Greet.run
result.success?        # => true
result.greeting        # => "Hello, World!"
result.output.greeting # => "Hello, World!"
```

A step is just a method. Set instance variables that match declared `output`
fields and they're captured, coerced, and surfaced on the result — and reachable
directly off it (`result.greeting`). If no step records a result, the run
auto-succeeds.

## Control flow

Inside a step, five verbs record the outcome. The bang forms also halt the
pipeline; the plain forms record and keep going (last write wins). Genuine
exceptions are never swallowed — they propagate to the caller.

| Verb | Records | Halts? |
|------|---------|--------|
| `succeed(message = nil, **output)` | `Success` | no |
| `fail(code, message = nil, **errors)` | `Failure` | no |
| `fail_with(source, code: :invalid)` | `Failure` absorbing `source.errors` | no |
| `skip(code = :skipped, message = nil, **output)` | `Skipped` | no |
| `succeed!` / `fail!` / `fail_with!` / `skip!` | as above | **yes** |
| `halt!` | — (keeps current) | **yes** |

`fail_with` absorbs an arbitrary FieldStruct's validation errors into the failure
— handy for validating a side struct in a step. `skip` takes output kwargs too,
so an idempotent hit can return the existing record's data.

Inside an action, `fail` is this verb, not Ruby's `Kernel#fail`: it never
raises, and a sentence code (`fail 'card expired'`) raises `ArgumentError`. Use
`raise` for exceptions. A plain `fail` / `fail_with` / `skip` / `succeed` must be the last
expression of its step or hook method (`fail :x if bad?` followed by more code
is a `fail!` missing its bang): an action that breaks this raises
`DefinitionError` on its first run, and the opt-in `Actionable/VerbNotLast`
RuboCop cop flags it in your editor. While upgrading an app that has misplaced
verbs, `Actionable.verb_position_check = false` turns the first-run check off
(the cop is then the only guard). See
[USAGE, Control flow](USAGE.md#where-a-plain-verb-may-go).

<!-- doctest -->
```ruby
class Charge < Actionable::Action
  input { required :amount, :integer }

  step :validate
  step :charge

  def validate
    fail!(:invalid_amount, 'must be positive') unless input.amount.positive?
  end

  def charge
    succeed("charged #{input.amount}")
  end
end

ok = Charge.run(amount: 10)
ok.success?  # => true
ok.message   # => "charged 10"

bad = Charge.run(amount: -5)
bad.failure? # => true
bad.code     # => :invalid_amount
```

## Three outcomes, not two

A **skip** means the action had nothing to do — a precondition wasn't ready, the
work was already done. That's not a failure (no error, nothing to retry or
alert) and not a success (no real work). Conflating it with either loses
information; `Actionable` makes it a first-class outcome.

<!-- doctest -->
```ruby
class Sync < Actionable::Action
  input { optional :ready, :boolean }

  step :guard
  step :perform

  def guard
    skip!(:not_ready, 'nothing to sync yet') unless input.ready
  end

  def perform
    succeed('synced')
  end
end

idle = Sync.run(ready: false)
idle.skipped? # => true
idle.success? # => false
idle.failure? # => false
idle.ok?      # => true
idle.code     # => :not_ready

Sync.run(ready: true).success? # => true
```

Predicates: `success?` / `successful?`, `failure?` / `failed?`, `skipped?`, and
`ok?` (≡ "didn't fail" — true for both a success and a skip).

## Declared failures

An action can declare the failure codes it ends with, each with neutral
metadata. The gem stores the metadata, attaches it to the failure and shows it
in `describe`, but never interprets it, so your app decides what a key like
`kind:` means:

<!-- doctest -->
```ruby
class Capture < Actionable::Action
  fails :refused, 'the card was refused', kind: :rejected
  fails :expired, kind: :rejected

  step :capture
  def capture = fail!(:refused)
end

result = Capture.run
result.code     # => :refused
result.metadata # => {kind: :rejected}
Capture.declared_failures.keys # => [:refused, :expired]
```

Once an action declares any code, a `fail` with an undeclared one raises
`Actionable::DefinitionError` at the call. Actions that declare none, and the
codes the gem emits itself (`:invalid_input`, `:invalid_output`), are unchecked.
A nested action's failure reaches its parent with its code, message, errors and
metadata intact. See [USAGE](USAGE.md#declared-failures).

Skips are declared the same way with `skips`, so every way an action can end is
part of its contract:

<!-- doctest -->
```ruby
class Reindex < Actionable::Action
  skips :not_ready, 'the index is still building', retry: true

  step :reindex
  def reindex = skip!(:not_ready)
end

skipped = Reindex.run
skipped.code     # => :not_ready
skipped.metadata # => {retry: true}
Reindex.declared_skips # => {not_ready: {retry: true}}
```

Metadata is yours to interpret: the gem stores and returns it but never acts
on it (decisions D20/D21). In particular `Actionable::Job` acks every skip;
`retry: true` above does not make a job retry unless the action opts in with
`honor_retry_metadata` (see [Background jobs](#background-jobs-optional)).
Otherwise read `result.metadata` in your job, or list permanent failure codes
with `actionable_permanent_codes`.

Once an action declares any skip code, a `skip` with an undeclared one raises
`Actionable::DefinitionError`, and that includes the default `:skipped`. See
[USAGE](USAGE.md#declared-skips).

## Typed output

`output do … end` builds a FieldStruct schema. Matching instance variables are
captured at the end of the run, coerced through the schema, and exposed as
`result.output` plus convenience delegation. Only a **strict success** is
validated — a failed or skipped run captures output best-effort.

<!-- doctest -->
```ruby
class Sum < Actionable::Action
  output { required :total, :integer }

  step :add

  def add
    @total = '42' # coerced through the schema
  end
end

Sum.run.total        # => 42
Sum.run.output.total # => 42
```

## Typed input

`input do … end` makes `.run` coerce its keyword arguments into a typed struct,
validate them, and expose `input` to the steps. A missing or invalid required
input short-circuits to a `Failure(:invalid_input)` without running any steps.
Without an `input` block, `.run`'s arguments are forwarded to the constructor.

For a polymorphic payload, `input_for` picks the schema at run time from a
discriminator — typed input without a single fixed shape:

```ruby
input_for :event_type do
  on 'sale',   SaleShape
  on 'refund', RefundShape
  default      UnknownShape
end
```

## Running a batch

`Action.run_each(enumerable) { |item| run_args }` runs the action once per item
and collects a `BatchResult` (Enumerable) — the common "process each row, report
per item" shape. Items run independently.

```ruby
batch = ImportRow.run_each(rows) { |row| { row: row } }
batch.all_ok?       # => false
batch.failures.size # => 2
batch.to_api_h      # => [{index: 0, status: :success, id: …, errors: {}}, …]
```

## Composition

Steps can be other actions or value-based branches.

**Nested actions** thread named instance variables in (`:input`) and absorb
selected outputs back (`:expose`, default all). A nested failure fails the
parent; a nested skip continues it.

<!-- doctest -->
```ruby
class BuildLine < Actionable::Action
  input  { required :sku, :string }
  output { required :line, :string }
  step :build

  def build = @line = "line:#{input.sku}"
end

class BuildOrder < Actionable::Action
  output { required :line, :string }
  step :set_sku
  step BuildLine, input: %i[sku], expose: %i[line]

  def set_sku = @sku = 'ABC'
end

BuildOrder.run.output.line # => "line:ABC"
```

**Case steps** branch on a value, matched by `==`, `Regexp`, or Array membership.

<!-- doctest -->
```ruby
class Triage < Actionable::Action
  input  { required :status, :integer }
  output { optional :level, :symbol }

  def status = input.status

  case_step :status do
    on (400..499).to_a, :client_error
    on (500..599).to_a, :server_error
    default :ok
  end

  def client_error = @level = :client
  def server_error = @level = :server
  def ok = @level = :ok
end

Triage.run(status: 404).output.level # => :client
Triage.run(status: 503).output.level # => :server
Triage.run(status: 200).output.level # => :ok
```

## Lifecycle hooks

`on_success`, `on_failure`, `on_skip`, and `always` run after the main steps,
dispatched by the outcome (then `always`, regardless). Hooks are ordinary
methods and may use the control-flow verbs. A bang verb in an outcome hook
stops the rest of that category and becomes the result, but the `always` hooks
still run, so cleanup and audit can't be skipped. Redeclaring a step or hook
(in the same class or a subclass) overrides it in place: the last declaration
wins. See [USAGE](USAGE.md#lifecycle-hooks) and [Steps](USAGE.md#steps).

```ruby
class Publish < Actionable::Action
  step :publish

  on_success :notify
  on_failure :rollback
  on_skip    :log_skip
  always     :audit

  # ...
end
```

## History & measurement

`measure :all` records a `History` of every step — section, name, timing,
result code, and nested child history. The default (`measure :none`) records
nothing for zero overhead. `measure :sampled, rate: 0.1` records a fraction of
runs for low-overhead production observability. Measurement cascades into nested
actions.

```ruby
class Pipeline < Actionable::Action
  measure :all
  step :a
  step :b
end

history = Pipeline.run.history
history.steps.map(&:name) # => [:a, :b]
history.took              # total seconds
history.to_json           # Oj-serialized
```

## Registry & introspection

Every named action registers itself for discovery and tooling, and
`Action.describe` returns a structured summary (input/output, steps, hooks,
measure) so humans and agents can understand an action without reading source:

```ruby
Actionable.registry['Greet'] # => Greet
Greet.describe               # => { name: "Greet", steps: [...], output: {...}, ... }
Greet.describe_text          # => "Greet (measure: none)\n  Input: ..." (readable form)
```

Failure results expose FieldStruct's error collection, so beyond
`result.errors[:field]` you get `result.errors.full_messages` — each message as
a complete sentence (`"Total is required"`). `result.to_h` is a plain-Hash view,
and `result.to_api_h(index:)` a compact HTTP/batch element (`index`, `status`,
`id`, `errors`).

## Guardrails

Misconfigured actions fail loudly with `Actionable::DefinitionError` rather than
a cryptic `NoMethodError`: declaring an `output` field that shadows a result
attribute or reserved ivar is rejected at declaration time, and a declared step
whose method isn't implemented is caught at run start (naming the action and
method).

## Rails adapter (optional)

`require 'actionable/rails'` adds the `transactional` macro and
`Actionable::ProxyValidator`. The core never loads `active_*`.

```ruby
require 'actionable/rails'

class Settle < Actionable::Action
  transactional model: :invoice # wraps the run in Invoice.transaction

  step :debit
  step :credit
end
```

A success commits; a recorded failure **or** a raised exception rolls back; a
skip commits (nothing to roll back).

`after_commit :send_receipt` (ActiveRecord >= 7.2) runs a side effect only
after the **outermost** transaction commits a successful run — never after a
rollback, a failure, or a skip; immediately when no transaction is open.

`ProxyValidator` applies ActiveModel rules to a delegate object:

```ruby
class InvoiceRules < Actionable::ProxyValidator
  validates :amount, presence: true, numericality: { greater_than: 0 }
end

# inside a step:
rules = InvoiceRules.new(@invoice)
fail(:invalid, **rules.formatted_errors) unless rules.valid?
```

## RSpec integration (optional)

`require 'actionable/rspec'` adds the `perform_actionable` matcher and stub
helpers:

```ruby
expect(CreateInvoice).to perform_actionable(amount: 5).and_succeed
expect(CreateInvoice).to perform_actionable(bad).and_fail(:invalid_input)
expect(Sync).to          perform_actionable(ready: false).and_skip(:not_ready)

allow_actionable_success(CreateInvoice, output: { id: 7 })
```

## Outcome coverage (optional)

`require 'actionable/rspec/coverage'` records which outcomes your specs
actually reach. At the end of the suite it reports, for every action, the
outcomes it can end with (success, its declared failures and skips) that no
spec produced. A stubbed result doesn't count. A committed baseline of known
gaps lets CI fail on a new gap or a stale entry, and sharded suites write one
file per shard and merge them in a later step. See USAGE, "Outcome coverage".

```ruby
# spec/support/actionable_coverage.rb
require 'actionable/rspec/coverage'
Actionable::Coverage.loader = -> { Rails.application.eager_load! }
Actionable::Coverage.baseline = 'spec/actionable_coverage_baseline.yml' if ENV['CI']
```

## Background jobs (optional)

`require 'actionable/job'` adds a framework-agnostic helper that runs an action
inside a Sidekiq worker or ActiveJob job and maps its result to a queue
disposition (`:ack` / `:retry` / `:discard`):

```ruby
require 'actionable/job'

class ProjectEventJob
  include Sidekiq::Job             # or ActiveJob::Base
  include Actionable::Job::Mixin

  def perform(event_id)
    run_actionable(ProjectApiEvent, event_id: event_id)
  end
end
```

A success or skip acks; a transient failure raises `RetryableFailure` so the
queue retries; a permanent-code failure is discarded. Genuine exceptions
propagate unchanged. An action that declares `honor_retry_metadata` lets the
`retry:` metadata of its declared failures and skips decide instead
(`skips :not_ready, retry: true` then retries the job). See
[USAGE](USAGE.md#background-jobs).

## Types (RBS)

The library ships `sig/actionable.rbs` (generated by Sord from YARD). For your
own actions, `Actionable::RBS.generate(YourAction)` emits a typed `.run`
signature, a typed `input` (as `InputSchema`), the output instance variables
your steps assign, and output accessors from the action's `input`/`output`
schemas.

**Adapter signatures are always declared.** `sig/` also types the Rails adapter
(`transactional`, `transaction_config`, `after_commit`, `after_commit_hooks`) on
`Actionable::Action`, the RSpec helpers, and `Actionable::Job`. RBS has no way to
make a signature depend on a `require`, and `rbs` loads a gem's whole `sig/`
directory, so a type checker sees those methods even in an app that never
requires `actionable/rails` — where calling them raises `NoMethodError`. Outside
Rails, don't rely on the type checker to catch a stray `transactional`.

## Claude Code skill

The gem bundles a [Claude Code](https://claude.com/claude-code) skill
(`skills/actionable/SKILL.md`) that teaches the assistant the step/result DSL,
the control-flow verbs, the common mistakes, and how to debug a failed or skipped
run — so editing actions in a dependent project goes correctly.

**Install as a plugin** (recommended — the repo doubles as a single-plugin marketplace):

```text
/plugin marketplace add Paymentbox-com/actionable
/plugin install actionable@actionable
```

**Or copy it into your project** (no marketplace needed) — the skill ships in the gem package:

```bash
mkdir -p .claude/skills/actionable
cp "$(bundle show actionable)/skills/actionable/SKILL.md" .claude/skills/actionable/
```

Either way it triggers when you ask Claude to define, edit, or debug an
`Actionable::Action`. The skill points at [`USAGE.md`](USAGE.md) (also shipped)
for the exhaustive reference.

## Performance

Indicative numbers from `bundle exec rake bench` (dependency-free script in
`benchmarks/`, 20,000 iterations after a warm-up; Ruby 4.0.7, YJIT off, Apple
M4, actionable 1.6.0 + the unreleased 1.7.0 changes). Use them to compare
changes on one machine, not as a promise for yours.

| Scenario | µs per run |
|---|---|
| Trivial action (one empty step) | 5.6 |
| 5-step action, `measure :none` (default) | 7.4 |
| 5-step action, `measure :all` | 11.5 |
| Input coercion, 5-field schema from strings | 20.4 |
| Nested action (parent + child, typed outputs) | 23.4 |
| Nested action, `measure :all` | 26.8 |
| `history.to_json` of a 5-step history | 3.6 to 4.4 |

The fixed cost of a run dominates; each extra step is a fraction of a
microsecond. Measuring adds about 4 µs to a 5-step run, so `measure :sampled`
keeps it off most production runs. Input coercion and typed output validation
cost more than the steps themselves.

## Development

```bash
bin/rspec                       # run the specs
bundle exec rake                # specs + rubocop
bundle exec rake release:check  # full pre-flight (specs, rubocop, sigs, docs)
bundle exec rake bench          # indicative micro-benchmarks (not in the default task)
```

See [`USAGE.md`](USAGE.md) for the dense, example-first reference.

## License

[MIT](LICENSE.txt).
