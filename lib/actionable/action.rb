# frozen_string_literal: true

module Actionable
  # Base class for service objects. Subclass it, declare an ordered list of
  # steps with {.step}, implement each step as an instance method, and run it
  # with {.run} (decisions D1/D2).
  #
  #   class Greet < Actionable::Action
  #     step :build_message
  #     def build_message = @message = 'hello'
  #   end
  #
  #   Greet.run # => #<Actionable::Success ...>
  class Action
    class << self
      # The ordered, deduplicated set of steps declared on this action.
      # A {Set} keyed by step identity ([type, name]) so a redeclared step
      # collapses to one entry; insertion order is preserved (decision D2).
      #
      # @return [Set<Steps::Base>]
      def steps
        @steps ||= Set.new
      end

      # Declare the action's typed output schema, or read it back.
      #
      # With a block, builds an anonymous +FieldStruct::Base+ subclass from the
      # FieldStruct DSL (+required+/+optional+/…) and stores it as this action's
      # output schema (decision D6). At the end of a run the {Runner} captures
      # the instance variables whose names match declared fields, coerces them
      # through the schema, and assigns the struct to +result.output+.
      #
      #   output do
      #     required :invoice, Invoice
      #     optional :receipt, Receipt
      #   end
      #
      # @yield the FieldStruct field declarations
      # @return [Class<FieldStruct::Base>, nil] the output schema, or +nil+ when
      #   none has been declared (the free-form path)
      def output(&block)
        return @output_schema unless block

        @output_schema = Class.new(FieldStruct::Base, &block)
      end

      # @return [Class<FieldStruct::Base>, nil] the declared output schema, or
      #   +nil+ for a free-form action
      attr_reader :output_schema

      # Declare a step. The step type is inferred from +target+ (a Symbol or
      # String names an instance method — a {Steps::Method}).
      #
      # @param target [Symbol, String] the step target
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+)
      # @return [Set<Steps::Base>] the updated step set
      def step(target, **)
        steps << Steps.build(target, **)
      end

      # Lifecycle hooks that run after the main steps when the run succeeds.
      # @return [Set<Steps::Base>]
      def success_hooks
        @success_hooks ||= Set.new
      end

      # Lifecycle hooks that run after the main steps when the run fails.
      # @return [Set<Steps::Base>]
      def failure_hooks
        @failure_hooks ||= Set.new
      end

      # Lifecycle hooks that run after the main steps regardless of outcome.
      # @return [Set<Steps::Base>]
      def always_hooks
        @always_hooks ||= Set.new
      end

      # Declare a hook that runs at the end of a run iff it succeeded (D2).
      # @param target [Symbol, String] the instance method to run
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+)
      # @return [Set<Steps::Base>]
      def on_success(target, **)
        success_hooks << Steps.build(target, **)
      end

      # Declare a hook that runs at the end of a run iff it failed (D2).
      # @param target [Symbol, String] the instance method to run
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+)
      # @return [Set<Steps::Base>]
      def on_failure(target, **)
        failure_hooks << Steps.build(target, **)
      end

      # Declare a hook that runs at the end of a run regardless of outcome (D2).
      # @param target [Symbol, String] the instance method to run
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+)
      # @return [Set<Steps::Base>]
      def always(target, **)
        always_hooks << Steps.build(target, **)
      end

      # Declare a branching step (decision D3). The switch value is read from
      # +value_source+ (an instance method); the block declares branches with
      # +on(value, target)+ and an optional +default(target)+.
      #
      #   case_step :status do
      #     on 'active', :handle_active
      #     default :handle_unknown
      #   end
      #
      # @param value_source [Symbol, String] the method whose value is switched on
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+)
      # @yield the branch declarations
      # @return [Set<Steps::Base>] the updated step set
      def case_step(value_source, **, &)
        steps << Steps::Case.define(value_source, **, &)
      end

      # Enable or read the action's measurement mode (decision D10). +:all+
      # records an execution {History}; +:none+ (the default) records nothing
      # for zero overhead. A measuring run cascades into the nested actions it
      # invokes regardless of their own setting.
      #
      # @param mode [:all, :none, nil] the mode to set; omit to read
      # @return [:all, :none] the resolved mode
      def measure(mode = nil)
        unless mode.nil?
          raise ArgumentError, "unknown measure mode #{mode.inspect}" unless %i[all none].include?(mode)

          @measure = mode
        end
        @measure ||= :none
      end

      # @return [Boolean] whether this action records history
      def measure_all?
        measure == :all
      end

      # Instantiate the action with the given arguments and run it.
      #
      # @return [Result] the run's {Success} or {Failure}
      def run(...)
        Runner.new(new(...)).run
      end

      # Give each subclass its own copy of the inherited step set, so adding
      # steps to a subclass never mutates the parent's (decision D2).
      #
      # @param subclass [Class]
      # @return [void]
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@steps, steps.dup)
        subclass.instance_variable_set(:@output_schema, output_schema)
        subclass.instance_variable_set(:@success_hooks, success_hooks.dup)
        subclass.instance_variable_set(:@failure_hooks, failure_hooks.dup)
        subclass.instance_variable_set(:@always_hooks, always_hooks.dup)
        subclass.instance_variable_set(:@measure, measure)
      end
    end

    # Default free-form constructor: accept and ignore any arguments, so an
    # action with no declared input still runs via {.run}. Subclasses override
    # this to capture their inputs (decision D7; typed input lands in a later
    # slice).
    def initialize(*_args, **_kwargs)
    end

    # The result recorded during the run, if any. The control-flow methods
    # (+fail+/+succeed+/+fail!+/+succeed!+) write here; +nil+ means "no explicit
    # result", which the {Runner} turns into an auto-{Success}.
    #
    # @return [Result, nil]
    attr_reader :result

    private

    # Record a {Failure} as the run's result without halting — later steps
    # still run, and the final result reflects the most recent record (decision
    # D4, "last write wins").
    #
    # @param code [Symbol] the error code
    # @param message [String, nil] human-readable description
    # @param errors [Hash{Symbol=>String, Array<String>}] field => message(s)
    #   added to the result's errors collection
    # @return [false] so a step can branch on the call
    def fail(code, message = nil, **errors)
      failure = Failure.new(code: code, message: message)
      errors.each { |field, messages| Array(messages).each { |m| failure.errors.add(field, m) } }
      @result = failure
      false
    end

    # Record a {Success} as the run's result without halting (decision D4).
    #
    # @param message [String, nil] human-readable description
    # @param output [Hash{Symbol=>Object}] the success output payload
    # @return [true] so a step can branch on the call
    def succeed(message = nil, **output)
      @result = Success.new(message: message, output: output)
      true
    end

    # Record a {Failure} and halt the run, skipping the remaining steps
    # (decision D4).
    #
    # @param code [Symbol] the error code
    # @param message [String, nil] human-readable description
    # @param errors [Hash{Symbol=>String, Array<String>}] field => message(s)
    # @raise [UncaughtThrowError] never escapes the {Runner}'s halt catch
    # @return [void]
    def fail!(code, message = nil, **errors)
      fail(code, message, **errors)
      halt!
    end

    # Record a {Success} and halt the run, skipping the remaining steps
    # (decision D4).
    #
    # @param message [String, nil] human-readable description
    # @param output [Hash{Symbol=>Object}] the success output payload
    # @return [void]
    def succeed!(message = nil, **output)
      succeed(message, **output)
      halt!
    end

    # Halt the run immediately, keeping whatever result was already recorded
    # (a prior +fail+/+succeed+, or auto-{Success} if none). Control flow only —
    # not an exception (decision D4).
    #
    # @return [void]
    def halt!
      throw HALT
    end
  end
end
