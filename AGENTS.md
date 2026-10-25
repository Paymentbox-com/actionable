# Working with the actionable gem

This repo provides **Actionable** — a Ruby gem for service objects: subclass
`Actionable::Action`, declare ordered **steps**, implement each as a method, and run
it to get a single typed **result**. This file routes AI coding agents to the right
docs and the things most often gotten wrong. (For *contributing to the gem itself*,
see `CLAUDE.md`.)

## Read these

- **[`docs/getting_started.md`](docs/getting_started.md)** — how to use it in a repo
  (Ruby + Rails): a task→API map, an error→fix table, and a worked example.
- **[`USAGE.md`](USAGE.md)** — dense reference: every step type, option, and macro.
- **[`README.md`](README.md)** — feature overview.
- `skills/actionable/SKILL.md` — the bundled Claude Code skill. Install it with
  `/plugin marketplace add Paymentbox-com/actionable` then
  `/plugin install actionable@actionable` (the repo is a single-plugin marketplace).

## The shape

```ruby
class CreateInvoice < Actionable::Action
  input  { required :amount, :big_decimal; optional :name, :string }
  output { required :invoice, Invoice }

  step :build
  step :persist

  def build   = @invoice = Invoice.new(amount: input.amount, name: input.name)
  def persist = @invoice.save!
end

result = CreateInvoice.run(amount: 19.99, name: 'Acme')
result.success?       # => true
result.code           # => :success
result.output.invoice # => #<Invoice ...>   (typed)
result.invoice        # => same, via convenience delegation
```

## The gotchas

