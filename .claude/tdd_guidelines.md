# TDD Guidelines

> TDD is non-negotiable. Every change starts with a failing test.

---

## The TDD Cycle

```
RED ──────► GREEN ──────► REFACTOR ──┐
 │           │              │        │
 Write       Make test      Clean    │
 failing     pass           up       │
 test        (minimum)      code     │
 │                                   │
 └───────────────────────────────────┘
```

1. **RED**: Write a test describing the desired behavior. Run it — it must fail.
2. **GREEN**: Write the minimum code to pass. No optimization.
3. **REFACTOR**: Improve structure. Tests are the safety net.

---

## Commit Rhythm

Each TDD cycle maps to atomic commits. The commit history tells the story of *why*
code changed.

```
RED ─────────────► GREEN ──────────────► REFACTOR ────────────┐
 │                  │                      │                   │
 Write failing      Make it pass           Clean up            │
 test               (minimum code)         (no behavior change)│
 ┊                  git commit             git commit          │
 ┊                  "feat: ..."            "refactor: ..."     │
 ┊                  (includes the test)    (optional)          │
 └─────────────────────────────────────────────────────────────┘
```

### The Rule: Tests Ship With Their Code

The **green** commit includes both the test and the implementation. The test
*proves* the code works — they are one logical change. Never commit tests separately
from the code that makes them pass.

### Commit Types by TDD Phase

| Phase | Commit type | Example | What's in the commit |
|-------|-------------|---------|---------------------|
| GREEN (new feature) | `feat:` | `feat: add fail/succeed control flow with throw/catch halt` | Test + implementation |
| GREEN (bug fix) | `fix:` | `fix: keep StandardError propagating past the halt catch` | Regression test + fix |
| REFACTOR | `refactor:` | `refactor: extract expose filtering into Steps::Action` | Restructuring only, same test count |
| Test-only (rare) | `test:` | `test: add coverage for case_step Array membership` | Tests for existing untested code |

### Atomic Commit Principles

1. **One logical change per commit** — don't mix features; don't mix refactoring with behavior changes.
2. **Tests pass at every commit** — never commit a broken state.
3. **Independently revertable** — reverting any commit leaves the codebase working.
4. **Commit message explains why** — the diff shows *what*; the message explains *why*.

---

## Test Behavior, Not Implementation

### DO: Test Outcomes

```ruby
it 'returns a failure with the given code when fail! is called' do
  action = Class.new(Actionable::Action) do
    step :guard
    def guard = fail!(:nope, 'stop here')
  end
  result = action.run
  expect(result).to be_failure
  expect(result.code).to eq(:nope)
end

it 'surfaces declared output on the result' do
  action = Class.new(Actionable::Action) do
    output { required :total, :integer }
    step :compute
    def compute = @total = 42
  end
  expect(action.run.total).to eq(42)
end

it 'lets a raised StandardError propagate to the caller' do
  action = Class.new(Actionable::Action) do
    step :boom
    def boom = raise(ArgumentError, 'kaboom')
  end
  expect { action.run }.to raise_error(ArgumentError, 'kaboom')
end
```

### DON'T: Test Internals

```ruby
# BAD: asserting on private mechanics
expect(runner).to receive(:catch_halt)
# BAD: poking instance variables
action.instance_variable_get(:@result)
# BAD: asserting the throw symbol directly
expect { ... }.to throw_symbol(:actionable_halt)   # control-flow detail, not behavior
```

### The Refactoring Test

> If you can refactor implementation without changing tests, your tests are correct.
> If refactoring breaks tests, they're testing implementation.

The whole point of the rebuild is that `fail!` could switch from `throw` to some
other primitive and these tests would still pass — because they assert on the
*result*, not the mechanism.

---

## Describe Behaviors, Not Methods

```ruby
# BAD: method-centric (brittle)
RSpec.describe Actionable::Runner do
  describe '#run_through_main_steps' do

# GOOD: behavior-centric (durable)
RSpec.describe Actionable::Action do
  describe 'running an action that halts early' do
    it 'skips the remaining steps' do
```

Rename `run_through_main_steps`? Extract a `Pipeline` object? Behavior-focused tests
survive it.

---

## Actionable-Specific Testing Notes

- **Use anonymous action classes** (`Class.new(Actionable::Action) do … end`) for
  unit specs so each example declares exactly the steps/output it needs. Reserve
  named fixtures in `spec/support` for cross-cutting scenarios.
- **Always cover the four control-flow shapes** where relevant: soft `fail`/`succeed`
  (record, continue), bang `fail!`/`succeed!` (record, halt), `halt!` (stop, keep
  result), and a raised exception (propagates).
- **Output is a contract** — assert that *undeclared* ivars do **not** appear on the
  result, not just that declared ones do.
- **Core specs must not load Rails.** Anything exercising `transactional` or
  `ProxyValidator` goes in adapter specs that `require 'actionable/rails'`. The core
  suite must pass with only `field_struct` loaded.
- **Prefer real objects to mocks.** Stub external collaborators (a mailer, an HTTP
  client) at the boundary; use real actions, steps, and results.
- **Matcher specs use the matcher.** Test `perform_actionable` by exercising it
  against real actions, including its failure-message output.

---

## Anti-Patterns

| Anti-Pattern | Bad | Good |
|--------------|-----|------|
| Method-centric structure | `describe '#run'` | `describe 'running an action that fails'` |
| Testing the halt mechanism | `expect { }.to throw_symbol(:actionable_halt)` | Assert the resulting `Failure` |
| Swallowing in the test | `rescue` around `run` | Let it raise; use `raise_error` / `and_raise` |
| God tests | 20 assertions in one `it` | One behavior per example |
| Over-mocking | Double the runner and steps | Use a real anonymous action |
| Brittle message strings | Match full sentences | Assert on `code`; match messages loosely |
