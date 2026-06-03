# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code
in this repository.

## Context Documents

Before starting any work, read these in order:

| Document | Purpose |
|----------|---------|
| `docs/origin/plan.md` | **Source of truth.** Phase 1 design decisions (D1–D18), the 16-slice plan, Phase 2+ backlog, glossary. |
| `.claude/project_intent.md` | What Actionable is/isn't, terminology, design invariants. |
| `.claude/tdd_guidelines.md` | Test-driven development patterns (non-negotiable). |
| `.claude/planning_guide.md` | How to plan and build a feature/slice. |
| `docs/origin/first_discussion.md` | The original idea — historical context. |

---

## Project Overview

**Actionable** is a Ruby gem for **service objects**: subclass `Actionable::Action`,
declare an ordered list of **steps**, implement each as a method, and run it. A run
returns a single FieldStruct-backed **result** (`Success`, `Failure`, or `Skipped`)
with a `code`, `message`, `errors`, a typed `output`, and an execution `history`.
The three outcomes have strict predicates (`success?` / `failure?` / `skipped?`)
plus `ok?` (≡ "didn't fail"); see decision D17 for the `:skip` outcome.

This is a **clean-slate rebuild** of an older gem of the same name. The redesign
goals are: full type information (RBS via Sord + YARD), agent-readability, a
pure-Ruby core with Rails as an optional adapter, and an explicit typed `output`
instead of the old "capture every instance variable" magic. See `docs/origin/plan.md`
for the locked decisions.

The library targets **v1.0.0**. The slice plan and decisions D1–D18 are authoritative.

---

## Code Conventions

### JSON Handling
Use **Oj**, not the built-ins: `Oj.load(str)` / `Oj.dump(obj)` — never `JSON.parse`
or the built-in `to_json`.

### File loading
Standard `lib/actionable.rb` entry point with explicit `require_relative` for every
**core** file. **No autoload, no Zeitwerk.** The optional adapters
(`actionable/rails`, `actionable/rspec`) are **not** required by the core entry
point — they're separate requires. When you add a new core file under
`lib/actionable/`, add its `require_relative` to `lib/actionable.rb`.

### Control flow
Halting a run uses `throw :actionable_halt`, never an exception. The runner never
`rescue`s `Exception`/`StandardError` for control flow — genuine errors propagate to
the caller. (Decision D4.)

### Rails is optional
Nothing in the core load path may `require 'active_*'`. Transactions and
`ProxyValidator` live behind `require 'actionable/rails'`. (Decision D8.)

### Documentation
Public methods carry YARD comments — purpose, `@param`, `@return`, and any
non-obvious behavior. These feed Sord; keep them accurate. Don't restate what the
code already shows.

#### Documentation checklist (before a feature/behavior commit)
A behavior change isn't done until the docs are. Some of this is enforced
(`rake docs:check`), some is judgment:

| Surface | When to update | Enforced? |
|---|---|---|
| **YARD comments** + `rake sigs:generate` | any public API add/change | ✅ `sigs:check` |
| **USAGE.md** (the catalog) | every new/changed public method | ✅ `rake docs:check` (API→USAGE coverage) |
| **CHANGELOG.md** `[Unreleased]` | any `lib/**` change | ✅ `rake docs:check` (freshness) |
| **README.md** | a user-facing feature or verb | ⚠️ judgment |
| **docs/getting_started.md** | a feature an adopter would reach for early | ⚠️ judgment |
| **AGENTS.md** + **skills/actionable/SKILL.md** | a new verb / DSL macro / adapter agents should know | ⚠️ judgment |
| **docs/origin/plan.md** | a new locked decision (Dnn) | ⚠️ judgment |

`rake docs:check` is run automatically before commits in the Claude Code session
(a hook in `.claude/settings.json`). It does **not** judge prose quality — the
⚠️ rows are on you. Run it yourself any time: `bundle exec rake docs:check`. Its
allowlist of intentionally-undocumented public methods lives in the `docs:check`
task in the `Rakefile`; add to it only with intent.

### Linting & coverage
Rubocop must pass before commit. Coverage via SimpleCov (`COVERAGE=1 bin/rspec`).

---

## Testing

**TDD is non-negotiable.** Every change starts with a failing test. See
`.claude/tdd_guidelines.md`.

```bash
bin/rspec                           # Run all specs
bin/rspec spec/path/file_spec.rb    # Run specific file
bin/rspec spec/path/file_spec.rb:42 # Run specific line
bundle exec rake                    # Full suite + rubocop
COVERAGE=1 bin/rspec                # With coverage

# Sigs / docs / release prep
bundle exec rake sigs:generate      # Regenerate sig/actionable.rbs from YARD via sord
bundle exec rake sigs:check         # Fail if committed sigs are stale (CI guard)
bundle exec rake sigs:validate      # rbs validate the committed sig file
bundle exec rake docs:generate      # YARD HTML to doc/ (--fail-on-warning)
bundle exec rake docs:stats         # List undocumented public methods
bundle exec rake release:check      # Full pre-flight: spec + rubocop + sigs + docs
```

**The core suite must pass with only `field_struct` loaded** — no ActiveRecord. Rails
behavior is exercised in adapter specs that `require 'actionable/rails'`.

**Run `rake release:check` before every release commit.**

---

## Git Workflow

### Conventional Commits

```
feat: add nested action steps with input/expose
fix: keep StandardError propagating past the halt catch
refactor: extract expose filtering into Steps::Action
test: add coverage for case_step Array membership
docs: add usage examples to README
chore: wire sord/rbs/yard toolchain
```

| Type | When to use |
|------|-------------|
| `feat` | New behavior (TDD green — test + implementation together) |
| `fix` | Bug fix (regression test + fix) |
| `refactor` | Restructuring, no behavior change (tests unchanged) |
| `test` | Tests for existing untested code (not normal TDD) |
| `docs` | Documentation only |
| `chore` | Dependencies, CI, tooling, releases — no production code |

### Atomic Commits
One logical change per commit; tests ship with their code; tests pass at every
commit; each commit independently revertable; the message explains *why*.

### Branches
- `main` is the released branch; tagged releases come from here.
- `develop` is the integration branch.
- Per-feature branches off `develop`, merged back into `develop`.
- Release flow: `develop` → `main` via PR when cutting a version.

Use descriptive branch names off `develop`.

### Cutting a release
A version isn't released until there's a **GitHub Release** — a git tag alone is
invisible on the Releases page. The full sequence:
1. Bump `lib/actionable/version.rb`; move `CHANGELOG.md` `[Unreleased]` → a dated
   `## [x.y.z]` section (leave `[Unreleased]` empty).
2. `bundle exec rake release:check`.
3. Commit `chore: release vX.Y.Z`; merge `develop` → `main`.
4. `git tag -a vX.Y.Z`; push `main`, `develop`, and the tag.
5. `gh release create vX.Y.Z --title "Actionable vX.Y.Z" --notes-file <changelog section>`
   — **don't skip this**; tag ≠ Release.

### Commit footer
End AI-assisted commits with a `Co-Authored-By:` trailer.

---

## When in doubt

The slice plan in `docs/origin/plan.md` is the authoritative roadmap. Decisions
D1–D18 are locked unless explicitly revisited. If a question isn't answered there,
ask before guessing.
