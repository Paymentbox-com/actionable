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

```ruby
# Gemfile
gem 'actionable'
```

Requires Ruby 3.2+.

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
| `skip(code = :skipped, message = nil)` | `Skipped` | no |
| `succeed!` / `fail!` / `skip!` | as above | **yes** |
| `halt!` | — (keeps current) | **yes** |

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
methods and may use the control-flow verbs.

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
nothing for zero overhead. Measurement cascades into nested actions.

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
```

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

## Types (RBS)

The library ships `sig/actionable.rbs` (generated by Sord from YARD). For your
own actions, `Actionable::RBS.generate(YourAction)` emits a typed `.run`
signature and output accessors from the action's `input`/`output` schemas.

## Development

```bash
bin/rspec                       # run the specs
bundle exec rake                # specs + rubocop
bundle exec rake release:check  # full pre-flight (specs, rubocop, sigs, docs)
```

See [`USAGE.md`](USAGE.md) for the dense, example-first reference.

## License

[MIT](LICENSE.txt).
