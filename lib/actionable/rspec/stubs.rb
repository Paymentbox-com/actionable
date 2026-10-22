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
    # could (decision D20). A stubbed skip follows {Actionable::Action.skips}
    # the same way (decision D21), the default +:skipped+ included.
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
      # @raise [ArgumentError] when the action declares skips but not the code
      def allow_actionable_skip(action_class, **opts)
        allow_run(action_class, declared_skip_result(action_class, **opts))
      end

      # @return [Skipped] the stubbed result
      # @raise [ArgumentError] when the action declares skips but not the code
      def stub_actionable_skip(action_class, **opts)
        expect_run(action_class, declared_skip_result(action_class, **opts))
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
      # @param metadata [Hash{Symbol=>Object}] the skip's per-code metadata
      # @return [Skipped]
      def actionable_skip_result(code: :skipped, message: nil, output: {}, metadata: {})
        Actionable::Skipped.new(code: code, message: message, output: output, metadata: metadata)
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

      # A {Skipped} for +action_class+: the declared metadata and message for
      # its code, or a refusal when the action declares skips but not it.
      def declared_skip_result(action_class, code: :skipped, **opts)
        unless action_class.allows_skip_code?(code)
          raise ArgumentError, Actionable::RSpec.undeclared_code_message(action_class, code, outcome: :skip)
        end

        declaration = action_class.skip_declarations.fetch(code.to_sym, {message: nil, metadata: {}})
        opts[:message] ||= declaration[:message]
        actionable_skip_result(code: code, metadata: declaration[:metadata], **opts)
      end

      def allow_run(action_class, result)
        result = as_action_result(action_class, result)
        allow(action_class).to receive(:run) { stubbed_run(action_class, result) }
        result
      end

      def expect_run(action_class, result)
        result = as_action_result(action_class, result)
        expect(action_class).to receive(:run) { stubbed_run(action_class, result) }
        result
      end

      # The stubbed result as a real run would return it (decision D23): its
      # output shaped by the schema it is held to, then as the action's own
      # result class when it has typed outcomes.
      def as_action_result(action_class, result)
        shape_output(action_class, result)
        action_class.__send__(:typed_result, result)
      end

      # Mirror the runner: output for a code with a schema becomes that schema
      # (refused when it breaks it, since a real run would end as
      # +invalid_output+ instead), and under typed outcomes a code without one
      # carries an empty output (refused when output is given, as a real run
      # refuses it). The gem's own failure codes keep what they are given.
      def shape_output(action_class, result)
        schema = stubbed_output_schema(action_class, result)
        return result.output = build_stubbed_output(action_class, result, schema) if schema
        return unless action_class.typed_outcomes? && !result.success?
        return if result.failure? && Actionable::Action::GEM_FAILURE_CODES.include?(result.code)

        unless result.output.respond_to?(:empty?) && result.output.empty?
          raise ArgumentError, "#{action_class.name || "action"} output for #{result.code.inspect}, which declares no " \
                               'output schema; a real run refuses it'
        end
        result.output = {}
      end

      # @return [Class<FieldStruct::Base>, nil] the schema the result's output
      #   is held to: its code's, or the success schema under typed outcomes
      def stubbed_output_schema(action_class, result)
        return action_class.skip_output_schema(result.code) if result.skipped?
        return action_class.failure_output_schema(result.code) if result.failure?

        action_class.output_schema if action_class.typed_outcomes?
      end

      def build_stubbed_output(action_class, result, schema)
        given = result.output.is_a?(FieldStruct::Base) ? result.output.attributes : result.output.to_h
        given = given.slice(*schema.attribute_names)
        # A parent absorbs only the fields a run set, so a stub sets the ones it was given.
        result.output_fields_set = given.keys
        output = schema.new(**given)
        return output if output.valid?

        raise ArgumentError, "#{action_class.name || "action"} output for #{result.code.inspect} breaks its schema " \
                             "(#{output.errors.full_messages.join(", ")}); a real run would end as invalid_output"
      end

      # The stub's response: +result+, noted as a stubbed run when outcome
      # coverage is loaded (decision D22), so a report can tell an outcome
      # only ever stubbed from one never reached at all.
      def stubbed_run(action_class, result)
        Actionable::Coverage.record_stub(action_class, result) if defined?(Actionable::Coverage)
        result
      end

      def apply_errors(result, errors)
        errors.each { |field, messages| Array(messages).each { |message| result.errors.add(field, message) } }
        result
      end
    end
  end
end
