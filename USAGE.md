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

Redeclaring a step replaces it: **the last declaration wins and keeps the first
one's position**. A subclass can override an inherited step's guards or options
this way without touching the parent's steps.

<!-- doctest -->
```ruby
class Checkout < Actionable::Action
  step :load
  step :charge
end

class DryCheckout < Checkout
  step :charge, if: :live? # replaces Checkout's :charge, still after :load
end

DryCheckout.steps.map(&:name)       # => [:load, :charge]
DryCheckout.steps.to_a.last.options # => {if: :live?}
Checkout.steps.to_a.last.options    # => {}
```

| Redeclared with | Result |
|---|---|
| `step :x` then `step :x, if: :ok?` (same class or a subclass) | one `:x` step, guarded by `:ok?`, at the first `:x`'s position |
| `step Child` then `step Child, expose: []` | one nested step with the last `:input`/`:expose` |
| `case_step(:x) { … }` then `case_step(:x) { … }` | one case step with the last block's branches |
| `on_success :x` then `on_success :x, if: :ok?` (likewise `on_failure` / `on_skip` / `always`) | one hook with the last options, at the first one's position |
| `step :x` and `case_step :x` | **two** steps — a method step and a case step are different types |

Each hook phase is its own list, so `on_success :x` and `always :x` are two
hooks. There is no way to remove an inherited step or hook; guard it off with
`if:` / `unless:` instead.

```ruby
class Example < Actionable::Action
  step :first
  step :second, if: :ready?      # :if / :unless guards (Symbol or callable)
  step :third, unless: :skip_it?
end
```

Guards take a Symbol naming a (possibly private) predicate, or a callable
`->(instance) { … }`. Step, hook and `case_step` methods may be private too.
`@result` is reserved for the run's result: a step that assigns it anything
else raises `Actionable::DefinitionError`.

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

**`fail` is not `raise` inside an action.** `Actionable::Action#fail` replaces
Ruby's `Kernel#fail` (the alias of `raise`) in steps, hooks and any instance
method of the action, so `fail 'something broke'` cannot raise. A `fail` /
`skip` code must be an identifier: letters, digits and underscores, not
starting with a digit, optionally ending in `?` or `!` (`:card_expired`,
`:ok?`, `'NotFound'`). A sentence, a dashed or dotted string, or a class
raises `ArgumentError` at the call, naming the action and suggesting `raise`.
To signal a bug, use `raise`; to stop with a failure, use
`fail!(:code, 'message')`:

```ruby
class Habit < Actionable::Action
  step :check
  def check = fail('card expired') # meant: raise
end

Habit.run # ArgumentError: Habit: failure code "card expired" is not an identifier; ...
```

<!-- doctest -->
```ruby
class Fixed < Actionable::Action
  step :check
  step :finish
  def check = fail!(:card_expired, 'card expired') # records and halts
  def finish = succeed
end

Fixed.run.code # => :card_expired
```

A one-word string (`fail 'boom'`) is a valid code, so it still records a
failure `:boom` instead of raising. Code outside the action (a plain helper
object, a model) still gets `Kernel#fail`.

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

### Where a plain verb may go

`fail`, `fail_with`, `skip` and `succeed` record an outcome **and keep
running**, so in `fail :card_expired if card.expired?` followed by `notify`,
the `notify` still runs (`fail!` was meant). The rule: **in a step or hook method, a plain
recording verb must be the method's last expression, or explicitly end it.**
Bang verbs (`fail!`, `skip!`, `succeed!`, `fail_with!`) can go anywhere.

On an action's first run, every step method (case-step branch targets
included), lifecycle hook method (`on_success` / `on_failure` / `on_skip` /
`always`, and `after_commit` with the Rails adapter) is checked by parsing its
source with Prism. A misplaced verb raises `DefinitionError` naming the action,
method, `file:line` and verb, with the fix ("use fail! to stop here, or make it
the method's last expression"). The check runs once per class (a later run pays
nothing for it), and a failing check raises on every run until fixed. It is
skipped where it can't be done: no Prism (Ruby 3.2 without the `prism` gem; it
is a default gem from 3.3), or no readable source (a method from `eval` or
`define_method`).

| The verb call (`fail`, `fail_with`, `skip`, `succeed`, or `self.fail` …) | |
|---|---|
| is the method's last statement (a modifier `fail :x if bad?` counts as the statement) | OK |
| is the last statement of an `if` / `elsif` / `else` / `unless` / ternary / `case`-`when` / `case`-`in` / `rescue` / `ensure` branch, or the right side of `&&` / `and` / `\|\|` / `or`, whose construct is itself last | OK |
| is returned: `return fail(:x) if bad?`, or followed directly by `return` | OK |
| is the last statement of a block or loop body (or followed directly by `next` / `break` there), and the block's call is itself last: `items.each { \|i\| fail :bad if i.bad? }` | OK |
| is followed by an `ensure` (cleanup runs even after a bang verb) | OK |
| has another receiver (`gateway.fail`, `items.skip(1)`) | not checked |
| is followed by more code in the method, a branch whose construct is followed by more code, or a begin body that has an `else` | **offense** |
| is the end of a block or loop body whose call is followed by more code: `items.each { … fail :bad … }; save` | **offense** |
| is the left side of `and` / `or`: `fail(:x) and return` never returns (`fail` returns `false`); write `return fail(:x)` | **offense** |
| is nested in a larger expression: `log(fail(:x))`, `@ok = fail(:x)` | **offense** |

