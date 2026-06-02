# frozen_string_literal: true

require 'actionable/rspec'

RSpec.describe 'actionable rspec stubs' do
  # Its step would blow up if actually executed, proving the stub bypasses the run.
  let(:action) do
    Class.new(Actionable::Action) do
      def go = raise('the action should not actually run')
      step :go
    end
  end

  describe 'allow_actionable_success' do
    it 'returns a real Success and makes .run return it without executing the action' do
      result = allow_actionable_success(action, message: 'ok', output: {id: 7})
      run = action.run

      expect(run).to equal(result)
      expect(run).to be_success
      expect(run.message).to eq('ok')
      expect(run.output).to eq(id: 7)
    end
  end

  describe 'allow_actionable_failure' do
    it 'builds a Failure with code and errors' do
      allow_actionable_failure(action, code: :invalid, message: 'bad', errors: {name: 'is required'})
      run = action.run

      expect(run).to be_failure
      expect(run.code).to eq(:invalid)
      expect(run.message).to eq('bad')
      expect(run.errors[:name]).to eq(['is required'])
    end
  end

  describe 'stub_actionable_success' do
    it 'sets a call expectation satisfied when the action is run' do
      stub_actionable_success(action, message: 'ok')

      expect(action.run).to be_success
    end
  end

  describe 'composing with the matcher' do
    it 'a stubbed failure satisfies perform_actionable' do
      allow_actionable_failure(action, code: :nope)

      expect(action).to perform_actionable.and_fail(:nope)
    end
  end
end
