# frozen_string_literal: true

require_relative '../../../actionable'

module Actionable
  # Outcome coverage for a test suite (decision D22). While enabled, every real
  # +.run+ of a named action class is recorded as +[class name, outcome, code]+,
  # where outcome is +:success+, +:failure+ or +:skipped+. At the end of the
  # suite those observations are compared with the outcomes each action can
  # end with (its declarations, read at run time), and the outcomes no spec
  # reached are reported.
  #
  # Loaded by +require 'actionable/rspec/coverage'+, which also installs the
  # suite hook. Nothing here is loaded by the core.
  module Coverage
    # Prepended onto {Actionable::Action}'s singleton class, so every
    # subclass's +.run+ (nested {Steps::Action} runs and {Action.run_each}
    # included) passes through it. An RSpec stub of +.run+ defines the method
    # on the subclass itself, ahead of this module, so a stubbed run is never
    # recorded as the action being tested.
    module Recorder
      # Run the action and record the result's outcome.
      #
      # @return [Result]
      def run(*, **)
        result = super
        Coverage.record(self, result)
        result
      end
    end

    @mutex = Mutex.new
    @observed = Set.new
    @stubbed = Set.new
    @enabled = false

    class << self
      # Start recording runs. Installs {Recorder} the first time; safe to call
      # again.
      #
      # @return [void]
      def enable!
        singleton = Actionable::Action.singleton_class
        singleton.prepend(Recorder) unless singleton.ancestors.include?(Recorder)
        @enabled = true
      end

      # Stop recording runs. {Recorder} stays installed but records nothing.
      #
      # @return [void]
      def disable!
        @enabled = false
      end

      # @return [Boolean] whether runs are being recorded
      def enabled?
        @enabled
      end

      # Record one real run. Ignores anonymous classes and anything that isn't
      # a {Result}.
      #
      # @param action_class [Class<Actionable::Action>]
      # @param result [Result]
      # @return [void]
      def record(action_class, result)
        observation = observation_for(action_class, result)
        @mutex.synchronize { @observed << observation } if observation
      end

      # Record one run answered by the gem's stub helpers
      # (+allow_actionable_success+ and the rest). Kept apart from {.observed}:
      # a stubbed outcome was never produced by the action, so it never counts
      # as tested, but the report shows it.
      #
      # @param action_class [Class<Actionable::Action>]
      # @param result [Result]
      # @return [void]
      def record_stub(action_class, result)
        observation = observation_for(action_class, result)
        @mutex.synchronize { @stubbed << observation } if observation
      end

      # The runs answered by a gem stub helper so far, deduplicated.
      #
      # @return [Set<Array(String, Symbol, Symbol)>] +[class name, outcome, code]+
      def stubbed
        @mutex.synchronize { @stubbed.dup }
      end

      # The real runs recorded so far, deduplicated.
      #
      # @return [Set<Array(String, Symbol, Symbol)>] +[class name, outcome, code]+
      def observed
        @mutex.synchronize { @observed.dup }
      end

      # Forget every recorded run, real and stubbed.
      #
      # @return [void]
      def reset!
        @mutex.synchronize do
          @observed.clear
          @stubbed.clear
        end
      end

      private

      # @return [Array(String, Symbol, Symbol), nil]
      def observation_for(action_class, result)
        return unless enabled? && result.is_a?(Actionable::Result)

        name = action_class.name
        return if name.nil?

        [name, outcome_of(result), result.code.to_sym]
      end

      # @param result [Result]
      # @return [Symbol] +:success+, +:failure+ or +:skipped+
      def outcome_of(result)
        if result.failure? then :failure
        elsif result.skipped? then :skipped
        else :success
        end
      end
    end
  end
end
