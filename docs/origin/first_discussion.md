# Actionable — original idea

*The founding design notes for the Actionable rebuild, kept for historical
context. Reconstructed from the original gem's README and source, and from the
redesign conversation. The ideas and intent are preserved; the wording has been
tidied.*

## The core idea

I want a small Ruby library for **service objects** — objects that encapsulate one
piece of business logic as an ordered sequence of **steps**. You write a class,
declare its steps, and implement each step as a method. Running the object walks
the steps in order and returns a single **result** describing what happened:
a `code` (`:success` or an error code), a human-readable `message`, structured
`errors`, and an `output` payload.

The point is to pull business logic out of the places it tends to sprawl — Rails
controllers and models, Sidekiq workers, rake tasks — and into a shared, composable
set of actions with a predictable shape. A controller becomes "gather params →
run an action → branch on `result.code`."

It draws inspiration from Trailblazer's `Operation`, but it is deliberately
smaller and simpler in scope.

## The original shape

The first version of the gem looked like this:

```ruby
class CreateInvoice < Actionable::Action
  set_model :invoice          # wrap the run in an ActiveRecord transaction

  step :build
  step :validate
  step :create

  def initialize(params)
    super()
    @params = params
  end

  def build
    @invoice = Invoice.new
  end

  def validate
    fail :invalid, 'The invoice was invalid', validator.errors unless valid?
  end

  def create
    @invoice.save!
  end
end

result = CreateInvoice.run(params)
result.code       # => :success or :invalid
result.invoice    # => the @invoice we built (auto-captured)
```

Key ideas that were present from day one and are worth keeping:

- **Steps run in declaration order.** If no step declares success or failure, the
  action auto-succeeds at the end.
- **A single result object.** `code` / `message` / `errors`, plus the instance
  variables created during the run, surfaced as methods on the result.
- **Composability.** A step can point to *another action*, running its steps and
  threading values in and out.
- **Conditional steps.** `:if` / `:unless` options, taking a method name or a block.
- **Lifecycle hooks.** `on_success`, `on_failure`, and `always` steps that run at
  the end depending on the outcome.
- **Branching.** A `case_step` that dispatches to different steps based on a value.
- **Short-circuiting.** `fail!` / `succeed!` to stop the pipeline early; `fail` /
  `succeed` to record an outcome without stopping.
- **Transactions.** When a model is set, the whole run is wrapped in a DB
  transaction so it all commits or none of it does.
- **Test support.** RSpec matchers and stubs so callers can assert on and fake out
  action runs cheaply.

## What the rebuild changes (and why)

The original worked, but several things make it hard to type and hard for both
humans and coding agents to reason about. The rebuild keeps the *feel* of the
library while fixing these:

1. **Magic result accessors → a declared, typed output.** The original captured
   *every* instance variable and exposed them via `method_missing` on the result.
   Convenient, but untyped and invisible. The rebuild keeps the ergonomics (you
   still just set ivars) but routes them through a **declared `output` schema**
   backed by [FieldStruct](https://github.com/Paymentbox-com/field_struct), so the
   result payload is typed, validated, and self-documenting.

2. **Exceptions-as-control-flow → `throw`/`catch`.** The original short-circuited
   via exceptions caught by a bare `rescue Exception` in the runner — which also
   swallowed genuine errors and resisted typing. The rebuild halts the pipeline
   with `throw :actionable_halt`; real exceptions propagate untouched.

3. **Hard Rails coupling → optional adapter.** The original always loaded
   ActiveModel/ActiveSupport and hard-wired ActiveRecord transactions. The rebuild
   has a pure-Ruby core; transactions and the `ProxyValidator` move to an opt-in
   `actionable/rails` adapter.

4. **No types → full RBS.** Every public method carries YARD docs; Sord generates
   the library's `.rbs`; and `Actionable::RBS.generate` emits signatures for
   user-defined actions from their declared input/output schemas.

The name stays **Actionable**; users still subclass `Actionable::Action`.

For the full, current design — locked decisions, scope, and the slice plan — see
[`plan.md`](plan.md).
