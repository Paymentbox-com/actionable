# Getting started with Actionable

How to use Actionable in a repo — productively, in about ten minutes. Actionable
builds typed **service objects**: you subclass `Actionable::Action`, declare an
ordered list of **steps**, implement each as a method, and run it. A run returns
one typed **result** — a `Success`, `Failure`, or `Skipped` — carrying a `code`,
`message`, structured `errors`, a typed `output`, and an execution `history`.

This is the task-oriented adoption guide. For the exhaustive list of step types,
options, and macros see [`USAGE.md`](../USAGE.md); for the feature tour see
[`README.md`](../README.md).

## At a glance — task → API

| You want to… | Do this |
|---|---|
| Define a service object | `class Settle < Actionable::Action` |
| Add an ordered step | `step :build` |
| Run it | `Settle.run(**kwargs)` |
| Type & validate inputs | `input { required :amount, :integer }` |
| Type the result payload | `output { required :invoice, Invoice }` |
| Read a typed output | `result.invoice` / `result.output.invoice` |
| Record success / failure / skip | `succeed` / `fail(:code)` / `skip(:code)` |
| Stop the pipeline | `succeed!` / `fail!` / `skip!` / `halt!` |
| Guard a step | `step :charge, if: :ready?` |
| Branch on a value | `case_step :status do … end` |
| Compose actions | `step Other, input: %i[sku], expose: %i[line]` |
| Run code after the outcome | `on_success` / `on_failure` / `on_skip` / `always` |
| Record timings & history | `measure :all`, then `result.history` |
| Inspect an action | `Settle.describe` / `Settle.describe_text` |
| Read errors as sentences | `result.errors.full_messages` |
| Test an action | `expect(Settle).to perform_actionable(…).and_succeed` |
| Wrap a run in a DB transaction | `transactional model: :invoice` (Rails adapter) |
| Generate RBS for an action | `Actionable::RBS.generate(Settle)` |

## Install

```ruby
# Gemfile
gem 'actionable'
```

Requires Ruby 3.2+. The core is pure Ruby (only `field_struct`). Two optional
adapters are separate requires — never loaded by the core:

```ruby
require 'actionable/rails'  # transactions + ProxyValidator (needs Rails / ActiveModel)
require 'actionable/rspec'  # the perform_actionable matcher + stub helpers
```

---

## Part 1 — Any Ruby project

### Your first action

A step is just a method. Set instance variables that match declared `output`
fields and they're captured, coerced, and surfaced on the result — and reachable
directly off it. If no step records an outcome, the run auto-succeeds.

<!-- doctest -->
```ruby
class Greet < Actionable::Action
  output { required :greeting, :string }

  step :build

  def build = @greeting = 'Hello, World!'
end

result = Greet.run
result.success?        # => true
result.greeting        # => "Hello, World!"
result.output.greeting # => "Hello, World!"
```

### The result model — three honest outcomes

Every run returns exactly one result. Beyond success and failure, a **skip** is a
first-class outcome: the action had nothing to do (a precondition wasn't ready,
the work was already done). That's neither an error nor real work, so conflating
it with either loses information. Results can also be built directly (handy in
tests):

<!-- doctest -->
```ruby
ok = Actionable::Success.new(message: 'done')
ok.success?  # => true
ok.ok?       # => true

idle = Actionable::Skipped.new(code: :not_ready)
idle.skipped? # => true
idle.failure? # => false
idle.ok?      # => true

bad = Actionable::Failure.new(code: :nope)
bad.failure? # => true
bad.ok?      # => false
```

Predicates: `success?`/`successful?`, `failure?`/`failed?`, `skipped?`, and `ok?`
(≡ "didn't fail" — true for both a success and a skip). Every result carries
`code`, `message`, `errors`, `output`, and `history`.

### Typed input

`input do … end` coerces `.run`'s keyword arguments into a typed struct and
exposes it to the steps as `input`. A missing or uncoercible **required** input
short-circuits to `Failure(:invalid_input)` *without running any steps*.

