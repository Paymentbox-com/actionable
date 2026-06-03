---
name: actionable
description: Author, edit, and debug Actionable service objects — declaring steps, choosing control-flow verbs (succeed/fail/fail_with/skip and their bang forms), wiring typed input/output schemas (including discriminated input via input_for), running over a collection with run_each, composing nested actions and case branches, lifecycle hooks, history/sampled measurement, serializing results (to_h/to_api_h), and the optional Rails/RSpec/job adapters.
when_to_use: Use when defining or modifying a class that inherits from Actionable::Action (any step / case_step / on_success / output / input / input_for declaration), when choosing how a step should record its outcome, when running an action over a collection, when debugging why a run failed/skipped or an output wasn't captured, when mapping a result to an HTTP/job response, or when testing an action with the perform_actionable matcher.
---

# Working with Actionable

Actionable builds **service objects**: declare an ordered list of **steps** on an
`Actionable::Action` subclass, implement each as a method, and run it. A run
returns one value object — `Success`, `Failure`, or `Skipped` — with `code`,
`message`, `errors`, a typed `output`, and a `history`.

## Read the bundled reference first

The gem ships a dense, example-first reference. Read it before answering a
non-trivial question — it matches the installed version:

- Run `bundle show actionable` and open `USAGE.md` at that path, or
- https://github.com/Paymentbox-com/actionable/blob/main/USAGE.md

This skill is the **workflow and the mistakes to avoid**; `USAGE.md` is the catalog.

## Defining an action

```ruby
class CreateInvoice < Actionable::Action
  input  { required :amount, :integer }      # typed .run kwargs (optional block)
  output { required :invoice, :string }       # declared, typed result payload

  step :validate
  step :build

  def validate
    fail!(:invalid_amount) unless input.amount.positive?
  end

  def build
    @invoice = "INV-#{input.amount}"          # ivar matching an output field is captured
  end
end

result = CreateInvoice.run(amount: 10)
result.success?         # => true
result.invoice          # => "INV-10"  (delegates to result.output.invoice)
```

When asked to build one:

1. Declare `input`/`output` schemas if the action has a typed contract; reach for
   `input.field` rather than a custom `initialize`.
2. Add `step :name` in order; implement each as a method.
3. Inside steps, record the outcome with a control-flow verb (below). Setting an
   ivar named like an `output` field is enough to surface it — no explicit expose.
4. Run `bin/rspec` / `bundle exec rake` and test with `perform_actionable`.

## Choosing a control-flow verb

| Want to… | Use |
|----------|-----|
| Succeed and keep running | `succeed(message = nil, **output)` |
| Record an error, keep running | `fail(code, message = nil, **errors)` |
| Fail with a FieldStruct's errors | `fail_with(struct, code: :invalid, message: nil)` |
| Mark "nothing to do" (with optional output) | `skip(code = :skipped, message = nil, **output)` |
| Same, but stop the pipeline now | `succeed!` / `fail!` / `fail_with!` / `skip!` |
| Stop, keep whatever was recorded | `halt!` |

- **Skip is not failure.** Use `skip!` when a precondition isn't ready / there's
  nothing to do — not `fail!`. A skip is `ok?` (won't read as an error) but
  distinct from success (`skipped?`). Use `ok?` for "didn't fail" checks. `skip`
  takes `**output` (like `succeed`), so an idempotent hit can return the existing
  record's id.
- `fail_with(struct, code:)` records a failure carrying `struct`'s validation
  errors — for validating a side FieldStruct in a step.
- Plain verbs don't halt; last write wins. Bang verbs halt.
- To signal a real bug, `raise` — exceptions propagate, they aren't caught.

## Composition

- **Nested action:** `step Notify, input: %i[invoice], expose: %i[receipt]`. A
  child failure fails the parent; a child skip continues it.
- **Branch:** `case_step :status do on 'active', :handle; default :other end`
  (matches by `==`, `Regexp`, or Array membership).
- **Hooks:** `on_success` / `on_failure` / `on_skip` / `always` run after the
  main steps by outcome.
- **Discriminated input:** `input_for(:event_type) { on 'sale', SaleShape;
  default UnknownShape }` picks the input schema at run time from a discriminator
  (typed polymorphic input). An unmatched value with no `default` →
  `Failure(:invalid_input)`.
- **Batch:** `Action.run_each(items) { |i| {…} }` runs once per item and returns a
  `BatchResult` (`all_ok?` / `any_failure?` / `partial?`, `to_api_h`).

## Mistakes to avoid

- **Reserved output field names raise `Actionable::DefinitionError`.** An
  `output` field named `code`/`message`/`output`/`history`/`errors` (result
  attributes) or `result`/`input` (reserved ivars) is rejected when declared —
  pick another name. (Input fields are fine; they're read via `input.x`.)
- **A missing step method raises `DefinitionError` at run start**, naming the
  action and method — implement every declared step / hook / case method.
- **A successful run must satisfy its declared output**, or it becomes
  `Failure(:invalid_output)`. Failures/skips capture output best-effort and are
  not validated — so don't rely on output fields being present after a skip.
- **Don't `require 'actionable/rails'` in the core path.** Transactions and
  `ProxyValidator` are opt-in; the core never loads `active_*`.

To inspect an action's shape (for tooling or to reason about it), call
`SomeAction.describe` — a Hash of its name, input/output, steps, hooks, measure,
and transaction config (or `describe_text` for a readable summary).

## Beyond a single run

- **Serialize a result:** `result.to_h` (plain Hash) or
  `result.to_api_h(index:)` (compact HTTP/batch element: `index`, `status`,
  `id`, `errors`) — don't hand-map in controllers.
- **Background jobs (`require 'actionable/job'`):** `include
  Actionable::Job::Mixin` into a Sidekiq/ActiveJob job and call
  `run_actionable(SomeAction, **kwargs)` in `perform`. A success/skip acks; a
  transient failure raises `RetryableFailure` (queue retries); a permanent-code
  failure is discarded; a genuine exception propagates.
- **Prod observability:** `measure :sampled, rate: 0.1` records history on a
  fraction of runs (between `:all` and `:none`).

## Testing (`require 'actionable/rspec'`)

```ruby
expect(CreateInvoice).to perform_actionable(amount: 10).and_succeed
expect(CreateInvoice).to perform_actionable(amount: 0).and_fail(:invalid_amount)
expect(Sync).to          perform_actionable.and_skip(:not_ready)

allow_actionable_failure(CreateInvoice, code: :invalid_amount) # stub without running
```
