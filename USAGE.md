# Actionable — Usage

A dense, example-first reference. Every block marked for doctesting is executed
by `spec/docs_examples_spec.rb`, so it can't rot. For a gentler introduction see
the [README](README.md).

---

## Results

A run returns one of three FieldStruct-backed value objects. They can be built
directly (handy in tests):

<!-- doctest -->
```ruby
ok = Actionable::Success.new(message: 'done')
ok.success?  # => true
ok.ok?       # => true

skipped = Actionable::Skipped.new(code: :not_ready)
skipped.skipped? # => true
skipped.failure? # => false
skipped.ok?      # => true

bad = Actionable::Failure.new(code: :nope)
bad.failure? # => true
bad.ok?      # => false
```

Every result carries `code`, `message`, `errors`, `output`, and `history`.
Predicates: `success?`/`successful?`, `failure?`/`failed?`, `skipped?`, and `ok?`
(≡ `!failure?`). `to_s`/`inspect` are compact, field-sorted, and deterministic.

## Steps

Declare steps in order; each names an instance method. Steps are kept in a
per-class `Set` keyed by `[type, name]`, so a redeclared step collapses to one
entry, and the set is inherited by subclasses.

```ruby
class Example < Actionable::Action
  step :first
  step :second, if: :ready?      # :if / :unless guards (Symbol or callable)
  step :third, unless: :skip_it?
end
```

Guards take a Symbol naming a (possibly private) predicate, or a callable
`->(instance) { … }`.

## Control flow

| Verb | Records | Halts? | Returns |
|------|---------|--------|---------|
| `succeed(message = nil, **output)` | `Success` | no | `true` |
| `fail(code, message = nil, **errors)` | `Failure` | no | `false` |
| `fail_with(source, code: :invalid, message: nil)` | `Failure` absorbing `source.errors` | no | `false` |
| `skip(code = :skipped, message = nil, **output)` | `Skipped` | no | `false` |
| `succeed!` / `fail!` / `fail_with!` / `skip!` | as above | **yes** | — |
| `halt!` | keeps current `@result` | **yes** | — |

Plain (non-bang) verbs don't stop the pipeline — the final result reflects the
most recent record:

<!-- doctest -->
```ruby
class LastWins < Actionable::Action
  step :a
  step :b
  def a = fail(:nope)
  def b = succeed('recovered')
end

LastWins.run.success? # => true
```

