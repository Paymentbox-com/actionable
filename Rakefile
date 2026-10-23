# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop sigs:untyped]

desc 'Run the indicative micro-benchmarks in benchmarks/ (BENCH_ITERATIONS=n; not in the default task)'
task :bench do
  ruby 'benchmarks/run.rb'
end

# --- Type signatures (sord + rbs) -------------------------------------

SIG_FILE = 'sig/actionable.rbs'

# Sord limitations that need a tiny post-process pass.
#
# Each entry is [search_regex, replacement]. Keep this list short and
# document each entry — if it grows, it's a smell that we should fix
# YARD upstream or open an issue against Sord.
SORD_FIXUPS = [
  # Sord emits a bare `include Enumerable`, but RBS's Enumerable is generic and
  # requires its element type. BatchResult enumerates Results (decision D19).
  [/^(\s*)include Enumerable$/, '\1include ::Enumerable[Result]'],
  # Constants a consumer cannot reference, which RBS has no way to mark:
  # those assigned inside +class << self+ live on the singleton class
  # (+Action.singleton_class::OUTCOME_BASES+, not +Action::OUTCOME_BASES+), and
  # +private_constant+s raise NameError from outside. Sord declares both as
  # public constants of the class, so drop them.
  [/^\s*(?:RESERVED_OUTPUT_FIELDS|OUTCOME_BASES|BOOL_CLASSES|HASH_OUTPUT): .*\n/, '']
].freeze

# The committed sigs may only get MORE typed. `sigs:untyped` counts the
# non-comment `untyped` tokens in sig/ and fails when the count is above this
# ceiling — or below it, so a typing PR lowers the ceiling in the same commit
# and it can never creep back up. Ratchet down only.
SIG_UNTYPED_CEILING = 27

# Every place sord falls back to `untyped` because the YARD is missing
# ([OMIT]) or names a duck type ([DUCK]), keyed without file:line so edits
# above a method don't churn the list. `sigs:generate` / `sigs:check` fail on
# a warning not listed here (type it in YARD instead) and on a listed entry
# sord no longer emits (delete it). Shrink-only, like the ceiling.
SORD_WARNING_ALLOWLIST = [
  'DUCK Actionable::Action#fail_with: #errors looks like a duck type',
  'DUCK Actionable::Action#fail_with!: #errors looks like a duck type',
  'DUCK Actionable::Failure#absorb_errors_from: #errors looks like a duck type',
  'DUCK Actionable::Steps::Base#evaluate_guard: #call looks like a duck type'
].freeze

# --- Docs guard (`docs:check`, decision D19) --------------------------

# The user-facing API classes whose public methods must be documented in
# USAGE.md (the catalog). Reflection respects `private`, so internal helpers
# are excluded automatically.
DOC_API_CLASSES = %w[
  Actionable Actionable::Action Actionable::Result Actionable::Success Actionable::Failure
  Actionable::Skipped Actionable::BatchResult Actionable::InputDispatch
  Actionable::ValueMatch Actionable::Job
].freeze

# Public methods intentionally NOT in the USAGE reference: attribute writers,
# secondary/internal predicates and accessors, and delegation hooks. A NEW
# public method that isn't here must be documented in USAGE (or added here
# deliberately). Keep this list honest — it's the "knowingly undocumented"
# ledger, not a dumping ground.
DOC_COVERAGE_ALLOWLIST = %w[
  absorb_errors_from always_hooks failure_hooks skip_hooks success_hooks
  catch_halt verb_position_check=
  branches default_schema define schema_for schemas
  code= history= message= metadata= output=
  input_dispatch input_schema output_schema
  length measure_all? measure_rate measure_sample_hit? measure_sampled?
  method_missing
  output_fields_set output_fields_set=
].freeze

# Non-comment `untyped` tokens across every sig/ file.
def sig_untyped_count
  Dir['sig/**/*.rbs'].sum do |path|
    File.foreach(path).sum { |line| line.lstrip.start_with?('#') ? 0 : line.scan(/\buntyped\b/).size }
  end
