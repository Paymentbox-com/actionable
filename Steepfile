# frozen_string_literal: true

# Type-checks the library sources against the committed signatures.
# The stdlib libraries match rbs_collection.yaml so ::Date / ::Time /
# ::DateTime / ::BigDecimal references in sig/actionable.rbs resolve.
target :lib do
  signature 'sig'

  check 'lib'

  library 'date', 'time', 'bigdecimal'
end
