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
    #
    # A stubbed failure of an action that declares failures with
    # {Actionable::Action.fails} carries the declared metadata (and message,
    # when none is given) for its code, and a code the action doesn't declare
    # raises +ArgumentError+, so a stub can't return what the action never
    # could (decision D20).
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
      # @raise [ArgumentError] when the action declares failures but not the code
      def allow_actionable_failure(action_class, **opts)
        allow_run(action_class, declared_failure_result(action_class, **opts))
      end

      # @return [Failure] the stubbed result
      # @raise [ArgumentError] when the action declares failures but not the code
      def stub_actionable_failure(action_class, **opts)
        expect_run(action_class, declared_failure_result(action_class, **opts))
      end

      # @return [Skipped] the stubbed result
      def allow_actionable_skip(action_class, **opts)
        allow_run(action_class, actionable_skip_result(**opts))
      end

      # @return [Skipped] the stubbed result
      def stub_actionable_skip(action_class, **opts)
        expect_run(action_class, actionable_skip_result(**opts))
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
      # @param metadata [Hash{Symbol=>Object}] the failure's per-code metadata
      # @return [Failure]
      def actionable_failure_result(code: :error, message: nil, output: {}, errors: {}, metadata: {})
        failure = Actionable::Failure.new(code: code, message: message, output: output, metadata: metadata)
        apply_errors(failure, errors)
      end

      # Build a real {Skipped} from a hash (no stubbing).
      #
      # @param code [Symbol]
      # @param message [String, nil]
      # @param output [Hash]
      # @return [Skipped]
      def actionable_skip_result(code: :skipped, message: nil, output: {})
        Actionable::Skipped.new(code: code, message: message, output: output)
      end

      private

      # A {Failure} for +action_class+: the declared metadata and message for
      # its code, or a refusal when the action declares failures but not it.
      def declared_failure_result(action_class, code: :error, **opts)
        unless action_class.allows_failure_code?(code)
          raise ArgumentError, Actionable::RSpec.undeclared_code_message(action_class, code)
        end

        declaration = action_class.failure_declarations.fetch(code.to_sym, {message: nil, metadata: {}})
        opts[:message] ||= declaration[:message]
        actionable_failure_result(code: code, metadata: declaration[:metadata], **opts)
      end

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
