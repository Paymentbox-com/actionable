# frozen_string_literal: true

module Actionable
  # Executes an action instance's steps and produces the {Result}.
  #
  # The main loop runs inside {Actionable.catch_halt}, so a halting step
  # (+throw Actionable::HALT+) unwinds out of the loop without running the
  # remaining steps. Genuine exceptions are not caught — they propagate to the
  # caller (decision D4). When no step recorded a result, the run auto-succeeds.
  class Runner
    # @param instance [Action] the action instance to run
    def initialize(instance)
      @instance = instance
    end

    # Run the action's steps and return its result.
    #
    # @return [Result] the recorded result, or a fresh {Success} if none was set
    def run
      Actionable.catch_halt { run_steps }
      @instance.result || Success.new
    end

    private

    # Run each declared step in order, skipping any whose guard opts out.
    #
    # @return [void]
    def run_steps
      @instance.class.steps.each do |step|
        next if step.skip?(@instance)

        step.call(@instance)
      end
    end
  end
end
