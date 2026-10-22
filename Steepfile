# frozen_string_literal: true

# Type-checks the core library against the committed signatures. Report-only:
# run it through gemfiles/types.gemfile (Steep 2.x); CI never fails on it.
#
# The optional adapters are out of scope: they carry no YARD sigs by design
# (.yardopts excludes them) and gem_rbs_collection has no RSpec sigs.
#
# The stdlib libraries match rbs_collection.yaml so ::Date / ::Time /
# ::DateTime / ::BigDecimal references in sig/actionable.rbs resolve.
target :lib do
  signature 'sig'

  check 'lib'
  ignore 'lib/actionable/rspec', 'lib/actionable/rspec.rb',
    'lib/actionable/rails', 'lib/actionable/rails.rb',
    'lib/actionable/railtie.rb'

  library 'date', 'time', 'bigdecimal'
end
