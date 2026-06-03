# frozen_string_literal: true

module Actionable
  # Namespace for the concrete step types an action's pipeline is built from
  # (decision D3): {Steps::Method} now, {Steps::Action} and {Steps::Case} later.
  module Steps
    # Shared behavior for every step: a +name+, an +options+ hash, value
    # identity for Set deduplication (keyed by +[type, name]+, decision D2),
    # and the +:if+ / +:unless+ skip logic. Subclasses implement {#call}.
    #
    # @abstract Subclass and implement {#call}.
    class Base
      # @return [Object] the step's name — a Symbol for a {Steps::Method},
      #   an action Class for a {Steps::Action}
      attr_reader :name

      # @return [Hash{Symbol=>Object}] the declared step options (e.g. +:if+,
      #   +:unless+, and step-type-specific keys)
      attr_reader :options

      # @param name [Object] the step name (see {#name})
      # @param options [Hash{Symbol=>Object}] step options
      def initialize(name, **options)
        @name = name
        @options = options
      end

      # Run the step against an action instance.
      #
      # @param _instance [Object] the action instance the step runs against
      # @raise [NotImplementedError] always — concrete step types override this
      # @return [void]
      def call(_instance)
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      # Whether this step should be skipped for the given instance, per its
      # +:if+ / +:unless+ guards. A guard is a Symbol naming a (possibly
      # private) instance method, or a callable invoked with the instance.
      # When both guards are present, either one asking to skip wins.
      #
      # @param instance [Object] the action instance to evaluate guards against
      # @return [Boolean]
      def skip?(instance)
        return true if options.key?(:if) && !evaluate_guard(options[:if], instance)
        return true if options.key?(:unless) && evaluate_guard(options[:unless], instance)

        false
      end

      # Value identity: same concrete class AND same name. This keys steps in
      # the per-action Set so a redeclared step dedups (decision D2).
      #
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.instance_of?(self.class) && name == other.name
      end
      alias eql? ==

      # @return [Integer] consistent with {#==}, so steps work as Set members
      def hash
        [self.class, name].hash
      end

      private

      # Resolve a guard against the instance. A Symbol/String names an instance
      # method (called via +__send__+, so private predicates work); anything
      # else is treated as a callable receiving the instance.
      #
      # @param guard [Symbol, String, #call]
      # @param instance [Object]
      # @return [Boolean]
      def evaluate_guard(guard, instance)
        case guard
        when Symbol, String then instance.__send__(guard)
        else guard.call(instance)
        end
      end
    end
  end
end
