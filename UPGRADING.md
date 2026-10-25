# Upgrading Actionable

<!-- upgrading-range: 1.5.0..1.9.0 -->

This guide takes an app from any **1.5.x** release to **1.8.2**, one version at
a time or [straight through](#straight-from-15-to-18). It lists every change a
caller can see, not just the breaking ones. Each entry has the same four parts:

- **Symptom**: the exception and message shape, or the spec that fails.
- **Find**: a copy-pasteable search, or the tool that finds it when no
  search is reliable.
- **Fix**: before and after.
- **Why**: one line.

The `rg` patterns search `app lib` (code), `spec` and `sig`; point them at your
own directories and drop any that don't exist. Patterns with `-P` need ripgrep
built with PCRE2. Check first, in the shell that will run them, with
`rg --pcre2-version`; an agent's `bash -c` may not see a shell function or alias
that wraps `rg`. A pattern finds *candidates*; read each hit.

**Which Finds to run.** Most changes raise or fail a spec, so the suite finds
them; their Finds cover code the suite doesn't reach. Seven change behaviour
without raising, so run their Finds even on a green suite: the
[nested savepoint](#a-nested-transactional-action-takes-its-own-savepoint),
[bang verbs in hooks](#a-bang-verb-inside-a-lifecycle-hook-sets-the-result),
[nested output](#a-nested-action-no-longer-overwrites-parent-fields-it-didnt-set),
[RSpec stubs](#rspec-stubs-absorb-only-the-fields-you-give-them),
[redeclared steps](#redeclaring-a-step-or-hook-overrides-it-last-wins),
[`always` after a halt](#always-hooks-run-even-after-an-outcome-hook-halts) and
[`case_step` branch guards](#case_step-branch-guards-are-honoured). Every pattern has been checked against the "before" snippet it
targets. [CHANGELOG.md](CHANGELOG.md) has the
full list of changes, including internal ones.

Agents: follow the numbered procedure in [AGENTS.md](AGENTS.md#upgrading)
(or the bundled skill), which runs this guide step by step.

## TL;DR

**Who must act:** every app moving to 1.8.0 (two new checks raise on code that
used to run), anyone who keeps hand-written RBS next to `Actionable::RBS`
output, and Rails apps that nest `transactional` actions. **Already on 1.8.1?**
Skip to [1.8.1 → 1.8.2](#181--182): one silent change (`case_step` branch
guards) and two narrow ones. **Already on 1.8.2?** Skip to
[1.8.2 → 1.9.0](#182--190): the gem is renamed `actionable-rb`.

1. **Bump field_struct first.** actionable >= 1.6 requires `field_struct >=
   0.12` (1.5.2 needs `>= 0.11`). Upgrade it and follow field_struct's
   [UPGRADING.md](https://github.com/Paymentbox-com/field_struct/blob/main/UPGRADING.md)
   until your suite is green.
2. **Bump actionable** to `v1.8.2` in the Gemfile.
3. **Fix verb-position offenses.** If you need a green baseline first, run the
   suite once with `Actionable.verb_position_check = false`, then turn it back
   on. Enable the [`Actionable/VerbNotLast` cop](#a-plain-verb-must-end-its-step-or-hook-method)
   in `.rubocop.yml` to list every offense up front. Fix
   [non-identifier codes](#fail--skip-codes-must-be-identifiers) at the same
   time: that check has no switch.
4. **Regenerate the RBS you own** with `Actionable::RBS.generate`, then delete
   hand-written declarations it now covers (see the [1.6.0 entries](#152--160)).
5. **Opting in to job retries** (`honor_retry_metadata`)? Under ActiveJob, also
   declare `retry_on Actionable::Job::RetryableFailure`.
6. **Using `after_commit`?** It needs ActiveRecord >= 7.2. The rest of the
   Rails adapter is tested on 7.1.

**Expected effort:** the fixes take minutes to an hour for most apps (what the
cop and the code check report). Longer only if you keep hand-written RBS for
your actions or nest `transactional` actions inside your own transactions. On
top of that come the full suite runs: a baseline, one after the field_struct
bump, one after this one, and a final run with the check on. Budget 4× your
suite's wall time.

## Straight from 1.5 to 1.8

You can jump in one bump. Work in this order, so each step starts from a green
run:

1. Bump field_struct to >= 0.12 (step 1 above). Bundler refuses the actionable
   bump until you do: `Bundler could not find compatible versions for gem
   "field_struct"`.
2. Bump actionable to `v1.8.2`. Set `Actionable.verb_position_check = false`
   in `spec_helper` (or a `spec/support` file) for now, not in an initializer:
   an initializer also switches the check off in production, and that is easy
   to forget to undo. Use an initializer only if you must deploy before every
   offense is fixed (see [the verb entry](#a-plain-verb-must-end-its-step-or-hook-method)).
3. Run the suite. Work through the [1.5.2](#15x--152) and
   [1.7.0](#160--170) entries: they change runtime behaviour (savepoints,
   hook halts, nested output, redeclared steps, `always` hooks).
4. Enable the cop, fix every offense, and remove the
   `verb_position_check = false` line. Fix the
   [identifier codes](#fail--skip-codes-must-be-identifiers).
5. Regenerate your RBS and work through the [1.6.0](#152--160) entries and
   [adapter signatures](#adapter-signatures-now-ship-in-sig).
6. Work through the [1.8.2](#181--182) entries: a `case_step` branch guard
   now takes effect, and that doesn't raise, so run its Find.
7. Run the suite with the check on. Anything still failing:
   [bisect by version](#if-something-else-breaks).

## Symptom index

| You see | Version | Entry |
|---|---|---|
| Bundler: `could not find compatible versions for gem "field_struct"` | 1.5.2, 1.6.0 | [>= 0.11](#requires-field_struct--011), [>= 0.12](#requires-field_struct--012) |
| A failed nested `transactional` action's rows are gone | 1.5.2 | [Savepoint](#a-nested-transactional-action-takes-its-own-savepoint) |
| `fail!` in `on_success` now fails the run / rolls back / retries the job | 1.5.2 | [Bang verb in a hook](#a-bang-verb-inside-a-lifecycle-hook-sets-the-result) |
| A parent field keeps its value after `step Child` | 1.5.2 | [Nested absorb](#a-nested-action-no-longer-overwrites-parent-fields-it-didnt-set), [stubs](#rspec-stubs-absorb-only-the-fields-you-give-them) |
| `DefinitionError: … declares step(s) calling :print but does not implement them` | 1.5.2 | [Core method names](#a-step-or-hook-named-after-a-core-ruby-method-is-refused) |
| `DefinitionError: … set @result to a …` | 1.5.2 | [`@result`](#assigning-result-in-a-step-raises-a-clear-error) |
| `errors[:output]` gone from a failure or skip | 1.5.2 | [Spurious output error](#failures-and-skips-no-longer-carry-a-spurious-errorsoutput) |
| `RBS::InstanceVariableDuplicationError` | 1.6.0 | [Output ivars](#generated-rbs-owns-the-output-instance-variables) |
| `RBS::SuperclassMismatchError` | 1.6.0 | [Superclass chain](#generated-rbs-declares-the-real-superclass-chain) |
| `ArgumentError: X::InputSchema is already defined …` | 1.6.0 | [`InputSchema`](#inputschema-is-a-reserved-name-on-actions-with-a-fixed-input) |
| New Steep errors at call sites | 1.6.0 | [Stricter types](#generated-types-are-stricter) |
| A redeclared step runs different options | 1.7.0 | [Redeclaration](#redeclaring-a-step-or-hook-overrides-it-last-wins) |
| An `always` hook runs after a hook's `fail!` | 1.7.0 | [`always` after halt](#always-hooks-run-even-after-an-outcome-hook-halts) |
| `RBS::DuplicatedMethodDefinitionError` for `transactional`, `perform_actionable` … | 1.7.0 | [Adapter signatures](#adapter-signatures-now-ship-in-sig) |
| `describe[:hooks]` has an extra `after_commit:` key | 1.7.0 | [`describe`](#describe-lists-after_commit-hooks-under-the-rails-adapter) |
| ``DefinitionError: … calls `fail` with more code after it …`` | 1.8.0 | [Verb position](#a-plain-verb-must-end-its-step-or-hook-method) |
| `ArgumentError: … code "…" is not an identifier …` | 1.8.0 | [Identifier codes](#fail--skip-codes-must-be-identifiers) |
| A guarded `case_step` branch no longer runs | 1.8.2 | [Branch guards](#case_step-branch-guards-are-honoured) |
| `ArgumentError: … both name …Output in the generated RBS` | 1.8.2 | [Output class names](#actionablerbs-refuses-codes-that-share-an-output-class-name) |
| ``DefinitionError: … calls `fail` …`` for an aliased step | 1.8.2 | [Aliased step](#the-verb-check-reads-an-aliased-steps-original-def) |

## 1.5.x → 1.5.2

### Requires field_struct >= 0.11
<!-- upgrading: field-struct-0-11 -->

**Symptom.** `bundle update actionable` fails: `Bundler could not find
compatible versions for gem "field_struct"`.

**Find.**
```sh
rg -n "gem ['\"](field_struct|actionable)['\"]" Gemfile
```

**Fix.** Raise the field_struct pin in the same change:
```ruby
# before
gem 'field_struct', git: 'https://github.com/Paymentbox-com/field_struct', tag: 'v0.10.0'
# after (0.12.0 if you are going on to 1.6+)
gem 'field_struct', git: 'https://github.com/Paymentbox-com/field_struct', tag: 'v0.12.0'
```

**Why.** 1.5.2 is tested against field_struct 0.11's numeric and input fixes.

### A nested `transactional` action takes its own savepoint
<!-- upgrading: transactional-savepoint -->

**Symptom.** Inside an open transaction (your own `Model.transaction do`, or a
transactional parent action), a `transactional` action that ends in a
`Failure` now rolls back its own writes. A spec that expected those rows to
exist after the outer block commits now finds them missing.

**Find.** List the transactional actions, then check which run inside another
transaction:
```sh
rg -n '^\s*transactional\b' app lib
```

**Fix.** Usually nothing: the new behaviour is the correct one. To keep the old
joining behaviour for one action:
```ruby
# before (1.5.1 joined the outer transaction)
transactional model: :invoice
# after, only if you really want a failed run's writes to commit with the outer transaction
transactional model: :invoice, requires_new: false
```

**Why.** A recorded `Failure` committed its rows through the outer transaction,
which ignored the action's rollback.

### A bang verb inside a lifecycle hook sets the result
<!-- upgrading: hook-bang-verb -->

**Symptom.** `fail!` / `skip!` / `succeed!` in `on_success` / `on_failure` /
`on_skip` / `always` used to be dropped. Now the run ends with that hook's
result: a spec expecting `Success` gets the `Failure`, a `transactional`
action rolls back, and a job retries or discards. A nested action used as a
hook (`on_success AuditPayment`) that fails now fails the run.

**Find.** No single pattern. List the hook declarations, then read those
methods for a bang verb:
```sh
rg -n '^\s*(on_success|on_failure|on_skip|always)\s+:' app lib   # hook methods
rg -n '^\s*(on_success|on_failure|on_skip|always)\s+[A-Z]' app lib # nested actions as hooks
```

**Fix.** Keep the bang verb if the hook's failure should fail the run (that is
what the docs always said). If it shouldn't, record nothing: log, or `halt!`
to stop the remaining hooks and keep the result.
```ruby
# before: silently ignored, the run stayed a Success
def notify
  fail!(:notify_failed) unless mailer.ok?
end
# after, when a mailer problem must not fail the payment
def notify
  logger.warn('receipt not sent') unless mailer.ok?
end
```

**Why.** A hook's `fail!` must not commit a transaction or ack a job as a success.

### A nested action no longer overwrites parent fields it didn't set
<!-- upgrading: nested-absorb-set-fields -->

**Symptom.** After `step Child`, a parent field the child left nil (or at its
default) keeps the parent's value instead of being reset. A spec expecting the
nil now sees the old value.

**Find.** No reliable pattern; review nested steps without `expose:` whose child
shares output field names with the parent:
```sh
rg -n '^\s*step\s+[A-Z]' app lib
```

**Fix.** Have the child set the field explicitly; an assigned ivar (even `nil`)
counts as set:

<!-- doctest -->
```ruby
class ClearNote < Actionable::Action
  output { optional :note, :string }
  step :clear
  def clear = @note = nil # assigned, so the parent absorbs the nil
end

class Edit < Actionable::Action
  output { optional :note, :string }
  step :draft
  step ClearNote
  def draft = @note = 'draft'
end

Edit.run.note # => nil
```

**Why.** Copying every declared field wiped parent values the child never touched.

### RSpec stubs absorb only the fields you give them
<!-- upgrading: stub-set-fields -->

**Symptom.** A parent spec that stubs a child with partial output
(`allow_actionable_success(Child, total: 5)`) no longer gets the child's other
fields reset to nil; it keeps the parent's values, as a real run does.

**Find.**
```sh
rg -nP '\b(?:allow|stub)_actionable_(?:success|skip)\b' spec
```

**Fix.** Pass every field the parent should receive, `nil` included:
```ruby
# before: relied on the stub resetting :note
allow_actionable_success(Child, total: 5)
# after
allow_actionable_success(Child, total: 5, note: nil)
```

**Why.** Stubs now behave like the real runs they stand in for.

### A step or hook named after a core Ruby method is refused
<!-- upgrading: core-method-steps -->

**Symptom.** First run raises
`Actionable::DefinitionError: Report declares step(s) calling :print but does not implement them`.

**Find.** The runtime check is authoritative; this lists the common names:
```sh
rg -nP '^\s*(?:step|case_step|on_success|on_failure|on_skip|always)\s+:(?:puts|print|p|pp|exit|exit!|abort|sleep|format|sprintf|printf|warn|raise|system|exec|spawn|fork|open|select|test|loop|rand|srand|gets|require|load|eval|binding|caller|catch|throw|trap|display|hash|freeze|dup|clone|inspect|tap|then|itself|send|method|methods|class|name|object_id)\b' app lib
```

**Fix.** Implement the method on the action, or rename the step:
```ruby
# before: called Kernel#print (or Kernel#exit, which ended the process)
step :print
# after
step :print_report
def print_report = ...
```

**Why.** Steps are called with `__send__`, so `always :exit` could reach `Kernel#exit`.

### Assigning `@result` in a step raises a clear error
<!-- upgrading: result-ivar -->

**Symptom.** `Actionable::DefinitionError: Lookup set @result to a Account; @result is reserved for the run's result, so rename the instance variable`
(before: a `NoMethodError` deep in the runner).

**Find.**
```sh
rg -n '@result\s*(\|\|)?=' app lib
```

**Fix.**
```ruby
# before
def find = @result = Account.find(input.id)
# after
def find = @account = Account.find(input.id)
```

**Why.** `@result` holds the run's result.

Assigning an `Actionable::Result` (a `Failure`, `Skipped` or `Success`) is not
refused, from a step or from a helper a step calls, and `halt!` is the
documented way to stop after it ([USAGE](USAGE.md)'s verb table). So an app base
class that builds a failure carrying ActiveModel errors keeps working:
```ruby
def fail_invalid!(record)
  @result = Actionable::Failure.new(code: :invalid, message: 'Record is invalid', metadata: {}, output: {})
  record.errors.each { |error| @result.errors.add(error.attribute, error.message) }
  halt!
end
```
Only a non-`Result` value raises.

### Failures and skips no longer carry a spurious `errors[:output]`
<!-- upgrading: no-spurious-output-error -->

**Symptom.** A spec asserting `errors[:output] == ["is invalid"]` on a failure
or skip of an untyped action fails: the key is gone.

**Find.**
```sh
rg -nP "errors\[:output\]|output:\s*\[\s*['\"]is invalid" spec
```

**Fix.** Delete the assertion; errors the failure recorded itself are still there.
```ruby
# before
expect(result.errors).to include(output: ['is invalid'])
# after: assert on the errors your fail call recorded
expect(result.errors).to include(card: ['expired'])
```

**Why.** Best-effort output on a failure or skip is unvalidated by design.

### Also fixed in 1.5.2 (no action expected)

- `succeed` / `skip` kwargs survive lifecycle hooks: a run that used to end as
  `Failure(:invalid_output)` because a hook dropped a kwarg now succeeds.
  <!-- upgrading: hook-kwargs -->
- Private step, hook and `case_step` methods work (they raised `NoMethodError`).
- `Action.input` without a block reads the schema instead of replacing it.

## 1.5.2 → 1.6.0

No runtime behaviour changes. Everything here is about **generated RBS** and
the hand-written sig files that sit next to it. Regenerate first
(`Actionable::RBS.generate(YourAction)`, one file per action), then run
`rbs validate` (or Steep) and work through what it reports.

### Requires field_struct >= 0.12
<!-- upgrading: field-struct-0-12 -->

**Symptom.** `Bundler could not find compatible versions for gem "field_struct"`.

**Find.**
```sh
rg -n "gem ['\"](field_struct|actionable)['\"]" Gemfile
```

**Fix.** Pin `tag: 'v0.12.0'` (or later) and follow field_struct's
[UPGRADING.md](https://github.com/Paymentbox-com/field_struct/blob/main/UPGRADING.md)
before bumping actionable.

**Why.** Generated action RBS takes every field type from
`FieldStruct::RBS.type_for` (0.12).

### Generated RBS owns the output instance variables
<!-- upgrading: rbs-output-ivars -->

**Symptom.** `rbs validate`:
``Duplicated instance variable name `@total` in `::Total` (RBS::InstanceVariableDuplicationError)``.

**Find.** Your hand-written ivar declarations; delete those named after an
output field:
```sh
rg -n '^\s*@\w+\s*:' sig
```

**Fix.**
```rbs
# before (your sig/total.rbs)
class Total < ::ApplicationAction
  @total: ::Integer
end
# after: delete the declaration; the generated file has `@total: ::Integer?`
```

**Why.** A step that assigns `@total = ...` now type-checks without hand-written sigs.

### Generated RBS declares the real superclass chain
<!-- upgrading: rbs-superclass-chain -->

**Symptom.** `rbs validate`:
`Superclass mismatch: ::Billing::BaseAction (RBS::SuperclassMismatchError)`,
or a duplicate declaration error for a namespace you declared as `module`
that Ruby defines as a class.

**Find.** Your hand-written bases declared straight under
`Actionable::Action`; compare each with Ruby's `superclass`:
```sh
rg -nP '^\s*class\s+[\w:]+\s*<\s*(?:::)?Actionable::Action\b' sig
```

**Fix.** Match Ruby's ancestry, or delete the declaration (the generated file
declares every named ancestor up to `Actionable::Action`):
```rbs
# before (Ruby says: class Billing::BaseAction < ApplicationAction)
class Billing::BaseAction < ::Actionable::Action
end
# after
class Billing::BaseAction < ::ApplicationAction
end
```

**Why.** Actions under an intermediate base were declared `< ::Actionable::Action`,
hiding their bases from the type checker. See
[USAGE, Base actions](USAGE.md#base-actions).

### `InputSchema` is a reserved name on actions with a fixed input
<!-- upgrading: rbs-input-schema -->

**Symptom.** `Actionable::RBS.generate` raises
`ArgumentError: Import::InputSchema is already defined (in Import); Actionable::RBS.generate names the generated input type InputSchema, so rename that constant`.

**Find.**
```sh
rg -nw InputSchema app lib
```

**Fix.**
```ruby
# before
class Import < ApplicationAction
  InputSchema = Struct.new(:rows)
end
# after
class Import < ApplicationAction
  RowSet = Struct.new(:rows)
end
```

**Why.** Generated RBS declares a typed `InputSchema` class; Ruby's anonymous
runtime schema has no name to clash with.

### Generated types are stricter
<!-- upgrading: rbs-stricter-types -->

**Symptom.** Steep reports new errors in code that calls your actions. Typed
`.run` keywords (optional ones accept `nil`; a defaulted required field is an
optional keyword), `def input: () -> InputSchema`, writers typed
`(T? value) -> T?`, nullable scalar array elements (`::Array[::String?]`), and
type arguments on bare generics replace `untyped`. A field typed by an
anonymous nested struct class now raises `ArgumentError` at generation.

**Find.** No pattern: Steep (or `rbs validate`) is the finder.

**Fix.** Fix the call sites Steep reports, or give the field an `rbs_type:`
override (honoured since 1.6). Name anonymous nested struct classes:
```ruby
# before
required :address, Class.new(FieldStruct::Base) { required :zip, :string }
# after
Address = Class.new(FieldStruct::Base) { required :zip, :string }
required :address, Address
```

**Why.** The types now describe what `run` really accepts and returns.

## 1.6.0 → 1.7.0

### Redeclaring a step or hook overrides it (last wins)
<!-- upgrading: step-redeclaration -->

**Symptom.** An action (or subclass) that declares the same `step :x`,
`case_step :x`, `step Child` or hook twice with different options now runs the
**last** options. Before, the second declaration was silently dropped. A
subclass's override now takes effect, so behaviour you thought was overridden
(and wasn't) changes.

**Find.** Same-file duplicates (two classes in one file sharing a step name
show up too):
```sh
rg -no --no-heading '^\s*(step|case_step|on_success|on_failure|on_skip|always)\s+:?[A-Za-z_][\w:]*' app lib | sed -E 's/^([^:]+):[0-9]+:[[:space:]]*/\1 /' | sort | uniq -d
```
A subclass redeclaring a parent's step lives in another file: no reliable
pattern. Grep the step names of each base class you subclass.

**Fix.** Keep one declaration with the options you mean:

<!-- doctest -->
```ruby
class Ship < Actionable::Action
  output { optional :packed, :boolean }
  step :pack, if: :ready?
  def pack = @packed = true
  def ready? = true
end

class ShipFragile < Ship
  step :pack, unless: :fragile? # replaces the parent's options, keeps its position
  def fragile? = true
end

Ship.run.packed        # => true
ShipFragile.run.packed # => nil
```

**Why.** Invariant 5 promises a subclass can override inherited steps.

### `always` hooks run even after an outcome hook halts
<!-- upgrading: always-after-halt -->

**Symptom.** An `always` hook that never ran after a `fail!` in `on_success`
now runs, and sees the adopted `Failure`. Under `transactional` it runs inside
the transaction, so its writes roll back with the failed run. Specs that
counted `always` calls, or expected its side effect to be absent, fail.

**Find.**
```sh
rg -n '^\s*always\b' app lib
```

**Fix.** Make each `always` hook correct for every outcome; check `result` when
the outcome matters:

<!-- doctest -->
```ruby
class Sync < Actionable::Action
  output { optional :audited, :string }
  step :work
  on_success :publish
  always :audit
  def work = nil
  def publish = fail!(:publish_failed)
  def audit = @audited = result.failure? ? 'failed' : 'ok'
end

result = Sync.run
result.code # => :publish_failed
```

**Why.** One hook's halt silently skipped cleanup and audit hooks.

### Adapter signatures now ship in `sig/`
<!-- upgrading: adapter-rbs -->

**Symptom.** `rbs validate`:
`::Actionable::Action.transactional has duplicated definitions in sig/mine.rbs:3:4...3:52 (RBS::DuplicatedMethodDefinitionError)`
when your own sig files declare the Rails, RSpec or Job surface.

**Find.**
```sh
rg -nP 'def (?:self\.)?(?:transactional|transaction_config|after_commit|after_commit_hooks|perform_actionable|(?:allow|stub)_actionable_\w+|actionable_\w+_result)\b' sig
```

**Fix.** Delete your declarations of those methods; the gem's are generated from
its YARD. They are declared on `Actionable::Action` even when
`actionable/rails` isn't required (RBS can't make a signature conditional).

**Why.** The adapters' public surface is now typed by the gem itself.

### `describe` lists `after_commit` hooks under the Rails adapter
<!-- upgrading: describe-after-commit -->

**Symptom.** With `actionable/rails` loaded, `describe[:hooks]` gains an
`after_commit:` key (an empty Array when there are none), so a spec comparing
the whole hash with `eq` fails.

**Find.**
```sh
rg -nP '(?<!RSpec)\.describe\b(?!_text)' spec
```

**Fix.**
```ruby
# before
expect(Pay.describe[:hooks]).to eq(on_success: [:notify], always: [])
# after
expect(Pay.describe[:hooks]).to include(on_success: [:notify], always: [])
```

**Why.** `describe` is the contract summary; `after_commit` hooks are part of it.

## 1.7.0 → 1.8.0

Both checks below raise on code that used to run. `Actionable.verb_position_check`
switches off the first; nothing switches off the second.

### A plain verb must end its step or hook method
<!-- upgrading: verb-position-guard -->

**Symptom.** An action's first run raises:
```
Actionable::DefinitionError: Charge#check (app/actions/charge.rb:5) calls `fail` with more code after it, which still runs: use fail! to stop here, or make it the method's last expression
(see USAGE, Control flow)
```
It covers `fail`, `fail_with`, `skip` and `succeed` (and `self.fail` …) in every
step, case-step branch target and lifecycle hook method (`after_commit`
included). It is checked once per class, on the first run.

**Find.** The cop is the finder; it applies the same rules. Add it to
`.rubocop.yml` (RuboCop >= 1.72; `require: [actionable/rubocop]` on older):
```yaml
plugins:
  - actionable:
      require_path: actionable/rubocop

Actionable/VerbNotLast:
  ActionBaseClasses: # replaces the default, so keep the two defaults
    - Actionable::Action
    - ApplicationAction
    - Billing::BaseAction # your own bases defined in other files
```
then `bundle exec rubocop --only Actionable/VerbNotLast`. The cop sees one file
at a time. It follows a subclass of a listed base only when both are in the
same file, so **list every intermediate base defined in its own file**, by full
name: with `ResponseReadyAction < ApplicationAction` and
`Orders::BaseAction < ResponseReadyAction` in separate files, list both. To
find candidates, count superclass names; the ones with many children are your
bases:
```sh
rg -oNP --no-filename --type ruby '^\s*class\s+[\w:]+\s*<\s*\K[\w:]+' app lib | sort | uniq -c | sort -rn | head -20
```
Steps a parent class declares are left to the runtime check.
Running the suite with the check on finds the rest. For a quick look before
enabling the cop, these list the two commonest shapes (not definitive):
```sh
rg -nP '^\s*(?:self\.)?(?:fail|fail_with|skip|succeed)\b(?!!).*\b(?:if|unless)\b' app lib
rg -nP '\b(?:fail|fail_with|skip|succeed)\b(?!!)[^#\n]*\b(?:and|or)\s+(?:return|next|break)\b' app lib
```

**Fix.** If the code after the verb should not run, add the bang; if it
should, make the verb last (or `return` it):
```ruby
# before
def check
  fail :card_expired if card.expired?
  charge_card
end
```

<!-- doctest -->
```ruby
class Charge < Actionable::Action
  step :check
  step :charge_card
  def check
    fail!(:card_expired) if expired? # stops here
  end

  def charge_card = nil
  def expired? = true
end

Charge.run.code # => :card_expired
```

`fail(:x) and return` never returns (`fail` returns `false`): write
`return fail(:x)`. [USAGE, Where a plain verb may go](USAGE.md#where-a-plain-verb-may-go)
has the full table. If you can't fix every offense before deploying, set
`Actionable.verb_position_check = false` in an initializer and keep the cop in
CI until you can turn it back on. The check is skipped on Ruby 3.2 without the
`prism` gem, and for methods from `eval` / `define_method`; the cop still
covers those.

**Why.** `fail :x if bad?` followed by more code keeps running: almost always
a `fail!` missing its bang.

### `fail` / `skip` codes must be identifiers
<!-- upgrading: identifier-codes -->

**Symptom.** At the call:
```
ArgumentError: Codes: failure code "card expired" is not an identifier; use a Symbol like :card_expired. Inside an action, fail records a failure, it is not Kernel#fail: to raise an exception, use raise
```
(`skip code ...` for a skip). A code must be a Symbol or String matching
`/\A[[:alpha:]_][[:alnum:]_]*[?!]?\z/`. Sentences, dotted (`'payment.declined'`)
and dashed (`:"not-found"`) codes, codes starting with a digit (`'404'`) and
classes (`fail GatewayError, 'down'`) all raise. Applies to `fail`, `fail!`,
`fail_with`, `fail_with!` (its `code:`), `skip` and `skip!`. **No opt-out:**
`verb_position_check = false` doesn't cover it.

**Find.** Three patterns: quoted codes, `code:` keywords, and class codes. They
skip calls on a receiver (`run.fail!(…)` on a model with its own `fail!`) and
also `self.fail …`, which is rare. A bare `fail` outside an action class
(`Kernel#fail` in a model or job) is fine to leave:
```sh
rg -nP --type ruby "(?<![\w.])(?:fail|skip)!?[ (]\s*(?:'[^']*[^\w'?!][^']*'|\"[^\"]*[^\w\"?!][^\"]*\"|['\"]\d|:['\"])" app lib
rg -nP --type ruby "\bcode:\s*(?:'[^']*[^\w'?!][^']*'|\"[^\"]*[^\w\"?!][^\"]*\"|['\"]\d|:['\"])" app lib
rg -nP --type ruby '(?<![\w.])fail!?[ (]\s*[A-Z]\w*(?:::[A-Z]\w*)*\s*(?:,|\)|$)' app lib
```
A code built at run time (`fail!(code_for(response))`) can't be found
statically; the runtime check is the finder.

**Fix.** Use a Symbol code and pass the sentence as the message; `raise` when
you meant an exception:
```ruby
# before
fail('card expired')
fail(GatewayError, 'gateway down')
skip('payment.declined')
```

<!-- doctest -->
```ruby
class Pay < Actionable::Action
  step :charge
  def charge = fail!(:card_expired, 'card expired') # was: fail('card expired')
end

result = Pay.run
result.code    # => :card_expired
result.message # => "card expired"
```

**Why.** `fail 'card expired'` is `Kernel#fail` habit; inside an action it
recorded the sentence as a code and kept running.

## 1.8.0 → 1.8.1

No caller action. The `Actionable/VerbNotLast` cop now resolves a superclass by
its lexical full name, as Ruby does, so two same-named classes in one file no
longer confuse it: it can only report fewer false offenses, never new ones on
code it already accepted. Everything else in 1.8.1 is test and tooling.

## 1.8.1 → 1.8.2

A patch release, but three fixes change what an app can see. Each is a bug
fix: the old behaviour contradicted the documentation.

| Change | Who is affected | What you see | Why |
|---|---|---|---|
| [`case_step` branch guards are honoured](#case_step-branch-guards-are-honoured) | Actions with `on …, if:` / `unless:` inside a `case_step` | **Silent:** a branch whose guard says no no longer runs; the run still succeeds | The guard was accepted and silently ignored |
| [`Actionable::RBS` refuses colliding codes](#actionablerbs-refuses-codes-that-share-an-output-class-name) | `typed_outcomes` actions with codes like `:ready` + `:ready_`, or non-ASCII codes | `ArgumentError` from `generate`, naming both codes | Both schemas landed in one RBS class, so one was typed wrong |
| [The verb check reads an aliased step's `def`](#the-verb-check-reads-an-aliased-steps-original-def) | Steps that name an `alias_method` alias of a method with a misplaced `fail` / `skip` | `DefinitionError` on first run | Aliased steps skipped the check that 1.8.0 applies to every other step |

**From 1.8.1:**
1. Bump the tag to `v1.8.2`.
2. Run the `case_step` Find below, and check that each guarded branch should
   really be skipped when its guard says no.
3. If you use `typed_outcomes`, regenerate your RBS: `generate` names any clash.
4. Run the suite.
Nothing else changed for callers. Codes ending in `?` / `!` get valid RBS class
names (`…PredicateFailureOutput`); before, their RBS didn't parse.

### `case_step` branch guards are honoured
<!-- upgrading: case-branch-guards -->

**Symptom.** A `case_step` branch declared with `if:` / `unless:` no longer
runs when its guard opts out: an output field it set is `nil`, a side effect
doesn't happen, or a spec that expected the branch to run fails. The run still
succeeds. A guarded-out branch does **not** fall through to the next `on` or
to the `default`.

**Find.** Guarded branches inside a `case_step` block:
```sh
rg -n '^\s*(on|default)\b.*,\s*(if|unless):' app lib
```

**Fix.** If the branch should run regardless, drop the guard. If a
guarded-out branch should fall back to another target, say so in a guard-free
branch body:
```ruby
# before: the guard was ignored, so 'sms' always sent an SMS
case_step :kind do
  on 'sms', :send_sms, if: :sms_enabled?
  default   :send_email
end

# after: 'sms' with SMS off sends an email
case_step :kind do
  on 'sms', :route_sms
  default   :send_email
end

def route_sms = sms_enabled? ? send_sms : send_email
```

**Why.** The guard was accepted and silently dropped; a branch now behaves
like the plain step it is.

### `Actionable::RBS` refuses codes that share an output class name
<!-- upgrading: rbs-outcome-class-names -->

**Symptom.** Under `typed_outcomes`, `Actionable::RBS.generate` raises:
```
ArgumentError: Billing::Charge: skip codes :ready and :ready_ both name ReadySkipOutput in the generated RBS; rename one of the codes
```
(or `... is not a valid RBS class name ...` for a code whose class name would not
be plain ASCII starting with a capital, e.g. `:日本` or `:foo_é`). Codes ending in `?` / `!` that declare an output
schema now generate `…PredicateFailureOutput` / `…BangSkipOutput`; before,
their RBS didn't parse, so nothing can reference the old names.

**Find.** Run `Actionable::RBS.generate` (your sigs task) for every action; it
names each clash. No search finds them reliably.

**Fix.** Rename one of the two codes, and its `fail` / `skip` calls:
```ruby
# before
skips(:ready) { required :id, :integer }
skips(:ready_) { required :id, :integer }

# after
skips(:ready) { required :id, :integer }
skips(:ready_later) { required :id, :integer }
```

**Why.** Both schemas went into one RBS class, so one of them typed wrong.

### The verb check reads an aliased step's original `def`
<!-- upgrading: verb-check-alias -->

**Symptom.** On first run, the same `DefinitionError` as for any
[verb-position offense](#a-plain-verb-must-end-its-step-or-hook-method),
naming the step (`Charge#charge`) and the `file:line` of the aliased `def`:
```
Actionable::DefinitionError: Charge#charge (app/actions/charge.rb:4) calls `fail` with more code after it, which still runs: use fail! to stop here, or make it the method's last expression
```

**Find.** Aliases in action classes; read the `def` each step alias points
at. The `Actionable/VerbNotLast` cop doesn't follow aliases, so it won't list
these:
```sh
rg -n '^\s*(alias_method\b|alias\s)' app lib
```

**Fix.** As for any offense: a bang verb, or make the verb the last
expression:
```ruby
# before
step :charge
def do_charge
  fail :late if late?
  @charged = true
end
alias_method :charge, :do_charge

# after
step :charge
def do_charge
  fail! :late if late?
  @charged = true
end
alias_method :charge, :do_charge
```

**Why.** The check looked the `def` up by the alias's name, found none, and
skipped the step.

## 1.8.2 → 1.9.0

The gem is renamed. Nothing in the library changed.

| Change | Who is affected | What you see | Why |
|---|---|---|---|
| [The gem is named `actionable-rb`](#the-gem-is-named-actionable-rb) | Every app (the Gemfile line), and apps that load the cop with `plugins:` | `bundle install` fails: "Could not find gem 'actionable' in …"; RuboCop: "Failed to load plugin `actionable`" | The `actionable` name on rubygems.org belongs to an unrelated 2014 gem |

**From 1.8.2:**
1. In the Gemfile, change `gem 'actionable'` to `gem 'actionable-rb'` and the
   tag to `v1.9.0`, then `bundle install`.
2. If `.rubocop.yml` loads the cop with `plugins:`, rename its key to
   `actionable-rb`.
3. Run the suite. No code changes: `require 'actionable'` and every constant
   stay the same.

### The gem is named `actionable-rb`
<!-- upgrading: gem-renamed-actionable-rb -->

**Symptom.** `bundle install` (or `bundle update actionable`) stops with
`Could not find gem 'actionable' in https://github.com/Paymentbox-com/actionable`
(Bundler matches a git source by the gemspec's name). With the cop loaded by
`plugins:`, `rubocop` stops with ``Failed to load plugin `actionable` because the
corresponding plugin class could not be determined``.

**Find.**
```sh
rg -n "gem ['\"]actionable['\"]" Gemfile gemfiles
rg -n -A1 '^\s*-\s*actionable:\s*$' .rubocop.yml
```

**Fix.**
```ruby
# Gemfile, before
gem 'actionable', git: 'https://github.com/Paymentbox-com/actionable', tag: 'v1.8.2'
# after
gem 'actionable-rb', git: 'https://github.com/Paymentbox-com/actionable', tag: 'v1.9.0'
```
```yaml
# .rubocop.yml, before
plugins:
  - actionable:
      require_path: actionable/rubocop
# after
plugins:
  - actionable-rb:
      require_path: actionable/rubocop
```
Keep `require 'actionable'` wherever you have it. A Gemfile that relies on
`Bundler.require` needs no `require:` option: the gem ships an
`actionable-rb.rb` that loads the library. The older `require:
[actionable/rubocop]` form in `.rubocop.yml` keeps working unchanged.

**Why.** To publish on rubygems.org, the gem needs a name nobody else holds;
`actionable` there is an unrelated project from 2014.

## Class-level API an app base class may rely on

Unchanged from 1.5.1 to 1.8.1, so a shared `ApplicationAction` that overrides
or calls these needs no edit: `fails` / `skips` (the declarations),
`declared_failures` / `declared_skips`, `allows_failure_code?` /
`allows_skip_code?`, `failure_output_schema` / `skip_output_schema`, `halt!`,
`fail_with!`, and the `Failure` / `Skipped` / `Success` constructors. `Result`
only gained an `@api private` accessor. Anything marked `@api private` in the
YARD docs can change in any release.

## New, opt-in: worth adopting

| Since | Feature | One line | Reference |
|---|---|---|---|
| 1.5.2 | Savepoint control | `transactional model: :x, requires_new: false` joins an outer transaction instead of taking a savepoint. | [USAGE, Rails adapter](USAGE.md#rails-adapter) |
| 1.6.0 | Typed `Actionable::RBS` | Typed `.run` keywords, `InputSchema`, output ivars and the real superclass chain for each action. | [USAGE, RBS for your actions](USAGE.md#rbs-for-your-actions) |
| 1.7.0 | `honor_retry_metadata` | Declared `retry: true` / `retry: false` decides the job's disposition (ActiveJob: `retry_on Actionable::Job::RetryableFailure`). | [USAGE, Background jobs](USAGE.md#background-jobs) |
| 1.7.0 | `after_commit` | Emails, webhooks and enqueues run only after the outermost transaction commits (ActiveRecord >= 7.2). | [USAGE, Rails adapter](USAGE.md#rails-adapter) |
| 1.7.0 | RSpec matchers, typed | `perform_actionable` and the `allow_/stub_actionable_*` helpers now have RBS. | [USAGE, RSpec integration](USAGE.md#rspec-integration) |
| 1.8.0 | `Actionable/VerbNotLast` cop | Lints misplaced plain verbs in CI, before the first run. | [USAGE, Where a plain verb may go](USAGE.md#where-a-plain-verb-may-go) |

## If something else breaks

**Bisect by version.** Pin each release in turn and run the failing spec; the
first tag that fails names the section above to reread:
```ruby
gem 'actionable', git: 'https://github.com/Paymentbox-com/actionable', tag: 'v1.5.2' # then v1.6.0, v1.7.0, v1.8.0
```
From `v1.9.0` the gem is `actionable-rb`, so that line says `gem 'actionable-rb'`.
Remember the field_struct floor at each step (0.11 for 1.5.2, 0.12 from 1.6.0).

**A guard offense or a real bug?**

- `DefinitionError` "... calls `fail` with more code after it ..." is the verb
  guard. It goes away with `Actionable.verb_position_check = false`; a real bug
  doesn't. The cop reports the same line.
- `ArgumentError` "... code ... is not an identifier" is the code check, raised
  at the `fail` / `skip` call itself. The backtrace's first app frame is the
  line to change.
- `DefinitionError` "... declares step(s) calling ... but does not implement
  them" or "... set @result ..." are the 1.5.2 definition checks.
- Anything else (a different result code, missing output, a hook that runs or
  doesn't) is behaviour: find the version with the bisect above, then the entry
  in that version's section. If none fits, it's a bug. Open an issue with the
  action and the two versions.