1. **`fail`/`succeed` vs `fail!`/`succeed!`.** The plain versions *record* an outcome
   and keep running; the bang versions *also stop* the pipeline (`halt!` stops without
   recording). Last write wins; with no call, the action auto-succeeds.
   **`fail` is not `raise` here:** inside an action it is the gem's verb, so
   `fail 'boom'` records a `Failure` with code `:boom` and keeps running (a
   sentence code like `'card expired'` raises `ArgumentError`). Use `raise` for
   a bug, `fail!(:code, 'msg')` to stop with a failure.
   **A plain verb must be the last expression of its step/hook method.**
   `fail :x if bad?` followed by more code raises `DefinitionError` on the
   action's first run: write `fail!` to stop there, or move the verb last
   (`return fail(:x) if bad?` also works). Lint it with the opt-in
   `Actionable/VerbNotLast` cop (`require_path: actionable/rubocop`). See
   [USAGE, Control flow](USAGE.md#where-a-plain-verb-may-go).
2. **Output is declared, not magic.** Only fields in `output do … end` appear on the
   result. Setting an undeclared `@foo` does nothing for the caller — declare it.
3. **Genuine exceptions propagate.** A `raise` inside a step is *not* turned into a
   failure. Catch it yourself, or `fail`/`fail!` deliberately. Assert on it in specs
   with `perform_actionable(...).and_raise(SomeError)`.
4. **Transactions need the Rails adapter.** `transactional model: :invoice` only
   works after `require 'actionable/rails'` (auto-loaded when ActiveRecord is present).
   The core never wraps a transaction on its own. The same goes for
   `after_commit :method` (ActiveRecord >= 7.2): it runs a successful run's side
   effect only after the outermost transaction commits — use it, not `on_success`,
   for emails/webhooks/enqueues from a transactional action.
5. **Nested actions thread values explicitly.** `step Child, input: %i[invoice]`
   passes `invoice` in; `expose: %i[receipt]` limits what comes back. Without
   `expose:`, all of the child's outputs are absorbed.
6. **A skip is `ok?`, not a failure — and now carries output.** `skip(code, msg,
   **output)` mirrors `succeed` (captured best-effort, unvalidated), so an
   idempotent hit can return the existing record's id. Don't model "already done"
   as a `fail`.
7. **Declared failures are strict.** Once an action says `fails :refused, kind:
   :rejected`, every code it fails with must be declared, or `fail` raises
   `DefinitionError`. `:invalid_input` / `:invalid_output` are exempt. The
   metadata after the message is the app's, read back as `result.metadata`;
   `fail`'s keywords are only ever errors.
8. **Declared skips are strict too, the default included.** Once an action says
   `skips :not_ready`, every `skip` / `skip!` must use a declared code, or it
   raises `DefinitionError`. Nothing is exempt, so a bare `skip!` (code
   `:skipped`) on a declaring action needs `skips :skipped`. A child's skip
   continues the parent, so a parent never declares its children's skip codes.
9. **Redeclaring overrides, last wins.** A second `step :x` (or `case_step`,
   nested `step Child`, or hook) with the same name, in the class or a
   subclass, replaces the earlier options and keeps the earlier position. You
   can't remove an inherited step; guard it with `if:` / `unless:`.
10. **`always` hooks run even after a hook halts.** A `fail!` in `on_success`
    stops the rest of the outcome hooks and becomes the result, but the
    `always` hooks still run and see it. Put cleanup and audit in `always`;
    check `result` there if the outcome matters.

## Fast paths

- Declare what an action can fail with: `fails :not_found, kind: :not_found`;
  read it back with `Action.declared_failures` or off the result as `result.metadata`.
- Declare what an action can skip with: `skips :not_ready, retry: true`; read it
  back with `Action.declared_skips` or off the skipped result as `result.metadata`.
- See an action's contract without reading source: `pp CreateInvoice.describe`
  (or `CreateInvoice.describe_text` for a readable summary).
- Run over a collection: `Action.run_each(items) { |i| {…} }` → a `BatchResult`
  with `all_ok?` / `any_failure?` / `partial?` and `to_api_h`.
- Pick the input schema at runtime: `input_for(:event_type) { on 'sale', SaleShape; default … }`.
- Validate a side struct and fail with its errors: `fail_with(EventShape.new(payload), code: :invalid_event)`.
- Render a result for an HTTP response: `result.to_h` / `result.to_api_h(index:)`.
- Run an action from a background job: `include Actionable::Job::Mixin` and call
  `run_actionable(...)` in `perform` (requires `actionable/job`). Add
  `honor_retry_metadata` to the action to make declared `retry: true` /
  `retry: false` metadata decide whether the job retries (off by default).
- Type your actions for Steep/Solargraph: `Actionable::RBS.generate(CreateInvoice)`.
- Test a caller without running the action: `stub_actionable_success CreateInvoice, invoice: an_invoice`
  (requires `actionable/rspec`).
- Find outcomes no spec reaches: `require 'actionable/rspec/coverage'` in a spec
  support file. The suite ends with a table of each action's never-reached
  outcomes; a stubbed result doesn't count. `Coverage.baseline = path` makes CI
  fail on a new gap or a stale entry (see USAGE, "Outcome coverage").
- Profile a run: declare `measure :all` (or `:sampled, rate: 0.1` in prod), then
  read `result.history.to_json`.

## Upgrading

Bumping actionable in a host app? Work from [`UPGRADING.md`](UPGRADING.md), not
from memory: it has a Symptom / Find / Fix / Why entry for every change a caller
can see since 1.5.x. Procedure:

1. **From / to.** Read the current version from `Gemfile.lock` (`actionable
   (x.y.z)`) and pick the target tag. Read UPGRADING.md's TL;DR and only the
   `## A → B` sections between the two.
2. **field_struct first.** If the target needs a newer one (>= 0.11 for 1.5.2,
   >= 0.12 from 1.6.0), bump it, follow its own UPGRADING.md, and get the suite
   green before touching actionable.
3. **Bump actionable.** Check `rg --pcre2-version` works in your shell. Run the
   **Find** of each entry UPGRADING.md lists under "Which Finds to run" (they
   change behaviour without raising), even if nothing failed. Run the others for
   code the suite doesn't reach. Keep the hits per entry.
4. **Enable the cop** (`plugins: [{actionable-rb: {require_path: actionable/rubocop}}]`
   in `.rubocop.yml`; list in `ActionBaseClasses` the two defaults and every app
   base class defined in its own file, by full name, intermediate ones too) and run
   `bundle exec rubocop --only Actionable/VerbNotLast`.
5. **Apply each entry's Fix.** `Actionable.verb_position_check = false` is only
   for a temporary green baseline: set it in `spec_helper`, not an initializer
   (an initializer switches it off in production too), and remove it before you
   finish. The identifier
   code check has no switch.
6. **Regenerate RBS** the app owns with `Actionable::RBS.generate`, then run
   `rbs validate` / Steep if the app uses them.
7. **Run the full suite with the check on.**
8. **Report** the entries applied, hits left unchanged and why, the entries
   whose Find says no reliable pattern exists (say what you reviewed by hand),
   and the residual risk: behaviour changes the suite may not exercise
   (savepoints, bang verbs in hooks, `always` after a halt, redeclared steps).
