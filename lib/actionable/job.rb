# frozen_string_literal: true

# Optional background-job integration (decision D19). Load it explicitly with
# `require 'actionable/job'`. Framework-agnostic and pure Ruby — it maps an
# action {Actionable::Result} to a queue *disposition* and provides a {Mixin}
# you include into a Sidekiq worker or ActiveJob job. Never loaded by the core
# entry point.
require_relative '../actionable' # ensure the core is loaded (self-contained entry)

module Actionable
  # Runs an action inside a background job and maps its result to a queue
  # disposition: a success or skip is done (+:ack+); a failure either retries
  # (transient) or is discarded (permanent). Genuine exceptions are never
  # swallowed — they propagate so the queue's own retry/backoff handles them
  # (invariant 2).
  module Job
    # Failure codes that should NOT be retried — a re-run can't fix bad input or
    # a missing record, so the job is discarded rather than retried. Override
    # per job via {Mixin#actionable_permanent_codes}.
    DEFAULT_PERMANENT_CODES = %i[invalid_input invalid_output not_found].freeze

    # Raised by {Mixin#run_actionable} for a retryable failure, so the host
    # queue (Sidekiq / ActiveJob) sees a raised error and applies its retry
    # policy. Carries the offending result.
    class RetryableFailure < StandardError
      # @return [Result] the failed result that triggered the retry
      attr_reader :result

      # @param result [Result]
      def initialize(result)
        @result = result
        super("actionable run failed with retryable code #{result.code.inspect}")
      end
    end

    module_function

    # Map a result to a queue disposition.
    #
    # @param result [Result] the action's result
    # @param permanent [Array<Symbol>] failure codes treated as non-retryable
    # @return [:ack, :retry, :discard] +:ack+ for a success or skip; +:discard+
    #   for a failure whose code is +permanent+; +:retry+ for any other failure
    def disposition(result, permanent: DEFAULT_PERMANENT_CODES)
      return :ack if result.ok?

      permanent.include?(result.code) ? :discard : :retry
    end

    # Mix into a Sidekiq worker or ActiveJob job. Call {#run_actionable} from
    # +perform+; it runs the action, records the result on {#actionable_result},
    # and raises {RetryableFailure} for a retryable failure (so the queue
    # retries) — returning normally for +:ack+ and +:discard+.
    #
    #   class ProjectEventJob
    #     include Sidekiq::Job
    #     include Actionable::Job::Mixin
    #     def perform(event_id) = run_actionable(ProjectApiEvent, event_id: event_id)
    #   end
    module Mixin
      # @return [Result, nil] the result of the most recent {#run_actionable}
      attr_reader :actionable_result

      # Run +action_class+ with the given arguments, map the outcome, and either
      # return the result (+:ack+ / +:discard+) or raise {RetryableFailure}
      # (+:retry+). A genuine exception inside the action propagates unchanged.
      #
      # @param action_class [Class<Actionable::Action>]
      # @return [Result] the run's result (for an ack/discard outcome)
      # @raise [RetryableFailure] when the failure should be retried
      def run_actionable(action_class, *args, **kwargs)
        @actionable_result = action_class.run(*args, **kwargs)
        if Actionable::Job.disposition(@actionable_result, permanent: actionable_permanent_codes) == :retry
          raise RetryableFailure, @actionable_result
        end

        @actionable_result
      end

      # @return [Array<Symbol>] failure codes this job treats as non-retryable;
      #   override to customize. Defaults to {DEFAULT_PERMANENT_CODES}.
      def actionable_permanent_codes
        DEFAULT_PERMANENT_CODES
      end
    end
  end
end