`fail`'s keyword arguments populate the result's `errors`; `succeed`'s populate
its `output`. A raised `StandardError` is never caught — it propagates to the
caller (assert on it with the RSpec matcher's `and_raise`).

`fail_with` absorbs an arbitrary FieldStruct's validation errors into the failure
— the same machinery `:invalid_input` / `:invalid_output` use internally, exposed
as a verb for validating a side struct:

<!-- doctest -->
```ruby
EventShape = Class.new(FieldStruct::Base) { required :event_type, :string }

class Ingest < Actionable::Action
  step :validate
  def validate = fail_with!(EventShape.new, code: :invalid_event)
end

result = Ingest.run
result.code               # => :invalid_event
result.errors[:event_type] # => ["is required"]
```

`skip` takes output kwargs too (symmetry with `succeed`) — captured best-effort,
never validated — so an idempotent hit can return the existing record's data:

<!-- doctest -->
```ruby
class Dedup < Actionable::Action
  output { optional :existing_id, :integer }
  step :check
  def check = skip!(:duplicate, 'already processed', existing_id: 42)
end

result = Dedup.run
result.skipped?    # => true
result.existing_id # => 42
```

## Output

`output do … end` declares a typed schema. Matching ivars are captured at the
end of the run; `succeed`'s keyword arguments overlay them (kwargs win):

<!-- doctest -->
```ruby
class Calc < Actionable::Action
  output { optional :total, :integer }
  step :compute
  step :finish
  def compute = @total = 1
  def finish  = succeed(total: 99) # overrides the captured ivar
end

Calc.run.output.total # => 99
```

Only a **strict success** is validated. If a success can't satisfy its declared
output, the run becomes a `Failure(:invalid_output)` carrying the errors; a
failed or skipped run captures output best-effort and is never validated.

<!-- doctest -->
```ruby
class NeedsTotal < Actionable::Action
  output { required :total, :integer }
  step :noop
  def noop = nil # never sets @total
end

result = NeedsTotal.run
result.failure?       # => true
result.code           # => :invalid_output
result.errors[:total] # => ["is required"]
```

`errors` is FieldStruct's own collection, so alongside the per-field
`errors[:field]` / `errors.to_h` it answers `full_messages` — each message
rendered as a complete sentence with the humanized field name prepended
(`:base` messages pass through unprefixed):

<!-- doctest -->
```ruby
result = Actionable::Failure.new(code: :invalid)
result.errors.add(:first_name, 'is required')

result.errors.full_messages # => ["First name is required"]
```

Declared output fields delegate off the result (`result.total` →
`result.output.total`), except names that collide with the result's own
attributes (`code`/`message`/`output`/`history`/`errors`).

## Input

`input do … end` coerces `.run`'s keyword arguments into a typed struct and
exposes it as `input`:

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

A missing or uncoercible required input yields `Failure(:invalid_input)` without
running any steps. An already-built input instance can be passed instead of
keyword arguments. With no `input` block, `.run`'s arguments go to the
constructor (the free-form path).

## Batch runs

`Action.run_each(enumerable) { |item| run_args }` runs the action once per item
and collects the per-item results into a `BatchResult` (Enumerable). Each item
runs independently, so one failure never affects another. The block maps an item
to `.run` arguments (a Hash → kwargs, an Array → positional, anything else → a
single argument); omit it to pass each item directly.

<!-- doctest -->
```ruby
class Doubler < Actionable::Action
  input  { required :n, :integer }
  output { required :doubled, :integer }
  step :go
  def go = @doubled = input.n * 2
end

batch = Doubler.run_each([1, 'x', 3]) { |n| {n: n} } # 'x' -> :invalid_input
batch.size        # => 3
batch.all_ok?     # => false
batch.any_failure? # => true
batch.partial?    # => true
batch.successes.map { |r| r.output.doubled } # => [2, 6]
```

`BatchResult` answers `all_ok?` / `any_failure?` / `partial?`, exposes
`successes` / `failures` / `skips`, and `to_api_h` renders the whole batch as an
array of indexed API elements.

## Lifecycle hooks

```ruby
class Flow < Actionable::Action
  step :work
  on_success :notify   # runs only on a success
  on_failure :rollback # runs only on a failure
  on_skip    :record   # runs only on a skip
  always     :audit    # runs regardless, after the outcome hook
end
```

Dispatch is by the post-main outcome and does not re-dispatch. Hooks may use the
control-flow verbs; `halt!` in a hook stops the remaining hooks. Output is
re-captured and re-validated after each hook.

## Nested actions

```ruby
step Notify, input: %i[invoice], expose: %i[receipt]
```

`:input` names parent ivars to pass to the child's `.run`; `:expose` limits which
child outputs are absorbed back as parent ivars (default: all). A child failure
fails the parent (with the child's code/message/errors) and halts; a child skip
continues the parent like a success.

## Case steps

<!-- doctest -->
```ruby
class Branch < Actionable::Action
  input  { required :kind, :string }
  output { optional :picked, :string }
  def kind = input.kind

  case_step :kind do
    on 'a',          :pick_a
    on %w[b c],      :pick_bc      # Array membership
    on(/\Az/,        :pick_z)      # Regexp
    default          :pick_default
  end

  def pick_a       = @picked = 'a'
  def pick_bc      = @picked = 'bc'
  def pick_z       = @picked = 'z'
  def pick_default = @picked = 'default'
end

Branch.run(kind: 'b').output.picked    # => "bc"
Branch.run(kind: 'zed').output.picked  # => "z"
Branch.run(kind: 'x').output.picked    # => "default"
```

A branch target is any step target (method or nested action). When nothing
matches and there's no `default`, the case step is a no-op.

## History & measurement

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

`measure :none` (the default) records nothing. A measuring run cascades into the
nested actions it invokes. `History#took` sums step durations;
`History#to_json` serializes via Oj.

## Registry

Named action subclasses register themselves, keyed by class name:

<!-- doctest -->
```ruby
class Registered < Actionable::Action
end

Actionable.registry[Registered.name].equal?(Registered) # => true
```

`Actionable.registry` is read-only for callers: `[]`, `each`, `keys`, `values`,
`size`, `empty?`.

## Introspection — `Action.describe`

A structured, at-a-glance summary of an action (name, input/output field
metadata, ordered steps with type, hooks, measure mode, transaction config) so
humans and agents can understand it without reading source:

<!-- doctest -->
```ruby
class Probe < Actionable::Action
  output { required :count, :integer }
  step :compute
  def compute = @count = 1
end

Probe.describe[:steps].first[:type] # => :method
Probe.describe.key?(:output)        # => true
Probe.describe[:measure]            # => :none
```

`Action.describe_text` renders the same information as a human/agent-readable
multi-line summary instead of a Hash. The input/output field lines reuse
FieldStruct's own `Metadata#describe` (each field's type, required-ness, and the
options its type accepts); only hook sections that have hooks are listed:

```
Probe (measure: none)
  Input: (free-form)
  Output:
    count (Integer, required) — accepts in (Array | Range)
  Steps:
    - compute (method)
```

## Serializing a result

`Result#to_h` is a plain-Hash view (`code`, `message`, `output`/`history`
rendered to primitives, `errors` as a Hash). `Result#to_api_h(index:)` is a
compact element for an HTTP/batch response — position, `status`
(`:success`/`:failure`/`:skipped`), the `id` read off the typed output, and
`errors` — so a controller doesn't hand-map the shape:

<!-- doctest -->
```ruby
class MakeWidget < Actionable::Action
  output { required :id, :integer }
  step :build
  def build = @id = 99
end

result = MakeWidget.run
result.status              # => :success
result.to_h[:output]       # => {:id=>99}
result.to_api_h(index: 0)  # => {:index=>0, :status=>:success, :id=>99, :errors=>{}}
```

## Guardrails (`DefinitionError`)

Misconfigured actions fail loudly with `Actionable::DefinitionError` instead of a
cryptic `NoMethodError`:

- **Reserved output field names (at declaration):** an `output` field that
  shadows a result attribute (`code` / `message` / `output` / `history` /
  `errors`) or a reserved instance variable (`result` / `input`) raises
  immediately. Pick another name. (Input fields aren't affected — they're read
  via `input.x`.)
- **Missing step methods (at run start):** every method a step needs (method
  steps, case value sources and method branch targets, hook steps) must be
  implemented, or the run raises a `DefinitionError` naming the action and the
  missing method.

## Rails adapter

`require 'actionable/rails'` (never loaded by the core):

- `transactional model: :invoice` (or a class) wraps the run in
  `model.transaction`. A success commits; a recorded failure or a raised
  exception rolls back; a skip commits.
- `Actionable::ProxyValidator` runs ActiveModel rules against a delegate object;
  `#formatted_errors` returns a hash ready to splat into `fail`.

## RSpec integration

`require 'actionable/rspec'`:

- `perform_actionable(*args, **kwargs)` with `.and_succeed(message)`,
  `.and_fail(code, message)`, `.and_skip(code, message)`,
  `.and_raise(error_class, message)`, and an optional block yielding
  `(result, exception)`.
- `allow_actionable_success` / `stub_actionable_success` (and `_failure` /
  `_skip` variants) build real result objects so `.run` returns them without
  executing the action.

## RBS for your actions

```ruby
Actionable::RBS.generate(CreateInvoice)
# => RBS with a typed `.run` (from the input schema) and output accessors /
#    result delegation (from the output schema), wrapped in module nesting.
```