Methods that aren't steps or hooks (helpers they call) are not checked.

**Turning the first-run check off.** It is on by default. As an escape hatch
while upgrading (an app with misplaced verbs you can't fix yet), switch it off
for the whole process, e.g. in an initializer:

```ruby
Actionable.verb_position_check = false # Actionable.verb_position_check? reads it back
```

Off, `run` never parses a method's source and never loads Prism. **The
`Actionable/VerbNotLast` cop is then the only guard**, so run it in CI until the
switch is back on. A class that ran while the check was off is checked on its
first run after it's turned back on. The switch doesn't cover the code check at
the `fail` / `skip` call (sentence codes raise `ArgumentError`): that check is a
per-call regex match, not a parse, costs about 0.4 µs, and catches a wrong
result code rather than a style problem.

**The RuboCop cop.** The gem ships `Actionable/VerbNotLast`, the same rules as
a lint, *not* loaded by `require 'actionable'`. Opt in from `.rubocop.yml`:

```yaml
plugins:
  - actionable:
      require_path: actionable/rubocop
```

(or `require: [actionable/rubocop]` on RuboCop < 1.72). The cop only sees one
file: it checks a class that is an action and declares `step` / `case_step`,
and the methods that class names in a step, case-step branch or hook
declaration. Methods a parent class declares as steps are left to the
first-run check.

A class counts as an action when its superclass is in `ActionBaseClasses`
(full names; default `Actionable::Action` and `ApplicationAction`; a leading
`::` is ignored), or is a class defined in the same file (`class Base < …` or
`Base = Class.new(…)`, any depth) whose own superclass does. The superclass
name resolves the way Ruby looks it up: from the enclosing `module` / `class`
outwards (a compact `class A::B` opens only `A::B`), to the first class,
module or listed base by that name, else the top level. So `Base` inside
`module B` is `B::Base` when the file defines one, not an `A::Base` action,
and a file's own `Legacy::ApplicationAction` shadows the listed one. Any
other class is left alone, so a dry-transaction
(`include Dry::Transaction` with its own `step`) gets no false positives, and
neither does a class that reopens an action without naming its superclass
(the first-run check still covers it). Name your app's own base classes:

```yaml
Actionable/VerbNotLast:
  ActionBaseClasses:
    - Actionable::Action
    - ApplicationAction
    - Billing::BaseAction
```

The list replaces the default, so keep the two defaults in it if you need them.

## Declared failures

`fails(code, message = nil, **metadata)` declares one failure code an action can
end with. The keywords after the message are neutral per-code metadata: the gem
stores them, attaches them to the failure, and shows them in `describe`, but
never reads them. Your app gives the keys their meaning. A `fail` or `fail_with`
with a declared code carries its metadata as `result.metadata`, and its declared
message when the call gives none. `declared_failures` reads the declarations
back as `{code => metadata}`, and `failure_declarations` as
`{code => {message:, metadata:}}`:

<!-- doctest -->
```ruby
class Charge < Actionable::Action
  fails :refused, 'the card was refused', kind: :rejected
  fails :not_found, kind: :not_found

  step :charge
  def charge = fail!(:refused, nil, kind: 'is not a known kind')
end

result = Charge.run
result.code           # => :refused
result.message        # => "the card was refused"
result.metadata       # => {kind: :rejected}
result.errors[:kind]  # => ["is not a known kind"]
Charge.declared_failures # => {refused: {kind: :rejected}, not_found: {kind: :not_found}}
```

Nothing but `**errors` follows `fail`'s message, so an error on a field named
like a metadata key (`kind` above) stays an error. Declarations are inherited,
and a subclass can add more. Declaring `:invalid_input` or `:invalid_output`
attaches that metadata to the failures the gem builds itself. A failure whose
code isn't declared has `metadata == {}`, and `Failure#to_h` includes it.

**Strict once declared.** An action that declares at least one code may only fail
with codes it declares (`allows_failure_code?(code)` answers whether it may). Any other `fail` / `fail!` / `fail_with` / `fail_with!`
raises `Actionable::DefinitionError` from the call itself, naming the code and
the declared list:

<!-- doctest -->
```ruby
class Refund < Actionable::Action
  fails :refused, kind: :rejected
  step :go
  def go = fail!(:timeout)
end

begin
  Refund.run
rescue Actionable::DefinitionError => e
  e.message.include?('fails with :timeout, which it does not declare') # => true
end
```

Two cases stay unchecked, so existing actions keep working unchanged:

- an action that declares no failures fails with any code, as before;
- the codes the gem emits itself, `Actionable::Action::GEM_FAILURE_CODES`
  (`:invalid_input` and `:invalid_output`), are always allowed.

`fail_with`'s default code `:invalid` is not exempt: the action writes that
`fail_with`, so a declaring action declares `:invalid` or passes its own `code:`.

## Declared skips

`skips(code, message = nil, **metadata)` declares one skip code an action can end
with, so skips get the same contract as failures (decision D21). The metadata is
neutral, as with `fails`. A `skip` or `skip!` with a declared code
carries its metadata as `result.metadata`, and its declared message when the
call gives none. `declared_skips` reads the declarations back as
`{code => metadata}`, and `skip_declarations` as `{code => {message:, metadata:}}`:

<!-- doctest -->
```ruby
class SyncField < Actionable::Action
  skips :not_ready, 'the field is not created yet', retry: true
  skips :already_synced, retry: false

  step :sync
  def sync = skip!(:not_ready)
end

result = SyncField.run
result.skipped?   # => true
result.code       # => :not_ready
result.message    # => "the field is not created yet"
result.metadata   # => {retry: true}
SyncField.declared_skips # => {not_ready: {retry: true}, already_synced: {retry: false}}
```

Declarations are inherited, and a subclass can add more. A skip whose code isn't
declared has `metadata == {}`, and `Skipped#to_h` includes it.

**Strict once declared.** An action that declares at least one skip code may only
skip with codes it declares (`allows_skip_code?(code)` answers whether it may).
Any other `skip` / `skip!` raises `Actionable::DefinitionError` from the call
itself. The gem emits no skip codes of its own, so nothing is exempt, and that
includes `skip`'s implicit default `:skipped`: a declaring action that calls a
bare `skip!` declares `:skipped` too.

<!-- doctest -->
```ruby
class Archive < Actionable::Action
  skips :already_archived
  step :go
  def go = skip!
end

begin
  Archive.run
rescue Actionable::DefinitionError => e
  e.message.include?('skips with :skipped, which it does not declare') # => true
end
```

An action that declares no skips skips with any code, as before. Declared
failures and declared skips are independent, so declaring one never makes the
other strict.

## Typed outcomes

`typed_outcomes` gives a skip and a failure an output contract of their own,
the way `output` gives one to a success (decision D23). It is opt-in and
inherited, so a host base class can turn it on for every action beneath it;
`typed_outcomes?` reads it, and `typed_outcomes enabled: false` turns it off
again for a subclass.

A block on `skips` or `fails` declares the output a result with that code
carries, in the same FieldStruct DSL as `output`. `skip_output_schema(code)` and
`failure_output_schema(code)` read it back, and `describe` shows its fields.
Under typed outcomes, a failure takes its output from the `output:` keyword of
`fail` / `fail!` (and of `fail_with` / `fail_with!`); every other keyword is
still an error:

<!-- doctest -->
```ruby
class ActivateKey < Actionable::Action
  typed_outcomes
  input { required :id, :integer }
  output { required :id, :integer }

  skips(:already_active) { required :id, :integer }
  fails(:invalid) { optional :field, :string }

  step :activate

  def activate
    return skip!(:already_active, nil, id: input.id) if input.id == 1
    return fail!(:invalid, 'bad id', output: {field: 'id'}, id: 'is negative') if input.id.negative?

    @id = input.id
  end
end

skipped = ActivateKey.run(id: 1)
skipped.class        # => ActivateKey::Skipped
skipped.id           # => 1
failed = ActivateKey.run(id: -1)
failed.class         # => ActivateKey::Failure
failed.output.field  # => "id"
failed.errors[:id]   # => ["is negative"]
ActivateKey.run(id: 2).class # => ActivateKey::Success
```

The rules:

- **A code with a schema** is built from the keywords it was recorded with,
  never from instance variables, and validated like a success: output that
  breaks the schema ends the run as `invalid_output`. This holds whether or not
  `typed_outcomes` is on, since the block itself is the opt-in for that code.
  So the block also ends instance-variable capture for that code: after
  `@note = 'x'; skip!(:dup)`, a `skips(:dup) { required :note, :string }`
  ends the run as `invalid_output`, because `note:` was never passed.
- **A code without one** carries an empty output under typed outcomes. Without
  them it keeps the old best-effort capture into the success schema. The
  failures the gem builds (`invalid_input`, `invalid_output`) keep their
  output either way, because the invalid struct is what explains them.
- **Output with nowhere to go is refused.** Under typed outcomes, output keywords
  on a code without a schema raise `Actionable::DefinitionError`, naming the
  code and asking for a `fails :code do … end` (or `skips`) schema. `output:`
  must be a Hash or a FieldStruct; anything else raises `ArgumentError`.
- **Result classes.** `.run` returns the action's own `Success`, `Failure` or
  `Skipped`, defined inside it. Each is a subclass of the gem class, or of the
  parent action's own for a subclass, so `result.is_a?(Actionable::Failure)`
  still holds. An action that already has its own constant by one of those names
  is refused. A host's own result subclass is returned as it is, which the
  generated RBS does not describe: it still types `.run` as the action's own
  classes, a known gap.
- **Nested failures.** A child's failure that crosses becomes the parent's own
  `Failure`. Its output is judged by the schema the *parent* declares for the
  code, and the parent must still declare the code. A parent without typed
  outcomes gets a plain `Actionable::Failure`, never the typed child's class.
  The gem's own `invalid_input` / `invalid_output` cross with their output and
  are not judged by a parent schema.
- **Stubs.** The RSpec stub helpers return the action's own result classes too,
  with the output shaped as a real run would shape it: built through the code's
  schema (an `ArgumentError` when it breaks the schema, since a real run would
  end as `invalid_output` instead), and empty for a code without one (output
  given for such a code raises `ArgumentError`).
- **RBS.** `Actionable::RBS.generate` types `.run` as
  `(Success | Skipped | Failure)`, with each `code` and `output` narrowed to
  what that outcome can carry (see [RBS for your actions](#rbs-for-your-actions)).
  The readers a result delegates to its output are declared on `Skipped` and
  `Failure` too.

Two things change for a spec when an action turns typed outcomes on. Results
compare by class, so `ActivateKey.run(id: 2) == Actionable::Success.new(...)` is
false even with the same output; compare with `ActivateKey::Success`, or use
`be_success` and the output. And the `allow_actionable_*` / `stub_actionable_*`
helpers return a new object of the action's own class, not one you built with
`actionable_failure_result`, so assert on what the helper returns.

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
running any steps. `input` with no block reads the declared schema, like `output`. An already-built input instance can be passed instead of
keyword arguments. With no `input` block, `.run`'s arguments go to the
constructor (the free-form path).

### Discriminated input

`input_for(discriminator) { … }` picks the input schema at run time from a
discriminator value — typed input for a polymorphic payload. Branches use the
same matching as `case_step` (`==`, Array membership, `Regexp`); an unmatched
value with no `default` short-circuits to `Failure(:invalid_input)`.

<!-- doctest -->
```ruby
SaleShape   = Class.new(FieldStruct::Base) { required :amount, :integer }
RefundShape = Class.new(FieldStruct::Base) { required :original_id, :integer }

class Ingest < Actionable::Action
  input_for :event_type do
    on 'sale',   SaleShape
    on 'refund', RefundShape
  end
  output { optional :amount, :integer }
  step :capture
  def capture
    @amount = input.amount if input.respond_to?(:amount)
  end
end

Ingest.run(event_type: 'sale', amount: '5').output.amount # => 5
Ingest.run(event_type: 'wat').code                        # => :invalid_input
```

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
control-flow verbs. A bang verb in a hook (`fail!`, `skip!`, `succeed!`) records
its result *and* stops the remaining hooks of its phase, so
`fail!(:verification_failed)` in `on_success` makes the run a `Failure` (and
rolls back a `transactional` action); `halt!` stops them and keeps the current
result. A nested action used as a hook that fails counts as a `fail!`.

The outcome hooks and the `always` hooks are separate phases, so `always` runs
even after an outcome hook halts, and sees the adopted result:

| A halt in… | Still runs | Final result |
|---|---|---|
| an outcome hook (`on_success` / `on_failure` / `on_skip`) | every `always` hook (not the rest of that outcome category) | the halting hook's |
| an `always` hook | nothing (the rest of the `always` hooks are skipped) | the halting hook's |

`always` hooks run inside the `transactional` transaction like the other hooks,
and appear in the history when measuring. Output is re-captured and
re-validated after each hook, and `succeed`/`skip` kwargs keep winning over
ivars on every refresh.

For side effects that must wait until the database work really committed (an
email, a webhook, an enqueue), the Rails adapter adds an `after_commit` hook
kind — see [Rails adapter](#rails-adapter).

## Nested actions

```ruby
step Notify, input: %i[invoice], expose: %i[receipt]
```

`:input` names parent ivars to pass to the child's `.run`; `:expose` limits which
child outputs are absorbed back as parent ivars (default: all). Only fields the
child actually set (an ivar it assigned or a `succeed`/`skip` kwarg) are
absorbed, so a field it left nil or at its default never overwrites the
parent's value. A child failure
fails the parent and halts; a child skip continues the parent like a success.

The child's failure crosses intact: its code, message, every error (whatever the
field is called), its `metadata`, and its result class. It doesn't go through
the parent's `fail`, so an override of `fail` in a host base class doesn't see
it. The parent's own declaration for that code fills in metadata keys the child
didn't set. A parent that declares failures must declare the codes its children
can fail with, since they become its own.

A child skip never becomes the parent's outcome (decision D17), so a parent that
declares skips does not declare its children's skip codes. The child's skip and
its metadata stay on the child's result.

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

A branch (or the `default`) takes `if:` / `unless:` like any step. The branch
is picked by value alone; its guard then decides whether the target runs. A
matched branch whose guard opts out does nothing: it does not fall through to
the next branch or the `default`.

<!-- doctest -->
```ruby
class Notify < Actionable::Action
  input  { required :kind, :string }
  output { optional :sent, :string }
  def kind = input.kind
  def sms_enabled? = false

  case_step :kind do
    on 'sms',  :send_sms, if: :sms_enabled?
    default    :send_email
  end

  def send_sms   = @sent = 'sms'
  def send_email = @sent = 'email'
end

Notify.run(kind: 'sms').output.sent    # => nil (guarded out, no fall-through)
Notify.run(kind: 'push').output.sent   # => "email"
```

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

`measure :none` (the default) records nothing. `measure :sampled, rate: 0.1`
records a fraction of runs (rate between 0 and 1) for low-overhead production
observability — when a run is sampled in, it measures fully and cascades into its
nested actions. A measuring run cascades into the nested actions it invokes.
`History#took` sums step durations; `History#to_json` serializes via Oj.
Measurement state is fiber-local: a nested action run inside another Fiber
(including `Enumerator#next`) is not recorded in the parent's history.

<!-- doctest -->
```ruby
class Sampled < Actionable::Action
  measure :sampled, rate: 1.0 # always, for a deterministic example
  step :work
  def work = nil
end

Sampled.run.history.steps.map(&:name) # => [:work]
```

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
metadata, ordered steps with type, declared failures and skips, hooks, measure
mode, transaction config) so humans and agents can understand it without reading
source. `describe[:failures]` and `describe[:skips]` each map a declared code to
`{message:, metadata:}`:

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
options its type accepts). Declared failures, declared skips and hook sections
are listed only when there are any:

```
Probe (measure: none)
  Input: (free-form)
  Output:
    count (Integer, required) — accepts in (Array | Range)
  Steps:
    - compute (method)
```

With `fails :refused, 'the card was refused', kind: :rejected` declared, a
`Failures:` section follows the steps:

```
  Failures:
    - refused (kind: :rejected): the card was refused
```

With `skips :not_ready, 'the field is not created yet', retry: true` declared, a
`Skips:` section follows the failures:

```
  Skips:
    - not_ready (retry: true): the field is not created yet
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
  `errors` / `metadata`) or a reserved instance variable (`result` / `input`) raises
  immediately. Pick another name. (Input fields aren't affected — they're read
  via `input.x`.)
- **Undeclared failure codes (at the `fail` call):** once an action declares a
  failure with `fails`, failing with a code it doesn't declare raises. See
  [Declared failures](#declared-failures).
- **Undeclared skip codes (at the `skip` call):** once an action declares a skip
  with `skips`, skipping with a code it doesn't declare raises, the default
  `:skipped` included. See [Declared skips](#declared-skips).
- **Missing step methods (at run start):** every method a step needs (method
  steps, case value sources and method branch targets, hook steps) must be
  implemented, or the run raises a `DefinitionError` naming the action and the
  missing method.
- **A plain verb with code after it (at first run):** a `fail` / `fail_with` /
  `skip` / `succeed` that isn't its step or hook method's last expression raises a
  `DefinitionError` naming the action, method, `file:line` and verb. See
  [Where a plain verb may go](#where-a-plain-verb-may-go).
- **Sentence codes (at the `fail` / `skip` call):** a code that isn't an
  identifier raises `ArgumentError`. See [Control flow](#control-flow).

## Rails adapter

`require 'actionable/rails'` (never loaded by the core). CI runs it on
ActiveRecord 7.1 and 8.x; only `after_commit` needs 7.2:

- `transactional model: :invoice` (or a class) wraps the run in
  `model.transaction`. A success commits; a recorded failure or a raised
  exception rolls back; a skip commits. Inside a transaction that is already
  open, the action takes its own savepoint (`requires_new: true`), so its failed
  writes roll back without the outer transaction committing them; pass
  `requires_new: false` to join the outer one instead. Lifecycle hooks run inside the
  transaction, so a hook's writes share its fate and its external side effects
  fire before the commit.
- `after_commit :method` (or a nested action: `after_commit Notify, input: %i[order]`,
  with `:if` / `:unless` guards like any hook) runs a side effect only after the
  database work really committed. Needs ActiveRecord >= 7.2 (it is built on
  `ActiveRecord.after_all_transactions_commit`); declaring it on an older
  ActiveRecord, or with ActiveRecord not loaded, raises a `DefinitionError`.
  Existing hooks are unchanged. Inherited like the other hooks. `describe`
  lists them under `hooks[:after_commit]`, and `describe_text` adds an
  `after_commit:` line when there are any.

  | Scenario | Runs? | When |
  |---|---|---|
  | `transactional` action succeeds at the top level | yes | right after its transaction commits, before `.run` returns |
  | succeeds inside an outer `Model.transaction` | yes | after the **outermost** transaction commits, not at the action's savepoint |
  | succeeds, then an enclosing transaction rolls back | no | — |
  | the run ends in a `Failure` | no | its writes rolled back, so nothing committed |
  | the run ends in a `Skipped` | no | a skip's writes still commit, but there was nothing to do, so no side effect |
  | non-transactional action, no transaction open | yes | immediately after the run, before `.run` returns |
  | nested actions, each with `after_commit` | each once, child first | after the outermost commit; a child's hook is dropped if a transactional parent then fails |

  The run is already over when the hook fires: it can't change the result (a
  halting verb only stops the remaining `after_commit` hooks) and it is not
  recorded in the history. An exception it raises propagates (decision D4) from
  wherever the commit happened — the outer `transaction` call, or `.run` when no
  transaction was open — after the writes are committed.
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
  executing the action. `actionable_failure_result(code:, message:, output:,
  errors:, metadata:)` and `actionable_skip_result(code:, message:, output:,
  metadata:)` build a failure or a skip without stubbing anything.

On an action that declares failures, the RSpec support holds to the
declarations. A stubbed failure carries the declared metadata for its code (and
the declared message when you give none), and a stub or `and_fail` with a code
the action doesn't declare raises `ArgumentError`, since it would test a
failure the action can never return. The exemptions match the runtime: actions
that declare none, and `GEM_FAILURE_CODES`.

Skips work the same way on an action that declares skips. A stubbed skip
carries the declared metadata and message for its code, and a stub or
`and_skip` with an undeclared code raises `ArgumentError`. As at runtime, the
default `:skipped` is not exempt, so `allow_actionable_skip(action)` with no
`code:` raises unless the action declares `:skipped`. A bare `and_skip` names no
code and is always accepted.

## Outcome coverage

`require 'actionable/rspec/coverage'` (decision D22) records every real `.run`
of a named action as `[class name, outcome, code]` and, at the end of the
suite, reports each action's outcomes that no spec reached. It is off unless
required, and `actionable/rspec` does not load it.

An action's expected outcomes come from its declarations at run time, as
outcome keys. `"success"` is always expected, plus `"failure:<code>"` for each
`declared_failures` code and `"skipped:<code>"` for each `declared_skips` code.
`Coverage.expected_outcomes(SomeAction)` lists them.

A run counts only when the action really ran. Nested `Steps::Action` runs and
each `run_each` item count. A stub of `.run` replaces the recording, so a
stubbed result never counts as tested; the gem's stub helpers note their runs
in `Coverage.stubbed`, which the report shows as "Stubbed only".

```ruby
# spec/support/actionable_coverage.rb
require 'actionable/rspec/coverage'

Actionable::Coverage.loader = -> { Rails.application.eager_load! }
Actionable::Coverage.baseline = 'spec/actionable_coverage_baseline.yml'
```

Settings, all on `Actionable::Coverage`:

| Setting | Default | Meaning |
|---|---|---|
| `root` | `Actionable::Action` | Report its named descendants that have steps. Anonymous classes and actions with no steps (abstract bases) are left out, and so is a class whose name no longer resolves to it. |
| `include_prefixes` / `exclude_prefixes` | `[]` | Name filters. A String matches as a prefix, a Regexp by `match?`. |
| `loader` | `nil` | Called before the actions are listed. A class that was never loaded can't be reported, so a Rails host eager-loads here. |
| `gem_codes` | `[]` | Gem codes to expect too. `:invalid_input` counts for an action whose input has a required field, `:invalid_output` for one whose output does. |
| `only_observed` | `false` | Report only actions with at least one real run, so a targeted run doesn't flag every action it never touched. |
| `baseline` | `nil` | Path to a committed JSON or YAML baseline of known gaps (below). |
| `new_gap_hint` | `DEFAULT_NEW_GAP_HINT` | The advice after "New untested outcomes." in the mismatch message. The default, `'Write a spec that reaches each one, or add it to the baseline:'`, offers both fixes; a host whose baseline only shrinks sets its own. |

`reset_config!` restores the defaults; `enable!`, `disable!`, `enabled?` and
`reset!` control the recording, and `observed` holds the real runs.

The report (`Actionable::Coverage::Report`) is a table of each action's
never-reached outcomes followed by the totals:

```text
Actionable outcome coverage
  Action           Never reached                       Stubbed only
  Billing::Charge  failure:refused, failure:not_found  failure:refused
  Billing::Refund  success
Actions: 2  Expected outcomes: 4  Reached: 1  Missing: 3
```

`rows`, `totals`, `to_h` and `to_json` give the same data to a machine, and
`ACTIONABLE_COVERAGE_JSON=path` writes the JSON next to the text.

**The baseline.** Missing outcomes alone never fail a suite. With
`Coverage.baseline` set to a file of `{"Action::Name" => [outcome keys]}`,
the report fails in two cases, and its message lists each entry to change:

- an untested outcome the baseline doesn't list (a new gap: write the spec,
  or add the entry);
- a baseline entry that is now covered, is no longer declared, or names an
  action that no longer exists (remove the entry).

`Report#to_baseline` returns the current gaps in that shape and
`#write_baseline(path)` writes them, as YAML for a `.yml`/`.yaml` path and JSON
otherwise. Running the report with `ACTIONABLE_COVERAGE_UPDATE_BASELINE=true`
rewrites `Coverage.baseline` from the current gaps instead of checking it,
which is how a host adopts the baseline and how it accepts a deliberate change.

**Unsharded suites.** The `after(:suite)` hook prints the report and, when it
disagrees with the baseline, raises `Coverage::BaselineMismatch`, which fails
the run.

**Sharded suites.** When `ACTIONABLE_COVERAGE_FILE` names a path, the hook
writes that process's runs there (`Coverage.write(path)`) and reports nothing,
since one shard can't judge the whole suite. Each rspec process needs its own
path. A later step merges the files with the expected outcomes computed in
that process: `Coverage.report!(files: 'tmp/actionable_coverage/*.json')`, or
`Report.new(files:)` for the report alone. A glob that matches no file raises
rather than reporting every outcome missing, and `Coverage.read(path)` reads
one file back. From a Rails CI step:

```bash
RAILS_ENV=test bin/rails runner 'require "./spec/support/actionable_coverage"; Actionable::Coverage.report!(files: "tmp/actionable_coverage/*.json")'
```

The baseline is only meaningful for a full run. A local or targeted run
reports every action it didn't touch, so set `baseline` only in CI and, for
local runs, `only_observed = true` (or require the file only when an env var
asks for it).

## Background jobs

`require 'actionable/job'` — a framework-agnostic helper that runs an action
inside a background job and maps its result to a queue disposition:
`Actionable::Job.disposition(result)` returns `:ack` (a success or skip), `:retry`
(a transient failure), or `:discard` (a failure whose code is in the
non-retryable set, default `%i[invalid_input invalid_output not_found]`).

Include `Actionable::Job::Mixin` into your Sidekiq worker or ActiveJob job and
call `run_actionable` from `perform`. It records `actionable_result`, returns for
an ack/discard, and raises `Actionable::Job::RetryableFailure` for a retry so the
queue applies its own backoff. A genuine exception inside the action propagates
unchanged (the queue retries it):

```ruby
require 'actionable/job'

class ProjectEventJob
  include Sidekiq::Job              # or: ActiveJob::Base
  include Actionable::Job::Mixin

  def perform(event_id)
    run_actionable(ProjectApiEvent, event_id: event_id)
  end

  # optional: customize which failure codes are permanent (not retried)
  def actionable_permanent_codes = %i[invalid_input not_found unprocessable]
end
```

**Retry from declared metadata (opt-in).** Declared metadata is neutral by
default (D20/D21): `skips :not_ready, retry: true` alone still acks. An action
that calls `honor_retry_metadata` (added to `Actionable::Action` by
`require 'actionable/job'`, so load the adapter before the action) lets the
`retry:` key of its declared codes decide the disposition:

| Result | `retry: true` | `retry: false` | no `retry:` key |
|---|---|---|---|
| `Failure` | `:retry` (even a permanent code) | `:discard` (even a transient code) | default mapping |
| `Skipped` | `:retry` | `:ack` | `:ack` |

`run_actionable` raises `RetryableFailure` for every `:retry`, a retried skip
included (`e.result` is the `Skipped`), so the same queue configuration covers
both: Sidekiq retries any raised job by default; under ActiveJob declare
`retry_on Actionable::Job::RetryableFailure` (otherwise the error goes to the
queue backend's own handling, as for any transient failure). CI checks both
against the real backends: ActiveJob's test adapter with `retry_on` (a retry is
a re-enqueue; once attempts run out the error is raised) and Sidekiq's inline
testing mode. The macro is inherited, and a
subclass backs out with `honor_retry_metadata(enabled: false)`;
`honor_retry_metadata?` reads it. Without a job, ask
`Actionable::Job.disposition(result, honor_retry: true)`.

<!-- doctest -->
```ruby
require 'actionable/job'

class Reindex < Actionable::Action
  honor_retry_metadata
  skips :not_ready, retry: true

  step :reindex
  def reindex = skip!(:not_ready)
end

Reindex.honor_retry_metadata?                                   # => true
Actionable::Job.disposition(Reindex.run, honor_retry: true)     # => :retry
Actionable::Job.disposition(Reindex.run)                        # => :ack
```

## RBS for your actions

```ruby
Actionable::RBS.generate(CreateInvoice)
# => RBS with a typed `.run` (from the input schema) and output accessors /
#    result delegation (from the output schema), wrapped in module nesting.
```

For an action with `input` and `output` schemas:

```ruby
class CreateInvoice < Actionable::Action
  input do
    required :amount, :integer
    optional :tags, :array, of: :string
  end
  output { required :total, :integer }
  step :compute

  def compute
    @total = input.amount * 2
  end
end
```

```
class CreateInvoice < ::Actionable::Action
  def self.run: (amount: ::Integer, ?tags: ::Array[::String?]?) -> Result
              | (InputSchema input) -> Result

  def input: () -> InputSchema

  @total: ::Integer?

  class InputSchema < ::FieldStruct::Base
    attr_reader amount: ::Integer
    def amount=: (::Integer? value) -> ::Integer?
    attr_reader tags: ::Array[::String?]?
    def tags=: (::Array[::String?]? value) -> ::Array[::String?]?
  end

  class Output < ::FieldStruct::Base
    attr_reader total: ::Integer
    def total=: (::Integer? value) -> ::Integer?
  end

  class Result < ::Actionable::Result
    def output: () -> Output
    def total: () -> ::Integer
  end
end
```

Field types come from `FieldStruct::RBS.type_for`, so they match what
`FieldStruct::RBS.generate` emits for a named struct: writers take and return
`T?`, scalar array elements are nullable, a field's `rbs_type:` override wins,
and a `:value` field is `untyped`. Types describe a valid instance: check
`valid?` before trusting them on a struct that may not be.

- **`InputSchema`, like `Output` and `Result`, exists only in RBS.** At runtime
  the input schema is an anonymous class (`CreateInvoice.input`), and a step's
  `input` is an instance of it. Generation raises `ArgumentError` when the
  action declares a fixed `input` schema and Ruby already resolves
  `CreateInvoice::InputSchema` (a constant by that name on the action, an
  ancestor or an included module), since the RBS name would then describe
  something else. An `input_for` (discriminated) action gets no `InputSchema`.
- **Output instance variables** (`@total: ::Integer?`) are declared so steps
  that assign them type-check; each is nullable because it is unset until a
  step assigns it. The generated RBS owns these declarations: **don't declare
  them again in your own sig files**, since RBS rejects an instance variable
  declared in two places.

An action that declares failures also gets a `failure_code` type alias listing
every code it can fail with, the declared ones first, then `GEM_FAILURE_CODES`:

```
type failure_code = :refused | :not_found | :invalid_input | :invalid_output
```

An action that declares skips gets a `skip_code` alias the same way, after
`failure_code` when both are declared. It lists the declared codes only, since
the gem emits no skips of its own:

```
type skip_code = :not_ready | :already_synced
```

Without typed outcomes the aliases are type aids only: nothing in the generated
`Result` uses them, since `code` is shared by all three outcomes. Under
`typed_outcomes` (decision D23) they type each outcome's `code`, and `.run`
returns the action's own result classes, each with the output it can carry:

```
def self.run: (id: ::Integer) -> (Success | Skipped | Failure)

class AlreadyActiveSkipOutput < ::FieldStruct::Base ... end
class InvalidFailureOutput < ::FieldStruct::Base ... end

class Success < ::Actionable::Success
  def code: () -> :success
  def output: () -> Output
end

class Skipped < ::Actionable::Skipped
  def code: () -> skip_code
  def output: () -> (AlreadyActiveSkipOutput | ::Hash[::Symbol, untyped])
end

class Failure < ::Actionable::Failure
  def code: () -> failure_code
  def output: () -> (InvalidFailureOutput | AlreadyActiveSkipOutput | Output | ::Hash[::Symbol, untyped])
end
```

A failure's output also admits every skip schema and `Output`, since output that
breaks one ends the run as `invalid_output` carrying it. For the same reason
every reader declared on `Failure` is nullable (`def key: () -> ::KeySummary?`):
a broken output can lack a required field. A code with no schema, or no
declarations at all, types as a Hash and a plain `::Symbol`.

### Base actions

The action is declared with its real superclass, and every named ancestor up to
`Actionable::Action` is declared before it, without members, so the RBS resolves
(and `rbs validate` passes) even when nobody generates your abstract bases:

```ruby
class ApplicationAction < Actionable::Action; end
module Codes
  class BaseAction < ApplicationAction; end
  class DecideMapping < BaseAction
    output { required :id, :integer }
  end
end

Actionable::RBS.generate(Codes::DecideMapping)
```

```
class ApplicationAction < ::Actionable::Action
end

module Codes
  class BaseAction < ::ApplicationAction
  end
end

module Codes
  class DecideMapping < ::Codes::BaseAction
    def self.run: (*untyped) -> Result
    ...
  end
end
```

Write each action's RBS to its own file: the ancestor declarations repeat,
byte-identical, in every file that shares a base, and RBS merges them. They also
merge with a base's own signature when you generate or write that too, as long
as it names the same superclass. A namespace that is a class opens as `class`
(without a superclass), not `module`. An anonymous ancestor is skipped: the
next named one becomes the superclass.

A subclass of a typed action subclasses its parent's result classes
(`class Success < ::Billing::BaseAction::Success`), so a typed ancestor's
declaration also carries its `Success`, `Skipped` and `Failure`, empty.
