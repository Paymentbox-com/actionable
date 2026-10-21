# frozen_string_literal: true

# Optional RSpec integration (decision D12). Load it explicitly with
# `require 'actionable/rspec'` (typically in spec_helper, after rspec). Never
# loaded by the core entry point.
require_relative '../actionable' # ensure the core is loaded (self-contained entry)
require_relative 'rspec/matchers'
require_relative 'rspec/stubs'

module Actionable
  # RSpec matchers and stubs for actions (decision D12).
  module RSpec
    # The refusal for a stub, +and_fail+ or +and_skip+ naming a code an action
    # that declares failures (decision D20) or skips (decision D21) doesn't
    # declare.
    #
    # @param action_class [Class<Actionable::Action>]
    # @param code [Symbol, String]
    # @param outcome [:failure, :skip] which declarations the code was checked against
    # @return [String]
    def self.undeclared_code_message(action_class, code, outcome: :failure)
      if outcome == :skip
        declared = action_class.declared_skips.keys.map(&:inspect).join(', ')
        return "#{action_class.name || "action"} does not declare skip #{code.to_sym.inspect} " \
               "(declared: #{declared}); a stub or and_skip with it tests a skip the action can never return"
      end

      declared = action_class.declared_failures.keys.map(&:inspect).join(', ')
      "#{action_class.name || "action"} does not declare #{code.to_sym.inspect} (declared: #{declared}); " \
        'a stub or and_fail with it tests a failure the action can never return'
    end
  end
end

if defined?(RSpec)
  RSpec.configure do |config|
    config.include Actionable::RSpec::Matchers
    config.include Actionable::RSpec::Stubs
  end
end
