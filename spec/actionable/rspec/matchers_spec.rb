# frozen_string_literal: true

require 'actionable/rspec'

RSpec.describe 'perform_actionable matcher' do
  let(:succeeds) do
    Class.new(Actionable::Action) do
      def go = succeed('done')
      step :go
    end
  end
  let(:fails) do
    Class.new(Actionable::Action) do
      def go = fail!(:nope, 'bad input')
      step :go
    end
  end
  let(:raises) do
    Class.new(Actionable::Action) do
      def go = raise(ArgumentError, 'boom')
      step :go
    end
  end
  let(:doubler) do
    Class.new(Actionable::Action) do
      input { required :n, :integer }
      output { required :doubled, :integer }
      def go = @doubled = input.n * 2
      step :go
    end
  end

  describe 'success expectations' do
    it 'passes for a succeeding action' do
      expect(succeeds).to perform_actionable.and_succeed
    end

    it 'matches the success message (exact and Regexp)' do
      expect(succeeds).to perform_actionable.and_succeed('done')
      expect(succeeds).to perform_actionable.and_succeed(/do/)
    end

    it 'threads args/kwargs through to .run' do
      expect(doubler).to perform_actionable(n: 5).and_succeed
    end
  end

  describe 'failure expectations' do
    it 'passes for a failing action with the expected code' do
      expect(fails).to perform_actionable.and_fail(:nope)
    end

    it 'matches code and message together' do
      expect(fails).to perform_actionable.and_fail(:nope, 'bad input')
    end

    it 'does not match the wrong code' do
      expect(fails).not_to perform_actionable.and_fail(:other)
    end
  end

  describe 'raise expectations' do
    it 'asserts a raised exception of the expected class' do
      expect(raises).to perform_actionable.and_raise(ArgumentError)
    end

    it 'matches the exception message' do
      expect(raises).to perform_actionable.and_raise(ArgumentError, /boom/)
    end
  end

  describe 'skip expectations' do
    let(:skips) do
      Class.new(Actionable::Action) do
        def go = skip!(:not_ready, 'nothing to do')
        step :go
      end
    end

    it 'passes for a skipped action' do
      expect(skips).to perform_actionable.and_skip
    end

    it 'matches the skip reason code and message' do
      expect(skips).to perform_actionable.and_skip(:not_ready, 'nothing to do')
    end

    it 'does not treat a skip as a success or a failure' do
      expect(skips).not_to perform_actionable.and_succeed
      expect(skips).not_to perform_actionable.and_fail
    end
  end

  describe 'block form' do
    it 'yields the result and exception for extra assertions' do
      expect(succeeds).to perform_actionable.and_succeed do |result, exception|
        expect(result.message).to eq('done')
        expect(exception).to be_nil
      end
    end
  end

  describe 'failure messages' do
    it 'explains the mismatch when the outcome is wrong' do
      matcher = perform_actionable.and_succeed
      matcher.matches?(fails)

      expect(matcher.failure_message).to match(/succeed/)
      expect(matcher.failure_message).to include('nope')
    end

    it 'surfaces an unexpected exception with a trimmed backtrace' do
      matcher = perform_actionable.and_succeed
      ENV['ACTIONABLE_SHORT_BACKTRACE'] = '1'
      ENV['ACTIONABLE_BACKTRACE_QTY'] = '2'
      matcher.matches?(raises)

      message = matcher.failure_message
      expect(message).to include('ArgumentError', 'boom')
      expect(message.lines.grep(/:\d+:in /).size).to be <= 2
    ensure
      ENV.delete('ACTIONABLE_SHORT_BACKTRACE')
      ENV.delete('ACTIONABLE_BACKTRACE_QTY')
    end
  end
end
