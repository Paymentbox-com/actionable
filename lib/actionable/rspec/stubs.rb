# frozen_string_literal: true

module Actionable
  module RSpec
    # Helpers mixed into example groups by +actionable/rspec+ that stub an
    # action's +.run+ to return a real {Success} / {Failure} built from a hash,
    # so callers can assert on +result.code+/+output+/+errors+ without executing
    # the action (decision D12).
    #
    # +allow_*+ permits the call (a stub); +stub_*+ also sets a call expectation
    # (a mock, verified on the example) — mirroring RSpec's allow/expect split.
    module Stubs
      # @return [Success] the stubbed result
      def allow_actionable_success(action_class, **opts)
        allow_run(action_class, actionable_success_result(**opts))
      end

      # @return [Success] the stubbed result
      def stub_actionable_success(action_class, **opts)
        expect_run(action_class, actionable_success_result(**opts))
      end

      # @return [Failure] the stubbed result
      def allow_actionable_failure(action_class, **opts)
        allow_run(action_class, actionable_failure_result(**opts))
      end

      # @return [Failure] the stubbed result
      def stub_actionable_failure(action_class, **opts)
        expect_run(action_class, actionable_failure_result(**opts))
      end

      # Build a real {Success} from a hash (no stubbing).
      #
      # @param message [String, nil]
      # @param output [Hash]
      # @param errors [Hash{Symbol=>String, Array<String>}]
      # @return [Success]
      def actionable_success_result(message: nil, output: {}, errors: {})
        apply_errors(Actionable::Success.new(message: message, output: output), errors)
      end

      # Build a real {Failure} from a hash (no stubbing).
      #
      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash]
      # @param errors [Hash{Symbol=>String, Array<String>}]
      # @return [Failure]
      def actionable_failure_result(code: :error, message: nil, output: {}, errors: {})
        apply_errors(Actionable::Failure.new(code: code, message: message, output: output), errors)
      end

      private

      def allow_run(action_class, result)
        allow(action_class).to receive(:run).and_return(result)
        result
      end

      def expect_run(action_class, result)
        expect(action_class).to receive(:run).and_return(result)
        result
      end

      def apply_errors(result, errors)
        errors.each { |field, messages| Array(messages).each { |message| result.errors.add(field, message) } }
        result
      end
    end
  end
end
