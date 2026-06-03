# frozen_string_literal: true

module Actionable
  module Steps
    # Build the right step type from a +step+ declaration's target, inferring
    # the type from the argument (decision D2): a Symbol/String becomes a
    # {Steps::Method}, an action +Class+ becomes a {Steps::Action}. The case
    # block type ({Steps::Case}) joins in a later slice.
    #
    # @param target [Symbol, String, Class<Actionable::Action>] the step target
    # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+,
    #   and for action steps +:input+ / +:expose+)
    # @return [Steps::Base] the constructed step
    # @raise [ArgumentError] when the target's type is not supported
    def self.build(target, **options)
      case target
      when Symbol, String then Method.new(target, **options)
      when Class
        raise ArgumentError, "unsupported step target: #{target.inspect}" unless target < Actionable::Action

        Action.new(target, **options)
      else
        raise ArgumentError, "unsupported step target: #{target.inspect}"
      end
    end
  end
end
