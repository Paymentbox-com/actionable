# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# --- Type signatures (sord + rbs) -------------------------------------

SIG_FILE = 'sig/actionable.rbs'

# Sord limitations that need a tiny post-process pass.
#
# Each entry is [search_regex, replacement]. Keep this list short and
# document each entry — if it grows, it's a smell that we should fix
# YARD upstream or open an issue against Sord. Empty for now; entries
# get added as the library surface grows and Sord gaps surface.
SORD_FIXUPS = [].freeze

def sord_run(target)
  # Temporarily hide the committed sig file — YARD picks up sig/*.rbs as
  # input, and the prior file's entries confuse Sord's parameter-matching
  # for kwarg-heavy methods. Move it aside, run sord, restore on failure
  # or when generating to a different target (e.g. sigs:check).
  stash = "#{SIG_FILE}.stashed-by-sord-rake"
  stashed = File.exist?(SIG_FILE) && File.rename(SIG_FILE, stash) && true
  ok = false
  sh "bundle exec sord #{target} --rbs --no-sord-comments --skip-constants --replace-errors-with-untyped"
  contents = File.read(target)
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

  desc 'Validate sig/actionable.rbs against the RBS grammar'
  task :validate do
    # The rbs collection (stdlib date/time/bigdecimal sigs) must be present
    # for the fully-qualified ::Date / ::Time / ::DateTime / ::BigDecimal
    # types in the generated sig to resolve. Install it on first run so a
    # fresh checkout's `rake release:check` is self-contained; the lock and
    # installed sigs float with the (uncommitted) Gemfile.lock.
    sh 'bundle exec rbs collection install' unless File.exist?('rbs_collection.lock.yaml')
    sh "bundle exec rbs -I #{SIG_FILE} validate"
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
end

# --- Release pre-flight -----------------------------------------------

namespace :release do
  desc 'Run the full pre-release battery: specs, rubocop, sig check, docs build'
  task check: %w[spec rubocop sigs:check sigs:validate docs:generate]
end
