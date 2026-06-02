# frozen_string_literal: true

module Actionable
  module Steps
    # Build the right step type from a +step+ declaration's target, inferring
    # the type from the argument (decision D2): a Symbol/String becomes a
    # {Steps::Method}. Other targets (an action Class → {Steps::Action}, a
    # case block → {Steps::Case}) join in later slices.
    #
    # @param target [Symbol, String] the step target
    # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+)
    # @return [Steps::Base] the constructed step
    # @raise [ArgumentError] when the target's type is not supported
    def self.build(target, **)
      case target
      when Symbol, String then Method.new(target, **)
      else
        raise ArgumentError, "unsupported step target: #{target.inspect}"
      end
    end
  end
end
