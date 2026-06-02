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

      # Declare a step. The step type is inferred from +target+ (a Symbol or
      # String names an instance method — a {Steps::Method}).
      #
      # @param target [Symbol, String] the step target
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+)
      # @return [Set<Steps::Base>] the updated step set
      def step(target, **)
        steps << Steps.build(target, **)
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
      end
    end

    # Default free-form constructor: accept and ignore any arguments, so an
    # action with no declared input still runs via {.run}. Subclasses override
    # this to capture their inputs (decision D7; typed input lands in a later
    # slice).
    def initialize(*_args, **_kwargs)
    end

    # The result recorded during the run, if any. The control-flow methods
    # (+fail+/+succeed+/…, a later slice) write here; +nil+ means "no explicit
    # result", which the {Runner} turns into an auto-{Success}.
    #
    # @return [Result, nil]
    attr_reader :result
  end
end
