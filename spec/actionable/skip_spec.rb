# frozen_string_literal: true

RSpec.describe 'Actionable skip status' do
  describe 'the Skipped result' do
    it 'is neither success nor failure, is skipped, and is ok' do
      result = Actionable::Skipped.new(code: :not_ready)

      expect(result).to be_skipped
      expect(result).not_to be_success
      expect(result).not_to be_failure
      expect(result).to be_ok
      expect(result.code).to eq(:not_ready)
    end

    it 'defaults its code to :skipped' do
      expect(Actionable::Skipped.new.code).to eq(:skipped)
    end

    it 'reports ok? across the three outcomes (ok == not failed)' do
      expect(Actionable::Success.new).to be_ok
      expect(Actionable::Skipped.new).to be_ok
      expect(Actionable::Failure.new).not_to be_ok
      expect(Actionable::Success.new).not_to be_skipped
    end
  end

  describe 'skip! (record and halt)' do
    it 'records a Skipped with its reason and skips the remaining steps' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:check) { skip!(:not_ready, 'nothing to do') }
        define_method(:work) { calls << :work }
        step :check
        step :work
      end

      result = klass.run

      expect(result).to be_skipped
      expect(result.code).to eq(:not_ready)
      expect(result.message).to eq('nothing to do')
      expect(calls).to eq([])
    end
  end

  describe 'skip (record, continue)' do
    it 'records a Skipped but keeps running — last write wins' do
      klass = Class.new(Actionable::Action) do
        define_method(:a) { skip(:not_ready) }
        define_method(:b) { succeed('did it') }
        step :a
        step :b
      end

      expect(klass.run).to be_success
    end

    it 'returns false' do
      returned = nil
      klass = Class.new(Actionable::Action) do
        define_method(:a) { returned = skip }
        step :a
      end

      klass.run

      expect(returned).to be(false)
    end
  end

  describe 'output on a skipped run' do
    it 'is captured best-effort and not validated' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:check) { skip!(:not_ready) } # never sets @total
        step :check
      end

      result = klass.run

      expect(result).to be_skipped
      expect(result.code).to eq(:not_ready) # NOT :invalid_output
      expect(result.output.total).to be_nil
    end
  end

  describe 'lifecycle dispatch' do
    it 'runs on_skip hooks (not on_success/on_failure), then always' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:check) { skip!(:not_ready) }
        define_method(:cleanup) { calls << :cleanup }
        define_method(:rollback) { calls << :rollback }
        define_method(:note_skip) { calls << :skip }
        define_method(:log) { calls << :log }
        step :check
        on_success :cleanup
        on_failure :rollback
        on_skip :note_skip
        always :log
      end

      klass.run

      expect(calls).to eq(%i[skip log])
    end
  end

  describe 'a skipped nested action' do
    it 'continues the parent like a success, absorbing best-effort output' do
      child = Class.new(Actionable::Action) do
        output { optional :note, :string }
        define_method(:go) { skip!(:not_ready) } # never sets @note
        step :go
      end
      parent = Class.new(Actionable::Action) do
        output do
          optional :note, :string
          optional :done, :boolean
        end
        define_method(:finish) { @done = true }
        step child
        step :finish
      end

      result = parent.run

      expect(result).to be_success         # parent decides its own outcome
      expect(result.output.done).to be(true) # parent ran past the skipped child
      expect(result.output.note).to be_nil
    end
  end
end
