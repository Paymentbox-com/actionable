# frozen_string_literal: true

RSpec.describe 'Actionable control flow' do
  describe 'fail (record, do not halt)' do
    it 'records a Failure but keeps running later steps' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:a) do
          calls << :a
          fail(:nope, 'stop here')
        end
        define_method(:b) { calls << :b }
        step :a
        step :b
      end

      result = klass.run

      expect(calls).to eq(%i[a b])
      expect(result).to be_failure
      expect(result.code).to eq(:nope)
      expect(result.message).to eq('stop here')
    end

    it 'returns false so a step can branch on it' do
      returned = nil
      klass = Class.new(Actionable::Action) do
        define_method(:a) { returned = fail(:nope) }
        step :a
      end

      klass.run

      expect(returned).to be(false)
    end

    it 'records structured errors from keyword arguments' do
      klass = Class.new(Actionable::Action) do
        define_method(:a) { fail(:invalid, 'bad', name: 'is required') }
        step :a
      end

      result = klass.run

      expect(result.errors[:name]).to eq(['is required'])
    end
  end

  describe 'succeed (record, do not halt)' do
    it 'records a Success with message and output payload' do
      klass = Class.new(Actionable::Action) do
        define_method(:a) { succeed('done', total: 5) }
        step :a
      end

      result = klass.run

      expect(result).to be_success
      expect(result.message).to eq('done')
      expect(result.output).to eq(total: 5)
    end

    it 'returns true so a step can branch on it' do
      returned = nil
      klass = Class.new(Actionable::Action) do
        define_method(:a) { returned = succeed }
        step :a
      end

      klass.run

      expect(returned).to be(true)
    end
  end

  describe 'last write wins' do
    it 'reflects the most recent non-bang record' do
      klass = Class.new(Actionable::Action) do
        define_method(:a) { fail(:nope) }
        define_method(:b) { succeed('recovered') }
        step :a
        step :b
      end

      result = klass.run

      expect(result).to be_success
      expect(result.message).to eq('recovered')
    end
  end

  describe 'fail! / succeed! (record and halt)' do
    it 'records a Failure and skips the remaining steps' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:a) do
          calls << :a
          fail!(:nope, 'stop')
        end
        define_method(:b) { calls << :b }
        step :a
        step :b
      end

      result = klass.run

      expect(calls).to eq([:a])
      expect(result).to be_failure
      expect(result.code).to eq(:nope)
    end

    it 'records a Success and skips the remaining steps' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:a) do
          calls << :a
          succeed!('done')
        end
        define_method(:b) { calls << :b }
        step :a
        step :b
      end

      result = klass.run

      expect(calls).to eq([:a])
      expect(result).to be_success
      expect(result.message).to eq('done')
    end
  end

  describe 'halt! (stop, keep current result)' do
    it 'stops the pipeline and keeps a previously recorded result' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:record_failure) { fail(:nope) }
        define_method(:stop) { halt! }
        define_method(:b) { calls << :b }
        step :record_failure
        step :stop
        step :b
      end

      result = klass.run

      expect(calls).to eq([])
      expect(result).to be_failure
      expect(result.code).to eq(:nope)
    end

    it 'auto-succeeds when nothing was recorded before the halt' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:a) { halt! }
        define_method(:b) { calls << :b }
        step :a
        step :b
      end

      result = klass.run

      expect(calls).to eq([])
      expect(result).to be_success
    end
  end

  describe 'fail_with (absorb a FieldStruct\'s errors)' do
    # A throwaway FieldStruct shape with a required field, so an empty instance
    # is invalid and carries a per-field error.
    let(:shape) do
      Class.new(FieldStruct::Base) do
        required :name, :string
        required :email, :string
      end
    end

    it 'records a Failure carrying the struct\'s validation errors' do
      bad = shape.new
      bad.valid? # populate errors
      this = self
      klass = Class.new(Actionable::Action) do
        define_method(:validate) { fail_with(this.shape.new, code: :invalid_event) }
        step :validate
      end

      result = klass.run

      expect(result).to be_failure
      expect(result.code).to eq(:invalid_event)
      expect(result.errors[:name]).to eq(['is required'])
      expect(result.errors[:email]).to eq(['is required'])
    end

    it 'defaults the code to :invalid and does not halt (last write wins)' do
      this = self
      klass = Class.new(Actionable::Action) do
        define_method(:validate) { fail_with(this.shape.new) }
        define_method(:recover) { succeed('recovered') }
        step :validate
        step :recover
      end

      expect(klass.run).to be_success
    end

    it 'fail_with! records and halts' do
      calls = []
      this = self
      klass = Class.new(Actionable::Action) do
        define_method(:validate) { fail_with!(this.shape.new, code: :invalid_event, message: 'bad shape') }
        define_method(:after) { calls << :after }
        step :validate
        step :after
      end

      result = klass.run

      expect(result).to be_failure
      expect(result.code).to eq(:invalid_event)
      expect(result.message).to eq('bad shape')
      expect(calls).to eq([])
    end
  end
end