<!-- doctest -->
```ruby
class Double < Actionable::Action
  input  { required :n, :integer }
  output { required :doubled, :integer }

  step :go

  def go = @doubled = input.n * 2
end

Double.run(n: '21').output.doubled # => 42
Double.run.code                    # => :invalid_input
```

### Typed output

`output do … end` declares a FieldStruct schema. Matching ivars are captured at
the end of the run, coerced through the schema, and exposed as `result.output`
plus convenience delegation (`result.total` → `result.output.total`). Only a
**strict success** is validated — a failed or skipped run captures output
best-effort and is never validated.

<!-- doctest -->
```ruby
class Sum < Actionable::Action
  output { required :total, :integer }

  step :add

  def add = @total = '42' # coerced through the schema
end

Sum.run.total        # => 42
Sum.run.output.total # => 42
```

### Control flow

Inside a step, five verbs record the outcome. The plain forms record and keep
going (**last write wins**); the bang forms also halt the pipeline. A genuine
`StandardError` is never swallowed — it propagates to the caller.

| Verb | Records | Halts? |
|------|---------|--------|
| `succeed(message = nil, **output)` | `Success` | no |
| `fail(code, message = nil, **errors)` | `Failure` | no |
| `fail_with(source, code: :invalid)` | `Failure` absorbing `source.errors` | no |
| `skip(code = :skipped, message = nil, **output)` | `Skipped` | no |
| `succeed!` / `fail!` / `fail_with!` / `skip!` | as above | **yes** |
| `halt!` | keeps current result | **yes** |

`fail`'s keyword arguments populate the result's `errors`; `succeed`'s populate
its `output`.

<!-- doctest -->
```ruby
class Charge < Actionable::Action
  input { required :amount, :integer }

  step :validate
  step :charge

  def validate
    fail!(:invalid_amount, 'must be positive') unless input.amount.positive?
  end

  def charge = succeed("charged #{input.amount}")
end

Charge.run(amount: 10).message  # => "charged 10"
Charge.run(amount: -5).failure? # => true
Charge.run(amount: -5).code     # => :invalid_amount
```

A skip is just as easy to express, and reads as "nothing to do":

<!-- doctest -->
```ruby
class Sync < Actionable::Action
  input { optional :ready, :boolean }

  step :guard
  step :perform

  def guard
    skip!(:not_ready, 'nothing to sync yet') unless input.ready
  end

  def perform = succeed('synced')
end

Sync.run(ready: false).skipped? # => true
Sync.run(ready: false).ok?      # => true
Sync.run(ready: true).success?  # => true
```

### Branching — case steps

A `case_step` reads a value (from a method or input) and dispatches to a branch
target, matched by `==`, Array membership, or `Regexp`. A branch target is any
step target — a method or a nested action.

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
  def ok           = @level = :ok
end

Triage.run(status: 404).output.level # => :client
Triage.run(status: 503).output.level # => :server
Triage.run(status: 200).output.level # => :ok
```

### Composing — nested actions

A step can be another action. `:input` names parent ivars to thread into the
child's `.run`; `:expose` limits which child outputs are absorbed back as parent
ivars (default: all). A child failure fails the parent (with the child's
code/message/errors) and halts; a child skip continues the parent.

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

### Lifecycle hooks & measurement

`on_success`, `on_failure`, `on_skip`, and `always` run after the main steps,
dispatched by the outcome (then `always`, regardless). Hooks are ordinary methods
and may use the control-flow verbs. `measure :all` records a `History` of every
step (the default `measure :none` records nothing for zero overhead):

<!-- doctest -->
```ruby
class Timed < Actionable::Action
  measure :all
  step :work
  def work = nil
end

