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
    # @return [Array<Symbol>]
    DEFAULT_PERMANENT_CODES = %i[invalid_input invalid_output not_found].freeze

    # Raised by {Mixin#run_actionable} for a retryable failure, so the host
    # queue (Sidekiq / ActiveJob) sees a raised error and applies its retry
    # policy. Carries the offending result.
    class RetryableFailure < StandardError
      # @return [Result] the failed result that triggered the retry
      attr_reader :result

      # @param result [Result] a {Failure}, or a {Skipped} retried because its
      #   metadata says +retry: true+ (see {RetryMetadata#honor_retry_metadata})
      def initialize(result)
        @result = result
        verb = result.skipped? ? 'skipped' : 'failed'
        super("actionable run #{verb} with retryable code #{result.code.inspect}")
      end
    end

    # The +honor_retry_metadata+ class macro (owner ruling P10). Extended onto
    # {Actionable::Action} by +actionable/job+, so an action can opt in to having
    # {Mixin#run_actionable} act on the +retry:+ metadata of its declared codes.
    # Metadata stays neutral by default (decisions D20/D21).
    module RetryMetadata
      # Opt this action in (or, with +enabled: false+, back out) to {Job}
      # honoring the +retry:+ metadata of its declared failures and skips:
      # +retry: true+ retries the job, +retry: false+ does not. A code with no
      # +retry:+ key keeps the default mapping. Inherited; a subclass can turn
      # it off.
      #
      #   class Reindex < Actionable::Action
      #     honor_retry_metadata
      #     skips :not_ready, retry: true # the job retries until the index is ready
      #   end
      #
      # @param enabled [Boolean]
      # @return [void]
      def honor_retry_metadata(enabled: true)
        @honor_retry_metadata = enabled
      end

      # Whether {Job} honors this action's +retry:+ metadata, inherited from
      # ancestors when not set locally. +false+ unless an ancestor opted in.
      #
      # @return [Boolean]
      def honor_retry_metadata?
        return @honor_retry_metadata if defined?(@honor_retry_metadata)
        return superclass.honor_retry_metadata? if superclass.respond_to?(:honor_retry_metadata?)

        false
      end
    end

    module_function

    # Map a result to a queue disposition.
    #
    # With +honor_retry: true+, a failure or skip whose metadata has a +retry:+
    # key is decided by it instead: truthy is +:retry+, falsy is +:discard+ for
    # a failure and +:ack+ for a skip. Results without the key, and successes,
    # map as usual.
    #
    # @param result [Result] the action's result
    # @param permanent [Array<Symbol>] failure codes treated as non-retryable
    # @param honor_retry [Boolean] act on the result's +retry:+ metadata
    # @return [:ack, :retry, :discard] +:ack+ for a success or skip; +:discard+
    #   for a failure whose code is +permanent+; +:retry+ for any other failure
    def disposition(result, permanent: DEFAULT_PERMANENT_CODES, honor_retry: false)
      return metadata_disposition(result) if honor_retry && retry_declared?(result)
      return :ack if result.ok?

      permanent.include?(result.code) ? :discard : :retry
    end

    # @param result [Result]
    # @return [Boolean] whether the result carries +retry:+ metadata
    def retry_declared?(result)
      !result.success? && result.metadata.key?(:retry)
    end
    private_class_method :retry_declared?

    # @param result [Failure, Skipped] a result whose metadata has +retry:+
    # @return [:ack, :retry, :discard]
    def metadata_disposition(result)
      return :retry if result.metadata[:retry]

      result.failure? ? :discard : :ack
    end
    private_class_method :metadata_disposition

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
      # When the action opted in with +honor_retry_metadata+, its declared
      # +retry:+ metadata decides (see {Job.disposition}).
      #
      # @param action_class [Class<Actionable::Action>]
      # @param args [Object] positional arguments, forwarded to +.run+
      # @param kwargs [Object] keyword arguments, forwarded to +.run+
      # @return [Result] the run's result (for an ack/discard outcome)
      # @raise [RetryableFailure] when the failure should be retried
      def run_actionable(action_class, *args, **kwargs)
        @actionable_result = action_class.run(*args, **kwargs)
        disposition = Actionable::Job.disposition(
          @actionable_result,
          permanent: actionable_permanent_codes,
          honor_retry: action_class.respond_to?(:honor_retry_metadata?) && action_class.honor_retry_metadata?
        )
        raise RetryableFailure, @actionable_result if disposition == :retry

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

# Wire the adapter into the core: the honor_retry_metadata macro onto Action.
Actionable::Action.extend(Actionable::Job::RetryMetadata)
