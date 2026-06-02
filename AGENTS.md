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
- `skills/actionable/SKILL.md` — the bundled Claude Code skill.

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
2. **Output is declared, not magic.** Only fields in `output do … end` appear on the
   result. Setting an undeclared `@foo` does nothing for the caller — declare it.
3. **Genuine exceptions propagate.** A `raise` inside a step is *not* turned into a
   failure. Catch it yourself, or `fail`/`fail!` deliberately. Assert on it in specs
   with `perform_actionable(...).and_raise(SomeError)`.
4. **Transactions need the Rails adapter.** `transactional model: :invoice` only
   works after `require 'actionable/rails'` (auto-loaded when ActiveRecord is present).
   The core never wraps a transaction on its own.
5. **Nested actions thread values explicitly.** `step Child, input: %i[invoice]`
   passes `invoice` in; `expose: %i[receipt]` limits what comes back. Without
   `expose:`, all of the child's outputs are absorbed.

## Fast paths

- See an action's contract without reading source: `pp CreateInvoice.input_schema.metadata.to_h`
  and `pp CreateInvoice.output_schema.metadata.to_h`.
- Type your actions for Steep/Solargraph: `Actionable::RBS.generate(CreateInvoice)`.
- Test a caller without running the action: `stub_actionable_success CreateInvoice, invoice: an_invoice`
  (requires `actionable/rspec`).
- Profile a run: declare `measure :all`, then read `result.history.to_json`.
