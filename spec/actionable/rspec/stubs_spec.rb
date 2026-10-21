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

  describe 'stubbing an action that declares failures' do
    let(:declaring) do
      Class.new(Actionable::Action) do
        fails :refused, 'the card was refused', kind: :rejected
        def go = raise('the action should not actually run')
        step :go
      end
    end

    it 'builds a Failure carrying the declared metadata and message' do
      allow_actionable_failure(declaring, code: :refused)
      run = declaring.run

      expect(run.metadata).to eq(kind: :rejected)
      expect(run.message).to eq('the card was refused')
    end

    it 'carries the declared metadata from stub_actionable_failure too' do
      stub_actionable_failure(declaring, code: :refused, message: 'declined')
      run = declaring.run

      expect(run.metadata).to eq(kind: :rejected)
      expect(run.message).to eq('declined')
    end

    it 'refuses a code the action does not declare' do
      expect { allow_actionable_failure(declaring, code: :nope) }
        .to raise_error(ArgumentError, /does not declare :nope.*:refused/)
    end

    it 'allows a code the gem emits itself' do
      expect(allow_actionable_failure(declaring, code: :invalid_input).metadata).to eq({})
    end

    it 'builds an empty metadata Failure for an action that declares none' do
      expect(allow_actionable_failure(action, code: :anything).metadata).to eq({})
    end
  end

  describe 'actionable_failure_result' do
    it 'takes explicit metadata, for a failure built without an action' do
      result = actionable_failure_result(code: :refused, metadata: {kind: :rejected})

      expect(result.metadata).to eq(kind: :rejected)
    end
  end

  describe 'allow_actionable_skip' do
    it 'builds a real Skipped with its reason' do
      allow_actionable_skip(action, code: :not_ready, message: 'later')
      run = action.run

      expect(run).to be_skipped
      expect(run.code).to eq(:not_ready)
      expect(run.message).to eq('later')
    end
  end

  describe 'stubbing an action that declares skips' do
    let(:declaring) do
      Class.new(Actionable::Action) do
        skips :not_ready, 'the field is not created yet', retry: true
        def go = raise('the action should not actually run')
        step :go
      end
    end

    it 'builds a Skipped carrying the declared metadata and message' do
      allow_actionable_skip(declaring, code: :not_ready)
      run = declaring.run

      expect(run).to be_skipped
      expect(run.metadata).to eq(retry: true)
      expect(run.message).to eq('the field is not created yet')
    end

    it 'carries the declared metadata from stub_actionable_skip too' do
      stub_actionable_skip(declaring, code: :not_ready, message: 'later')
      run = declaring.run

      expect(run.metadata).to eq(retry: true)
      expect(run.message).to eq('later')
    end

    it 'refuses a code the action does not declare' do
      expect { allow_actionable_skip(declaring, code: :paused) }
        .to raise_error(ArgumentError, /does not declare skip :paused.*:not_ready/)
    end

    it 'refuses the default :skipped when the action does not declare it' do
      expect { stub_actionable_skip(declaring) }
        .to raise_error(ArgumentError, /does not declare skip :skipped/)
    end

    it 'builds an empty metadata Skipped for an action that declares none' do
      expect(allow_actionable_skip(action, code: :anything).metadata).to eq({})
    end
  end

  describe 'actionable_skip_result' do
    it 'takes explicit metadata, for a skip built without an action' do
      result = actionable_skip_result(code: :not_ready, metadata: {retry: true})

      expect(result.metadata).to eq(retry: true)
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
