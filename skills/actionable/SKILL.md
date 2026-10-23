---
name: actionable
description: Author, edit, and debug Actionable service objects — declaring steps, choosing control-flow verbs (succeed/fail/fail_with/skip and their bang forms), wiring typed input/output schemas (including discriminated input via input_for), running over a collection with run_each, composing nested actions and case branches, lifecycle hooks, history/sampled measurement, serializing results (to_h/to_api_h), and the optional Rails/RSpec/job adapters.
when_to_use: Use when defining or modifying a class that inherits from Actionable::Action (any step / case_step / on_success / output / input / input_for declaration), when choosing how a step should record its outcome, when running an action over a collection, when debugging why a run failed/skipped or an output wasn't captured, when mapping a result to an HTTP/job response, when testing an action with the perform_actionable matcher, or when upgrading the actionable gem to a newer version.
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
- **Declare failure codes** with `fails :refused, 'message', kind: :rejected`.
  The keywords are neutral metadata the gem passes through to
  `result.metadata`. Once any code is declared, failing with an undeclared one
  raises `DefinitionError` (`:invalid_input` / `:invalid_output` are exempt).
  `fail`'s keywords after the message are only ever errors, so an error on
  `kind` stays an error.
- **Declare skip codes** with `skips :not_ready, 'message', retry: true`, read
  back as `result.metadata` on the skip. Once any skip code is declared,
  skipping with an undeclared one raises `DefinitionError`, the default
  `:skipped` included (nothing is exempt).
- Plain verbs don't halt; last write wins. Bang verbs halt.
- **A plain `fail` / `fail_with` / `skip` / `succeed` must be the last
  expression of its step or hook method** (or `return fail(...)`). `fail :x if bad?` followed by more
  code raises `DefinitionError` on the action's first run — that's a `fail!`
  missing its bang. The opt-in RuboCop cop `Actionable/VerbNotLast`
  (`plugins: [{actionable: {require_path: actionable/rubocop}}]`) flags it.
  `Actionable.verb_position_check = false` turns the first-run check off (an
  upgrade escape hatch; the cop is then the only guard). Don't reach for it to
  silence an offense: fix the verb.
- `fail` / `skip` codes must be identifiers (`:card_expired`, `:ok?`); a
  sentence raises `ArgumentError`.
- To signal a real bug, `raise` — exceptions propagate, they aren't caught.
  **Never `fail 'message'` for that:** inside an action `fail` is the gem's
  verb, not `Kernel#fail`: a sentence code raises `ArgumentError`, and a
  one-word string (`fail 'boom'`) records a `Failure` with code `:boom` and
  the run keeps going (a later `succeed` erases it).

```ruby
def charge
  fail 'gateway down'          # WRONG: not an exception; raises ArgumentError (not an identifier code)
  raise GatewayError, 'down'   # a bug / unexpected condition: propagates
  fail!(:gateway_down, 'down') # an expected failure outcome: records and halts
end
```

## Composition

- **Nested action:** `step Notify, input: %i[invoice], expose: %i[receipt]`. A
  child failure fails the parent with its code, message, errors and metadata
  intact; a child skip continues it. A parent that declares failures must
  declare its children's failure codes too, but never their skip codes.
- **Branch:** `case_step :status do on 'active', :handle; default :other end`
  (matches by `==`, `Regexp`, or Array membership).
- **Hooks:** `on_success` / `on_failure` / `on_skip` / `always` run after the
  main steps by outcome, inside any `transactional` transaction. With the Rails
  adapter, `after_commit :method` (ActiveRecord >= 7.2) runs only after the
  outermost transaction commits a successful run — the place for emails,
  webhooks and enqueues. It can't change the result and isn't in the history.
  A bang verb in an outcome hook stops the rest of that category, but `always`
  hooks still run and see the adopted result — keep cleanup/audit in `always`.
- **Override by redeclaring:** a second `step :x` / `case_step :x` / `step
  Child` / hook with the same name (same class or a subclass) replaces the
  earlier one's options and keeps its position — last declaration wins. There
  is no removal; guard an inherited step off with `if:` / `unless:`.
- **Discriminated input:** `input_for(:event_type) { on 'sale', SaleShape;
  default UnknownShape }` picks the input schema at run time from a discriminator
  (typed polymorphic input). An unmatched value with no `default` →
  `Failure(:invalid_input)`.
