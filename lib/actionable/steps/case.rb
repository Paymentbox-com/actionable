# frozen_string_literal: true

module Actionable
  module Steps
    # A step that branches to one of several targets based on a value
    # (decision D3, declared with +case_step+). The switch value is read from
    # the action via the named method; each branch's target is an ordinary step
    # (a method or a nested action), so branches compose like any other step.
    #
    #   case_step :status do
    #     on 'active',          :handle_active
    #     on %w[trial grace],   :handle_trial      # Array membership
    #     on(/\A4\d\d\z/,       :handle_client_err # Regexp
    #     default               :handle_unknown
    #   end
    class Case < Base
      # Collects +on+/+default+ branch declarations inside a +case_step+ block.
      class Builder
        # @return [Array<Array(Object, Steps::Base)>] ordered [match, step] pairs
        attr_reader :branches
        # @return [Steps::Base, nil] the fallback step, if +default+ was declared
        attr_reader :default_step

        def initialize
          @branches = []
          @default_step = nil
        end

        # Register a branch. +value+ matches the switch value by +==+, by
        # +Regexp#match?+ when it is a Regexp, or by membership when it is an
        # Array. +target+ is any step target (method name or nested action).
        #
        # @param value [Object, Regexp, Array]
        # @param target [Symbol, String, Class<Actionable::Action>]
        # @param options [Hash{Symbol=>Object}] step options for the target
        # @return [void]
        def on(value, target, **options)
          @branches << [value, Steps.build(target, **options)]
        end

        # Register the fallback branch, run when no +on+ branch matches.
        #
        # @param target [Symbol, String, Class<Actionable::Action>]
        # @param options [Hash{Symbol=>Object}] step options for the target
        # @return [void]
        def default(target, **options)
          @default_step = Steps.build(target, **options)
        end
      end

      # Build a case step from a +case_step+ declaration.
      #
      # @param value_source [Symbol, String] the method whose value is switched on
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+)
      # @yield the branch declarations (+on+ / +default+)
      # @return [Case]
      def self.define(value_source, **options, &block)
        builder = Builder.new
        builder.instance_eval(&block)
        new(value_source, builder.branches, builder.default_step, **options)
      end

      # @param value_source [Symbol, String] the method whose value is switched on
      # @param branches [Array<Array(Object, Steps::Base)>] ordered [match, step] pairs
      # @param default_step [Steps::Base, nil] the fallback step
      # @param options [Hash{Symbol=>Object}] step options
      def initialize(value_source, branches, default_step, **options)
        super(value_source, **options)
        @branches = branches
        @default_step = default_step
      end

      # Evaluate the switch value and run the first matching branch (or the
      # default). No-op when nothing matches and no default was declared.
      #
      # @param instance [Actionable::Action]
      # @return [void]
      def call(instance)
        value = instance.public_send(name)
        step = match(value) || @default_step
        step&.call(instance)
      end

      # @return [Array<Symbol>] the switch-value method plus every branch
      #   target's required methods
      def required_methods
        branch_steps = @branches.map(&:last)
        branch_steps << @default_step if @default_step
        ([name] + branch_steps.flat_map(&:required_methods)).uniq
      end

      # @return [Symbol]
      def kind
        :case
      end

      private

      # @param value [Object] the switch value
      # @return [Steps::Base, nil] the first matching branch's step
      def match(value)
        @branches.each { |branch_value, step| return step if matches?(branch_value, value) }
        nil
      end

      # @param branch_value [Object, Regexp, Array]
      # @param value [Object]
      # @return [Boolean]
      def matches?(branch_value, value)
        case branch_value
        when Array then branch_value.include?(value)
        when Regexp then branch_value.match?(value.to_s)
        else branch_value == value
        end
      end
    end
  end
end
