# frozen_string_literal: true

require 'time'

module Actionable
  # An ordered record of the steps a run executed, when measurement is enabled
  # (decision D10). Each entry is a {History::Step}; nested action steps carry
  # their child's +History+.
  class History
    # One recorded step: which section it ran in, its name, when it started, how
    # long it took, the result code it produced (if any), and — for action
    # steps — the nested child {History}.
    class Step
      # @return [Symbol] +:main+, +:success+, +:failure+, or +:always+
      attr_reader :section
      # @return [Symbol, String, Class] the step's name
      attr_reader :name
      # @return [Time] wall-clock start time
      attr_reader :started_at
      # @return [Float] elapsed seconds (monotonic)
      attr_accessor :duration
      # @return [Symbol, nil] the result code this step recorded, if it set one
      attr_accessor :code
      # @return [History, nil] the nested action's history, for action steps
      attr_accessor :nested

      # @param section [Symbol]
      # @param name [Symbol, String, Class]
      # @param started_at [Time]
      def initialize(section:, name:, started_at:)
        @section = section
        @name = name
        @started_at = started_at
        @duration = 0.0
        @code = nil
        @nested = nil
      end

      # @return [Hash{Symbol=>Object}] a JSON-ready hash (nested history recurses)
      def as_json(*)
        {
          section: section,
          name: name.is_a?(Class) ? name.name : name,
          started_at: started_at.iso8601(6),
          duration: duration,
          code: code,
          history: nested&.as_json
        }
      end
    end

    # @return [Array<Step>] the recorded steps, in execution order
    attr_reader :steps

    def initialize
      @steps = []
    end

    # Append a recorded step.
    #
    # @param step [Step]
    # @return [self]
    def <<(step)
      @steps << step
      self
    end

    # @return [Boolean] whether any step has been recorded
    def empty?
      @steps.empty?
    end

    # @return [Float] the summed duration of every recorded step
    def took
      @steps.sum(&:duration)
    end

    # @return [Array<Hash>] each step as a JSON-ready hash
    def as_json(*)
      @steps.map(&:as_json)
    end

    # @return [String] the history serialized to JSON via Oj (decision D15).
    #   +:compat+ mode emits plain JSON (string keys, symbols as strings) rather
    #   than Oj's default object-marker encoding.
    def to_json(*)
      Oj.dump(as_json, mode: :compat)
    end
  end
end
