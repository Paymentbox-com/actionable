# frozen_string_literal: true

module Actionable
  # Shared branch-value matching for the two places Actionable dispatches on a
  # value: case steps (decision D3) and discriminated input (decision D19). A
  # branch value matches by Array membership, by +Regexp#match?+ against the
  # value's string form, or by +==+.
  module ValueMatch
    module_function

    # @param branch_value [Object, Array, Regexp] the declared branch matcher
    # @param value [Object] the runtime value being dispatched on
    # @return [Boolean] whether +value+ matches +branch_value+
    def matches?(branch_value, value)
      case branch_value
      when Array then branch_value.include?(value)
      when Regexp then branch_value.match?(value.to_s)
      else branch_value == value
      end
    end
  end
end