- **Batch:** `Action.run_each(items) { |i| {…} }` runs once per item and returns a
  `BatchResult` (`all_ok?` / `any_failure?` / `partial?`, `to_api_h`).

## Mistakes to avoid

- **Reserved output field names raise `Actionable::DefinitionError`.** An
  `output` field named `code`/`message`/`output`/`history`/`errors`/`metadata`
  (result attributes) or `result`/`input` (reserved ivars) is rejected when declared —
  pick another name. (Input fields are fine; they're read via `input.x`.)
- **A missing step method raises `DefinitionError` at run start**, naming the
  action and method — implement every declared step / hook / case method.
- **A successful run must satisfy its declared output**, or it becomes
  `Failure(:invalid_output)`. Failures/skips capture output best-effort and are
  not validated — so don't rely on output fields being present after a skip.
- **`fail` shadows `Kernel#fail`** in every instance method of an action (see
  the verb section). Use `raise` for exceptions, `fail!(:code)` to stop with a
  failure.
- **Don't `require 'actionable/rails'` in the core path.** Transactions and
  `ProxyValidator` are opt-in; the core never loads `active_*`.

To inspect an action's shape (for tooling or to reason about it), call
`SomeAction.describe` — a Hash of its name, input/output, steps, declared
failures, hooks, measure, and transaction config (or `describe_text` for a readable summary).

## Beyond a single run

- **Serialize a result:** `result.to_h` (plain Hash) or
  `result.to_api_h(index:)` (compact HTTP/batch element: `index`, `status`,
  `id`, `errors`) — don't hand-map in controllers.
- **Background jobs (`require 'actionable/job'`):** `include
  Actionable::Job::Mixin` into a Sidekiq/ActiveJob job and call
  `run_actionable(SomeAction, **kwargs)` in `perform`. A success/skip acks; a
  transient failure raises `RetryableFailure` (queue retries); a permanent-code
  failure is discarded; a genuine exception propagates. Declared `retry:`
  metadata is ignored unless the action calls `honor_retry_metadata`; then
  `retry: true` retries (failures and skips) and `retry: false` doesn't.
- **Prod observability:** `measure :sampled, rate: 0.1` records history on a
  fraction of runs (between `:all` and `:none`).

## Upgrading the gem

When asked to bump actionable, follow the gem's `UPGRADING.md` (next to
`USAGE.md` in `bundle show actionable`, or
https://github.com/Paymentbox-com/actionable/blob/main/UPGRADING.md) instead
of recalling changes. In short:

1. Read the from/to versions (`Gemfile.lock`) and only the guide's sections
   between them.
2. Bump field_struct first when the target needs it (>= 0.12 from 1.6.0) and
   follow its UPGRADING.md.
3. Bump actionable; run every entry's **Find** in range.
4. Enable the `Actionable/VerbNotLast` cop and run
   `bundle exec rubocop --only Actionable/VerbNotLast`.
5. Apply each **Fix**; never leave `Actionable.verb_position_check = false`
   behind.
6. Regenerate owned RBS with `Actionable::RBS.generate`.
7. Run the suite with the check on.
8. Report what was fixed, what was reviewed by hand (entries with no
   reliable Find), and residual behaviour risks.

## Testing (`require 'actionable/rspec'`)

```ruby
expect(CreateInvoice).to perform_actionable(amount: 10).and_succeed
expect(CreateInvoice).to perform_actionable(amount: 0).and_fail(:invalid_amount)
expect(Sync).to          perform_actionable.and_skip(:not_ready)

allow_actionable_failure(CreateInvoice, code: :invalid_amount) # stub without running
```

On an action that declares failures, a stubbed failure carries the declared
metadata for its code, and a stub or `and_fail` with an undeclared code raises
`ArgumentError`.

**Outcome coverage** (`require 'actionable/rspec/coverage'`) lists, at the end
of the suite, each action's outcomes no spec reached: success, every declared
failure and every declared skip. Only a real run counts, so a stub doesn't
cover anything. When a project sets `Actionable::Coverage.baseline`, a new
declaration (`fails :x`) needs a spec that reaches it, or an entry in the
baseline file; the failure message names the exact line to add or remove.