end

# Sord's [OMIT]/[DUCK] lines as allowlist keys: "KIND Path: message", with
# the file:line, the ", using/replacing with untyped" tail and ANSI colours
# dropped.
def sord_untyped_warnings(output)
  output.gsub(/\e\[[\d;]*m/, '').each_line.filter_map do |line|
    next unless (m = line.match(/^\[(OMIT|DUCK)\s*\] \((\S+)\) \S+:\d+: (.*?)(?:, (?:using|replacing with) untyped)?$/))

    "#{m[1]} #{m[2]}: #{m[3]}"
  end
end

def check_sord_warnings!(output)
  found = sord_untyped_warnings(output)
  unlisted = found - SORD_WARNING_ALLOWLIST
  stale = SORD_WARNING_ALLOWLIST - found
  return if unlisted.empty? && stale.empty?

  msg = +'::: sord untyped-fallback allowlist (SORD_WARNING_ALLOWLIST in the Rakefile) is out of date.'
  msg << "\nNew [OMIT]/[DUCK] — give these a YARD type:\n  #{unlisted.join("\n  ")}" unless unlisted.empty?
  msg << "\nStale — sord no longer emits these; delete them:\n  #{stale.join("\n  ")}" unless stale.empty?
  abort msg
end

def sord_run(target)
  # Temporarily hide the committed sig file — YARD picks up sig/*.rbs as
  # input, and the prior file's entries confuse Sord's parameter-matching
  # for kwarg-heavy methods. Move it aside, run sord, restore on failure
  # or when generating to a different target (e.g. sigs:check).
  stash = "#{SIG_FILE}.stashed-by-sord-rake"
  stashed = File.exist?(SIG_FILE) && File.rename(SIG_FILE, stash) && true
  ok = false
  require 'open3'
  cmd = "bundle exec sord #{target} --rbs --no-sord-comments"
  puts cmd
  output, status = Open3.capture2e(cmd)
  puts output
  abort "::: sord failed (#{status})" unless status.success?
  contents = File.read(target)
  # Without --replace-errors-with-untyped, a YARD type sord cannot parse
  # lands as a SORD_ERROR_ constant; fail rather than commit it.
  abort "::: sord emitted SORD_ERROR_ types in #{target}; fix the YARD types it warned about." if contents.include?('SORD_ERROR')
  check_sord_warnings!(output)
  SORD_FIXUPS.each { |pattern, replacement| contents.gsub!(pattern, replacement) }
  File.write(target, contents)
  ok = true
ensure
  # Only restore the stash if (a) sord failed mid-flight, or (b) the
  # caller is writing to a tmp target and we want the committed file
  # back in place. When sord succeeded and target *was* SIG_FILE, the
  # fresh output already lives at SIG_FILE — restoring would clobber it.
  restore = stashed && File.exist?(stash) && (!ok || target != SIG_FILE)
  File.rename(stash, SIG_FILE) if restore
  File.delete(stash) if stashed && File.exist?(stash) && !restore
end

namespace :sigs do
  desc 'Regenerate sig/actionable.rbs from YARD comments via sord'
  task :generate do
    sord_run(SIG_FILE)
  end

  desc 'Check that the committed sig file matches a fresh sord run (CI guard)'
  task :check do
    require 'tmpdir'
    require 'digest'
    Dir.mktmpdir do |dir|
      tmp = File.join(dir, 'actionable.rbs')
      sord_run(tmp)
      committed = Digest::SHA256.file(SIG_FILE).hexdigest
      generated = Digest::SHA256.file(tmp).hexdigest
      next if committed == generated

      warn "::: #{SIG_FILE} is stale. Run `rake sigs:generate` and commit the result."
      sh "diff -u #{SIG_FILE} #{tmp} || true"
      exit 1
    end
  end

  desc 'Validate every sig/ file against the RBS grammar and the stdlib/collection types'
  task :validate do
    # The rbs collection (stdlib date/time/bigdecimal sigs) must be present
    # for the fully-qualified ::Date / ::Time / ::DateTime / ::BigDecimal
    # types in the generated sig to resolve. Install it on first run so a
    # fresh checkout's `rake release:check` is self-contained; the lock and
    # installed sigs float with the (uncommitted) Gemfile.lock.
    sh 'bundle exec rbs collection install' unless File.exist?('rbs_collection.lock.yaml')
    sh 'bundle exec rbs -I sig validate'
  end

  desc 'Fail unless the non-comment `untyped` count in sig/ equals SIG_UNTYPED_CEILING (ratchet down only)'
  task :untyped do
    count = sig_untyped_count
    if count > SIG_UNTYPED_CEILING
      abort "::: sig/ has #{count} untyped (ceiling #{SIG_UNTYPED_CEILING}). Type the new ones in YARD; " \
            'the ceiling only goes down.'
    elsif count < SIG_UNTYPED_CEILING
      abort "::: sig/ has #{count} untyped, below the ceiling of #{SIG_UNTYPED_CEILING}. " \
            "Lower SIG_UNTYPED_CEILING in the Rakefile to #{count} so it can't creep back up."
    end
    puts "sigs:untyped: #{count} untyped in sig/ (ceiling #{SIG_UNTYPED_CEILING})."
  end
end

# --- Documentation (yard) ---------------------------------------------

namespace :docs do
  desc 'Generate HTML API docs into doc/ from YARD comments'
  task :generate do
    # --fail-on-warning surfaces broken YARD references and malformed
    # tags so a release doesn't go out with a busted doc tree.
    sh 'bundle exec yard doc --fail-on-warning'
  end

  desc 'Show YARD coverage stats and list undocumented public methods'
  task :stats do
    sh 'bundle exec yard stats --list-undoc'
  end

  desc 'Guard that code changes are reflected in the docs (decision D19)'
  task :check do
    require_relative 'lib/actionable'
    require_relative 'lib/actionable/job'
    failures = []

    # 1. CHANGELOG freshness — a change under lib/ needs an [Unreleased] entry.
    #    A bare version bump (lib/actionable/version.rb only) is exempt: it IS
    #    the release commit, which deliberately empties [Unreleased].
    changed = `git diff HEAD --name-only`.split("\n")
    lib_changes = changed.grep(%r{\Alib/.*\.rb\z}) - ['lib/actionable/version.rb']
    unless lib_changes.empty?
      unreleased = File.read('CHANGELOG.md')[/##\s*\[Unreleased\](.*?)(?=^##\s|\z)/m, 1].to_s
      if unreleased.strip.empty?
        failures << 'CHANGELOG.md [Unreleased] is empty but lib/ changed — add an entry.'
      end
    end

    # 2. API → USAGE coverage — every public API method (minus the allowlist)
    #    must be named in USAGE.md.
    usage = File.read('USAGE.md')
    api = DOC_API_CLASSES.flat_map do |const|
      klass = Object.const_get(const)
      klass.singleton_methods(false) + klass.public_instance_methods(false)
    end.map(&:to_s).uniq - DOC_COVERAGE_ALLOWLIST
    undocumented = api.reject do |method|
      base = method.sub(/[?!]\z/, '')
      usage.include?(method) || usage.include?(base)
    end
    unless undocumented.empty?
      failures << 'Public API not documented in USAGE.md (document it, or add to ' \
                  "the docs:check allowlist with intent): #{undocumented.sort.join(", ")}"
    end

    abort "docs:check failed:\n- #{failures.join("\n- ")}" unless failures.empty?
    puts 'docs:check: CHANGELOG fresh; public API documented in USAGE.'
  end
end

# --- Release pre-flight -----------------------------------------------

namespace :release do
  desc 'Run the full pre-release battery: specs, rubocop, sig check, docs build'
  task check: %w[spec rubocop sigs:untyped sigs:check sigs:validate docs:generate]
end