history = Timed.run.history
history.steps.map(&:name)   # => [:work]
history.steps.first.section # => :main
```

### Introspecting an action

`describe` returns a structured Hash (name, input/output field metadata, ordered
steps, hooks, measure mode, transaction config); `describe_text` renders the same
information as a human/agent-readable string. Both let a reader understand an
action without opening its source.

<!-- doctest -->
```ruby
class Probe < Actionable::Action
  output { required :count, :integer }
  step :compute
  def compute = @count = 1
end

Probe.describe[:measure]            # => :none
Probe.describe[:steps].first[:type] # => :method
Probe.describe.key?(:output)        # => true
```

`Probe.describe_text` reuses FieldStruct's own field summaries for the
input/output lines:

```
Probe (measure: none)
  Input: (free-form)
  Output:
    count (Integer, required) — accepts in (Array | Range)
  Steps:
    - compute (method)
```

### When things go wrong — error → meaning → fix

<!-- doctest -->
```ruby
class NeedsTotal < Actionable::Action
  output { required :total, :integer }
  step :noop
  def noop = nil # never sets @total
end

result = NeedsTotal.run
result.code           # => :invalid_output
result.errors[:total] # => ["is required"]
```

`errors` is FieldStruct's own collection, so beyond `errors[:field]` you get
`full_messages` — each message as a complete, field-name-prefixed sentence:

<!-- doctest -->
```ruby
failed = Actionable::Failure.new(code: :invalid)
failed.errors.add(:first_name, 'is required')

failed.errors.full_messages # => ["First name is required"]
```

| You see | It means | Do |
|---|---|---|
| `Failure(:invalid_input)` | a `required` input was missing or wouldn't coerce; **no steps ran** | check `.run`'s kwargs against the `input` schema; read `result.errors` |
| `Failure(:invalid_output)` | a strict success couldn't satisfy the `output` schema | set every `required` output ivar (or pass it via `succeed(field: …)`) |
| `result.errors[:x] == ["is required"]` | a declared field is missing/blank | set the matching ivar / pass the input |
| `DefinitionError: … declares step(s) calling :x but does not implement them` | a step / hook / case target method is missing | implement the method, or remove the step |
| `DefinitionError: output field(s) :code conflict with reserved …` | an output field name shadows a reserved result attribute/ivar | rename the field |
| a raised `StandardError` out of `.run` | a genuine bug inside a step — **not** control flow | fix it; expected error outcomes use `fail`/`fail!`, not exceptions |

### Common mistakes

1. **Bang vs plain verbs.** `fail` records but the pipeline keeps running (last
   write wins); `fail!` halts immediately. Reach for the bang to stop.
2. **Output is captured from ivars *by name*.** Only ivars matching a declared
   `output` field are captured — a typo'd `@totals` is silently dropped. Set
   `@total`.
3. **Only a strict success validates output.** A failed or skipped run captures
   output best-effort and never validates it; don't rely on output typing on a
   non-success.
4. **An invalid required input never reaches your steps.** It short-circuits to
   `Failure(:invalid_input)` before step one — put "missing argument" handling in
   the `input` schema, not a guard step.
5. **Reserved output names.** `code` / `message` / `output` / `history` /
   `errors` / `result` / `input` can't be output fields (they'd shadow the
   result). Rename them.
6. **Exceptions aren't failures.** A raised `StandardError` propagates to the
   caller; it does not become a `Failure`. Use `fail`/`fail!` for expected error
   outcomes.

### Testing your actions

`require 'actionable/rspec'` adds a matcher that runs the action and asserts the
outcome, plus stub helpers that return real result objects without executing it:

```ruby
require 'actionable/rspec'

RSpec.describe Charge do
  it 'succeeds for a positive amount' do
    expect(described_class).to perform_actionable(amount: 10).and_succeed('charged 10')
  end

  it 'fails for a non-positive amount' do
    expect(described_class).to perform_actionable(amount: -5).and_fail(:invalid_amount)
  end

  it 'skips when there is nothing to do' do
    expect(Sync).to perform_actionable(ready: false).and_skip(:not_ready)
  end
