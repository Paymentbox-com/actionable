# frozen_string_literal: true

# Type-checks the library against the committed signatures at Steep's default
# diagnostic level. Report-only: run it through gemfiles/types.gemfile
# (Steep 2.x); CI never fails on it (owner ruling P11: a strict gate is
# revisited after Tier 1).
#
# The adapters a client calls (actionable/rails' transactional and
# after_commit, actionable/rspec's matchers and stubs, actionable/job) are in
# scope: sord generates their sigs from YARD like the core's. Their bodies call
# ActiveRecord and rspec-mocks, which have no sigs in this lane, so they add
# report-only problems. Still out of scope, as they have no sigs (.yardopts
# excludes them): ProxyValidator (ActiveModel-typed), the Railtie,
# actionable/rspec/coverage, and the recording-verb analyzer and its RuboCop
# cop (Prism / RuboCop / lint_roller types a host may not have: Prism isn't
# in Ruby 3.2, and RuboCop is a dev tool).
#
# The stdlib libraries match rbs_collection.yaml so ::Date / ::Time /
# ::DateTime / ::BigDecimal references in sig/actionable.rbs resolve.
target :lib do
  signature 'sig'

  check 'lib'
  ignore 'lib/actionable/rails/proxy_validator.rb', 'lib/actionable/railtie.rb',
    'lib/actionable/rspec/coverage', 'lib/actionable/rspec/coverage.rb',
    'lib/actionable/verb_position.rb', 'lib/actionable/rubocop.rb', 'lib/actionable/rubocop'

  library 'date', 'time', 'bigdecimal'
end
