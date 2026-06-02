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
      # @param args [Array] positional args forwarded to +.run+
      # @param kwargs [Hash] keyword args forwarded to +.run+
      # @yield [result, exception] optional extra assertions
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
      DEFAULT_BACKTRACE_QTY = 10

      def initialize(args, kwargs, block)
        @args = args
        @kwargs = kwargs
        @block = block
        @outcome = :success
      end

      # Expect a successful result, optionally matching +message+.
      # @return [self]
      def and_succeed(message = nil, &block)
        configure(:success, message, &block)
      end

      # Expect a failed result, optionally matching +code+ and +message+.
      # @return [self]
      def and_fail(code = nil, message = nil, &block)
        @expected_code = code
        configure(:failure, message, &block)
      end

      # Expect the run to raise +error_class+, optionally matching +message+.
      # @return [self]
      def and_raise(error_class = StandardError, message = nil, &block)
        @expected_error = error_class
        configure(:raise, message, &block)
      end

      # @param action_class [Class<Actionable::Action>]
      # @return [Boolean]
      def matches?(action_class)
        @action_class = action_class
        perform
        primary_match? && block_match?
      end

      # @param action_class [Class<Actionable::Action>]
      # @return [Boolean]
      def does_not_match?(action_class)
        @action_class = action_class
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

      def configure(outcome, message, &block)
        @outcome = outcome
        @expected_message = message
        @block = block if block
        self
      end

      def perform
        @result = nil
        @exception = nil
        @result = @action_class.run(*@args, **@kwargs)
      rescue StandardError => e
        @exception = e
      end

      def primary_match?
        case @outcome
        when :success then succeeded?
        when :failure then failed?
        when :raise then raised?
        end
      end

      def succeeded?
        @exception.nil? && @result&.success? && message_matches?(@result&.message)
      end

      def failed?
        @exception.nil? && @result&.failure? &&
          (@expected_code.nil? || @expected_code == @result.code) &&
          message_matches?(@result&.message)
      end

      def raised?
        !@exception.nil? && @exception.is_a?(@expected_error) && message_matches?(@exception.message)
      end

      def message_matches?(actual)
        @expected_message.nil? || @expected_message === actual # rubocop:disable Style/CaseEquality
      end

      def block_match?
        return true unless @block

        !!@block.call(@result, @exception)
      end

      def expectation_phrase
        case @outcome
        when :success then "succeed#{message_suffix}"
        when :failure then "fail#{code_suffix}#{message_suffix}"
        when :raise then "raise #{@expected_error}#{message_suffix}"
        end
      end

      def code_suffix
        @expected_code ? " with code #{@expected_code.inspect}" : ''
      end

      def message_suffix
        @expected_message ? " with message #{@expected_message.inspect}" : ''
      end

      def actual_phrase
        if @exception
          "it raised #{@exception.class}: #{@exception.message}\n#{formatted_backtrace}"
        elsif @result
          "got #{@result.inspect}"
        else
          'no result was produced'
        end
      end

      def formatted_backtrace
        frames = @exception.backtrace || []
        frames = frames.first(backtrace_qty) if short_backtrace?
        frames.join("\n")
      end

      def short_backtrace?
        ENV.key?('ACTIONABLE_SHORT_BACKTRACE')
      end

      def backtrace_qty
        (ENV['ACTIONABLE_BACKTRACE_QTY'] || DEFAULT_BACKTRACE_QTY).to_i
      end
    end
  end
end
