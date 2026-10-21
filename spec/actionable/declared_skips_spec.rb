# frozen_string_literal: true

RSpec.describe 'declared skips (skips)' do
  let(:sync) do
    Class.new(Actionable::Action) do
      skips :not_ready, 'the field is not created yet', retry: true
      skips :already_synced, retry: false

      input { required :state, :symbol }
      step :decide

      def decide
        case input.state
        when :not_ready then skip!(:not_ready)
        when :not_ready_with_message then skip!(:not_ready, 'field 42 is missing')
        when :already_synced then skip(:already_synced, nil, id: 7)
        end
      end
    end
  end

  describe '.declared_skips' do
    it 'maps each declared code to its metadata' do
      expect(sync.declared_skips).to eq(not_ready: {retry: true}, already_synced: {retry: false})
    end

    it 'is empty for an action that declares none' do
      expect(Class.new(Actionable::Action).declared_skips).to eq({})
    end

    it 'accepts a String code as its Symbol' do
      action = Class.new(Actionable::Action) { skips 'idle' }

      expect(action.declared_skips).to eq(idle: {})
    end

    it 'lets a redeclared code replace its metadata' do
      action = Class.new(Actionable::Action) do
        skips :not_ready, retry: true
        skips :not_ready, retry: false
      end

      expect(action.declared_skips).to eq(not_ready: {retry: false})
    end

    it 'is separate from the declared failures' do
      expect(sync.declared_failures).to eq({})
    end
  end

  describe '.skip_declarations' do
    it 'keys each code to its message and metadata' do
      expect(sync.skip_declarations).to eq(
        not_ready: {message: 'the field is not created yet', metadata: {retry: true}},
        already_synced: {message: nil, metadata: {retry: false}}
      )
    end
  end

  describe 'inheritance' do
    it 'gives a subclass its parent declarations, which it can extend' do
      child = Class.new(sync) { skips :paused }

      expect(child.declared_skips.keys).to eq(%i[not_ready already_synced paused])
    end

    it 'never mutates the parent when the subclass declares more' do
      Class.new(sync) { skips :paused }

      expect(sync.declared_skips.keys).to eq(%i[not_ready already_synced])
    end
  end

  describe 'the skipped result' do
    it 'carries the metadata of its declared code' do
      result = sync.run(state: :not_ready)

      expect(result).to be_skipped
      expect(result.code).to eq(:not_ready)
      expect(result.metadata).to eq(retry: true)
    end

    it 'uses the declared message when skip gives none' do
      expect(sync.run(state: :not_ready).message).to eq('the field is not created yet')
    end

    it 'keeps the message skip gives over the declared one' do
      expect(sync.run(state: :not_ready_with_message).message).to eq('field 42 is missing')
    end

    it 'keeps the output skip gives beside the metadata' do
      result = sync.run(state: :already_synced)

      expect(result.metadata).to eq(retry: false)
      expect(result.output).to eq(id: 7)
    end

    it 'defaults metadata to an empty Hash' do
      expect(Actionable::Skipped.new.metadata).to eq({})
    end

    it 'carries no metadata when the action declares no skips' do
      action = Class.new(Actionable::Action) do
        step :go
        def go = skip!(:idle)
      end

      expect(action.run.metadata).to eq({})
    end

    it 'shows the metadata in to_h' do
      expect(sync.run(state: :not_ready).to_h).to include(metadata: {retry: true})
    end
  end
end
