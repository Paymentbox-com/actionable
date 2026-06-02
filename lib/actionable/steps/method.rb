# frozen_string_literal: true

module Actionable
  module Steps
    # A step that calls an instance method on the action (decision D3,
    # triggered by a Symbol/String step argument).
    class Method < Base
      # @param name [Symbol, String] the instance method to call; normalized
      #   to a Symbol
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+)
      def initialize(name, **options)
        super(name.to_sym, **options)
      end

      # Invoke the named method on the instance.
      #
      # @param instance [Object] the action instance
      # @return [Object] the method's return value
      def call(instance)
        instance.public_send(name)
      end
    end
  end
end