end

# Make a collaborator's action return a canned result without running it:
allow_actionable_success(Charge, output: { amount: 10 })
```

`and_raise(ErrorClass, message)` asserts a propagated exception, and every matcher
accepts a block yielding `(result, exception)` for custom assertions.

### Agent toolbox

If you're an AI assistant working in this repo, reach for the gem's machine
affordances instead of guessing:

- `Klass.describe` / `Klass.describe_text` — *see* an action's inputs, outputs,
  steps, and hooks without reading its source.
- `Actionable.registry` — enumerate registered actions (`keys`, `values`, `[]`,
  `each`).
- `Actionable::RBS.generate(Klass)` — emit RBS for an action's typed `.run` and
  output accessors (Steep / Solargraph).
- `result.errors.full_messages` — validation errors as complete sentences.
- `result.to_h` / `result.to_api_h(index:)` — a plain-Hash or HTTP-element view
  of a result, so controllers and batch endpoints don't hand-map the shape.
- The gem ships [`USAGE.md`](../USAGE.md) (full reference) and a Claude Code skill
  (`skills/actionable/SKILL.md`) — both are in `bundle show actionable`.

---

## Part 2 — Rails

The core never loads `active_*`. The Rails adapter is opt-in:

```ruby
require 'actionable/rails' # e.g. in config/initializers/actionable.rb
```

### Where Actionable fits

Use an action for a **unit of business work** — settle an invoice, onboard a
user, sync a record — anywhere you'd otherwise reach for a "service object". The
typed `input`/`output` give you a validated boundary; the three outcomes let a
controller branch on success / failure / skip honestly. It is **not** a model and
**not** a form object; it orchestrates them.

### File placement (Zeitwerk)

Put actions in an autoloaded path so Rails loads them by name. A common choice is
`app/actions/`:

```
app/actions/
  billing/
    settle_invoice.rb   # class Billing::SettleInvoice < Actionable::Action
    charge_card.rb       # class Billing::ChargeCard   < Actionable::Action
```

The path mirrors the constant (`app/actions/billing/settle_invoice.rb` ↔
`Billing::SettleInvoice`); Zeitwerk autoloads them — no `require` in app code.

### Transactions

`transactional` wraps the whole run in `model.transaction`. A success commits; a
**recorded failure or a raised exception rolls back**; a skip commits (there's
nothing to undo).

```ruby
class Billing::SettleInvoice < Actionable::Action
  transactional model: :invoice # wraps the run in Invoice.transaction
                                 # (pass a class for an explicit one)
  input { required :invoice, Invoice }

  step :debit
  step :credit

  def debit  = input.invoice.debit!
  def credit = input.invoice.credit! # a raise here rolls the debit back
end
```

### Validating with ActiveModel — `ProxyValidator`

`ProxyValidator` runs ActiveModel rules against a delegate object;
`#formatted_errors` returns a hash ready to splat into `fail`:

```ruby
class InvoiceRules < Actionable::ProxyValidator
  validates :amount, presence: true, numericality: { greater_than: 0 }
end

# inside a step:
rules = InvoiceRules.new(@invoice)
fail!(:invalid, **rules.formatted_errors) unless rules.valid?
```

### Types for Steep / Solargraph (RBS)

If your app runs a type checker, generate RBS for your actions' dynamic `.run`
and output accessors:

```ruby
# lib/tasks/actionable_rbs.rake
namespace :actionable do
  task rbs: :environment do
    classes = [Billing::SettleInvoice, Billing::ChargeCard]
    File.write('sig/actions.rbs',
               classes.map { |k| Actionable::RBS.generate(k) }.join("\n"))
  end
end
```

---

## Where to go next

- [`USAGE.md`](../USAGE.md) — every step type, option, and macro on one page.
- [`README.md`](../README.md) — the feature tour.
- `docs/origin/plan.md` — the design rationale and locked decisions (D1–D18).
