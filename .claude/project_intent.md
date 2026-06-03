# Actionable — Project Intent

> What Actionable is, what it isn't, and the terminology used across the codebase.
> For the full design, decisions, and slice plan, see `docs/origin/plan.md`.

---

## What Actionable is

A small Ruby library for **service objects**: classes that encapsulate one unit of
business logic as an ordered sequence of **steps**. You subclass
`Actionable::Action`, declare steps with a DSL, implement each as a method, and run
it. A run returns a single **result** value object — `Success`, `Failure`, or
`Skipped` — with a `code`, `message`, structured `errors`, a typed `output`, and an
execution `history`.

It exists to pull business logic out of Rails controllers/models, Sidekiq workers,
and rake tasks into a shared, composable, predictably-shaped layer.

## What Actionable isn't

- **Not a workflow/BPM engine.** Steps are a linear pipeline with simple branching,
  not a graph with arbitrary transitions.
- **Not a state machine.** No persisted states or transition tables.
- **Not a background-job framework.** A run is synchronous; async is a Phase 2 idea.
- **Not Rails-coupled.** The core is pure Ruby (depends only on `field_struct`).
  Transactions and `ProxyValidator` live in the optional `actionable/rails` adapter.
- **Not a validation library.** Validation of inputs/outputs is delegated to
  FieldStruct; Actionable orchestrates, it doesn't re-implement.

---

## Phase 1 scope (v1.0.0)

See `docs/origin/plan.md` for the authoritative in/out lists. At a glance:

**In:** the step DSL (`step` / `case_step` / `on_success` / `on_failure` / `on_skip`
/ `always`), `Action` + `Runner`, `throw`/`catch` control flow (`fail` / `succeed` /
`skip` / `fail!` / `succeed!` / `skip!` / `halt!`), FieldStruct-backed
`Result`/`Success`/`Failure`/`Skipped` (the `:skip` outcome, D17), typed
`output` schema, optional typed `input` schema, nested-action composition with
`:input`/`:expose`, `History` + `measure`, `Registry`, optional Rails adapter
(transactions + `ProxyValidator`), optional RSpec integration, the
Sord/RBS/YARD type toolchain including `Actionable::RBS.generate` for user
actions, and the DX guardrails (`DefinitionError` for misconfigured actions) +
`Action.describe` introspection (D18).

**Out (deferred):** async/deferred results, step retries/timeouts, result
combinators, non-Rails transaction adapters, persisted history, auto-generated docs,
generators, I18n.

---

## Domain models and terminology

| Term | Meaning |
|---|---|
| **Action** | A subclass of `Actionable::Action`; one unit of business logic as ordered steps. |
| **Step** | One unit in an action's pipeline: Method, Action (nested), or Case. |
| **Method step** | Calls an instance method on the action. |
| **Action step** | Runs another action, threading values in (`:input`) and out (`:expose`). |
| **Case step** | Branches to a target based on a value (`on` / `default`). |
| **Lifecycle hook** | `on_success` / `on_failure` / `on_skip` / `always` — runs at the end based on outcome. |
| **Runner** | Executes steps inside `catch(:actionable_halt)`, runs hooks, optionally wraps a transaction, returns the result. |
| **Result** | The FieldStruct-backed value object from a run: `Success`, `Failure`, or `Skipped`. Predicates `success?` / `failure?` / `skipped?` / `ok?`. |
| **Skip** | A third outcome (D17): nothing to do — not a success, not a failure. `Skipped` result via `skip` / `skip!`. |
| **Output** | The declared, typed result payload (a FieldStruct), populated from matching ivars at run end. |
| **Input** | The optional declared, typed argument schema (a FieldStruct) enabling typed `.run`. |
| **Halt** | Early pipeline stop via `throw :actionable_halt` (from `fail!` / `succeed!` / `skip!` / `halt!`). Not an exception. |
| **History** | Per-run step timing/code record; enabled by `measure :all`. |
| **Registry** | `Actionable.registry` — map of all defined action classes. |
| **Rails adapter** | Optional `actionable/rails`: transactions + `ProxyValidator`. Core never depends on it. |

---

## Design invariants

These hold across the codebase. Don't break them without surfacing the change.

1. **Tests ship with code.** Every behavior change is a `feat:`/`fix:` commit that
   includes its specs. No "tests in a follow-up."
2. **Control flow is `throw`/`catch`, never exceptions.** Halting uses
   `throw :actionable_halt`. The runner never `rescue`s `Exception` or `StandardError`
   for control flow — genuine errors propagate to the caller.
3. **Output is an explicit, typed contract.** Only fields declared in `output do … end`
   are surfaced on the result. No "capture every instance variable" magic. Only a
   strict `Success` is output-validated; `Failure`/`Skipped` capture best-effort.
4. **The core is Rails-free.** Nothing under the core load path requires
   ActiveModel/ActiveSupport/ActiveRecord. Rails concerns live behind
   `require 'actionable/rails'`. RSpec concerns behind `require 'actionable/rspec'`.
5. **Class config is inherited and overridable.** Steps, `measure`, `transactional`,
   and schemas walk the ancestry chain; subclasses can add or override.
6. **Explicit `require_relative`, no autoload.** New core files get a matching
   `require_relative` in `lib/actionable.rb`. The optional adapters are not required
   by the core entry point.
7. **Oj for JSON.** Never `JSON.parse` / built-in `to_json`. Always `Oj.load` / `Oj.dump`.
8. **Delegate typing/validation to FieldStruct.** Inputs and outputs are FieldStruct
   schemas; we don't reinvent coercion, presence, or `ruby_type`.

---

## When in doubt

- Re-read `docs/origin/plan.md` (the locked decisions D1–D18 are authoritative).
- Re-read `docs/origin/first_discussion.md` for the original intent.
- If the answer isn't in either, ask Adrian before guessing.
