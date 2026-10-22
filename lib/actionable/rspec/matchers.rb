# frozen_string_literal: true

module Actionable
  module RSpec
    # RSpec matcher methods mixed into example groups by +actionable/rspec+.
    module Matchers
      # Run an action and assert on its outcome.
      #
      #   expect(CreateInvoice).to perform_actionable(amount: 5).and_succeed
      #   expect(CreateInvoice).to perform_actionable(bad).and_fail(:invalid_input)
      #   expect(Boom).to          perform_actionable.and_raise(RuntimeError)
      #
      # @param args [Object] positional args forwarded to +.run+
      # @param kwargs [Object] keyword args forwarded to +.run+
      # @yieldparam result [Result, nil] the run's result (+nil+ when it raised)
      # @yieldparam exception [StandardError, nil] what the run raised, if anything
      # @yieldreturn [Object] truthy when the extra assertions hold
      # @return [PerformActionable]
      def perform_actionable(*args, **kwargs, &block)
        PerformActionable.new(args, kwargs, block)
      end
    end

    # The matcher object returned by {Matchers#perform_actionable}. Runs the
    # action under test and checks the configured outcome (decision D12). Bare
    # +perform_actionable+ expects a success; chain +and_succeed+ / +and_fail+ /
    # +and_raise+ to be explicit. Code and message expectations match with +===+,
    # so exact values, Regexps, and classes all work.
    class PerformActionable
      # Backtrace frames shown under +ACTIONABLE_SHORT_BACKTRACE+ when
      # +ACTIONABLE_BACKTRACE_QTY+ is unset.
      # @return [Integer]
      DEFAULT_BACKTRACE_QTY = 10

      # @param args [Array<Object>] positional args forwarded to +.run+
      # @param kwargs [Hash{Symbol=>Object}] keyword args forwarded to +.run+
      # @param block [Proc, nil] extra assertions, called with the result and exception
      def initialize(args, kwargs, block)
        @args = args
        @kwargs = kwargs
        @block = block
        @outcome = :success
      end

      # Expect a successful result, optionally matching +message+.
      # @param message [Object, nil] matched against the result's message with +===+
      # @yieldparam result [Result, nil]
      # @yieldparam exception [StandardError, nil]
      # @yieldreturn [Object] truthy when the extra assertions hold
      # @return [self]
      def and_succeed(message = nil, &block)
        configure(:success, message, &block)
      end

      # Expect a failed result, optionally matching +code+ and +message+. On an
      # action that declares failures, a Symbol +code+ it doesn't declare raises
      # +ArgumentError+ (decision D20).
      # @param code [Object, nil] matched against the result's code with +==+
      # @param message [Object, nil] matched against the result's message with +===+
      # @yieldparam result [Result, nil]
      # @yieldparam exception [StandardError, nil]
      # @yieldreturn [Object] truthy when the extra assertions hold
      # @return [self]
      def and_fail(code = nil, message = nil, &block)
        @expected_code = code
        configure(:failure, message, &block)
      end

      # Expect a skipped result, optionally matching the reason +code+ and
      # +message+ (decision D17). On an action that declares skips, a Symbol
      # +code+ it doesn't declare raises +ArgumentError+ (decision D21).
      # @param code [Object, nil] matched against the result's code with +==+
      # @param message [Object, nil] matched against the result's message with +===+
      # @yieldparam result [Result, nil]
      # @yieldparam exception [StandardError, nil]
      # @yieldreturn [Object] truthy when the extra assertions hold
      # @return [self]
      def and_skip(code = nil, message = nil, &block)
        @expected_code = code
        configure(:skip, message, &block)
      end

      # Expect the run to raise +error_class+, optionally matching +message+.
      # @param error_class [Class<Exception>]
      # @param message [Object, nil] matched against the exception's message with +===+
      # @yieldparam result [Result, nil]
      # @yieldparam exception [StandardError, nil]
      # @yieldreturn [Object] truthy when the extra assertions hold
      # @return [self]
      def and_raise(error_class = StandardError, message = nil, &block)
        @expected_error = error_class
        configure(:raise, message, &block)
      end

      # @param action_class [Class<Actionable::Action>]
      # @return [Boolean]
      def matches?(action_class)
        @action_class = action_class
        ensure_code_declared!
        perform
        primary_match? && block_match?
      end

      # @param action_class [Class<Actionable::Action>]
      # @return [Boolean]
      def does_not_match?(action_class)
        @action_class = action_class
        ensure_code_declared!
        perform
        !primary_match?
      end

      # @return [String]
      def failure_message
        "expected #{@action_class} to #{expectation_phrase}, but #{actual_phrase}"
      end

      # @return [String]
      def failure_message_when_negated
        "expected #{@action_class} not to #{expectation_phrase}, but it did"
      end

      # @return [String]
      def description
        "perform actionable and #{@outcome}"
      end

      private

      # @param outcome [Symbol] +:success+, +:failure+, +:skip+ or +:raise+
      # @param message [Object, nil]
      # @yieldparam result [Result, nil]
      # @yieldparam exception [StandardError, nil]
      # @yieldreturn [Object] truthy when the extra assertions hold
      # @return [self]
      def configure(outcome, message, &block)
        @outcome = outcome
        @expected_message = message
        @block = block if block
        self
      end

      # An +and_fail+ or +and_skip+ code the action could never end with is a
      # broken spec, not a failed expectation, so it raises rather than not
      # matching.
      #
      # @raise [ArgumentError] when the action declares the outcome's codes but not this one
      # @return [void]
      def ensure_code_declared!
        return unless @expected_code.is_a?(Symbol)

        check = {failure: :allows_failure_code?, skip: :allows_skip_code?}[@outcome]
        return unless check && @action_class.respond_to?(check)
        return if @action_class.public_send(check, @expected_code)

        raise ArgumentError,
          Actionable::RSpec.undeclared_code_message(@action_class, @expected_code, outcome: @outcome)
      end

      # Run the action, keeping its result or the error it raised.
      # @return [void]
      def perform
        @result = nil
        @exception = nil
        @result = @action_class.run(*@args, **@kwargs)
      rescue StandardError => e
        @exception = e
      end

      # @return [Boolean, nil]
      def primary_match?
        case @outcome
        when :success then succeeded?
        when :failure then failed?
        when :skip then skipped?
        when :raise then raised?
        end
      end

      # @return [Boolean, nil]
      def succeeded?
        @exception.nil? && @result&.success? && message_matches?(@result&.message)
      end

      # @return [Boolean, nil]
      def failed?
        @exception.nil? && @result&.failure? &&
          (@expected_code.nil? || @expected_code == @result.code) &&
          message_matches?(@result&.message)
      end

      # @return [Boolean, nil]
      def skipped?
        @exception.nil? && @result&.skipped? &&
          (@expected_code.nil? || @expected_code == @result.code) &&
          message_matches?(@result&.message)
      end

      # @return [Boolean]
      def raised?
        !@exception.nil? && @exception.is_a?(@expected_error) && message_matches?(@exception.message)
      end

      # @param actual [String, nil]
      # @return [Boolean]
      def message_matches?(actual)
        @expected_message.nil? || @expected_message === actual # rubocop:disable Style/CaseEquality
      end

      # @return [Boolean]
      def block_match?
        return true unless @block

        !!@block.call(@result, @exception)
      end

      # @return [String, nil]
      def expectation_phrase
        case @outcome
        when :success then "succeed#{message_suffix}"
        when :failure then "fail#{code_suffix}#{message_suffix}"
        when :skip then "skip#{code_suffix}#{message_suffix}"
        when :raise then "raise #{@expected_error}#{message_suffix}"
        end
      end

      # @return [String]
      def code_suffix
        @expected_code ? " with code #{@expected_code.inspect}" : ''
      end

      # @return [String]
      def message_suffix
        @expected_message ? " with message #{@expected_message.inspect}" : ''
      end

      # @return [String]
      def actual_phrase
        if @exception
          "it raised #{@exception.class}: #{@exception.message}\n#{formatted_backtrace}"
        elsif @result
          "got #{@result.inspect}"
        else
          'no result was produced'
        end
      end

      # @return [String]
      def formatted_backtrace
        frames = @exception.backtrace || []
        frames = frames.first(backtrace_qty) if short_backtrace?
        frames.join("\n")
      end

      # @return [Boolean]
      def short_backtrace?
        ENV.key?('ACTIONABLE_SHORT_BACKTRACE')
      end

      # @return [Integer]
      def backtrace_qty
        (ENV['ACTIONABLE_BACKTRACE_QTY'] || DEFAULT_BACKTRACE_QTY).to_i
      end
    end
  end
end
