# frozen_string_literal: true

RSpec.describe 'Actionable typed output' do
  describe 'capturing declared output from instance variables' do
    it 'surfaces a matching ivar on the typed output and via delegation' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:compute) { @total = 42 }
        step :compute
      end

      result = klass.run

      expect(result).to be_success
      expect(result.output.total).to eq(42)
      expect(result.total).to eq(42) # convenience delegation
    end

    it 'coerces captured values through the FieldStruct schema' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:compute) { @total = '42' }
        step :compute
      end

      expect(klass.run.output.total).to eq(42)
    end

    it 'surfaces only declared fields, never incidental ivars' do
      klass = Class.new(Actionable::Action) do
        output { optional :total, :integer }
        define_method(:compute) do
          @total = 5
          @secret = 'hidden'
        end
        step :compute
      end

      result = klass.run

      expect(result.output.total).to eq(5)
      expect(result).not_to respond_to(:secret)
      expect(result.output).not_to respond_to(:secret)
    end
  end

  describe 'succeed keyword arguments' do
    it 'overlays captured ivars, with the kwargs winning on conflict' do
      klass = Class.new(Actionable::Action) do
        output { optional :total, :integer }
        define_method(:compute) { @total = 1 }
        define_method(:finish) { succeed(total: 99) }
        step :compute
        step :finish
      end

      expect(klass.run.output.total).to eq(99)
    end
  end

  describe 'a successful run whose output fails validation' do
    it 'becomes a Failure(:invalid_output) carrying the validation errors' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:noop) { nil } # never sets @total
        step :noop
      end

      result = klass.run

      expect(result).to be_failure
      expect(result.code).to eq(:invalid_output)
      expect(result.errors[:total]).to include('is required')
    end
  end

  describe 'output on a failed run' do
    it 'is captured best-effort and is not validated' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:go) { fail!(:nope) } # never sets @total
        step :go
      end

      result = klass.run

      expect(result).to be_failure
      expect(result.code).to eq(:nope) # NOT :invalid_output — failures aren't validated
      expect(result.output.total).to be_nil
    end

    it 'captures whatever ivars were set before the failure' do
      klass = Class.new(Actionable::Action) do
        output do
          optional :total, :integer
          optional :note, :string
        end
        define_method(:go) do
          @total = 7
          fail!(:nope)
        end
        step :go
      end

      result = klass.run

      expect(result.output.total).to eq(7)
      expect(result.output.note).to be_nil
    end
  end

  describe 'an action with no output schema' do
    it 'leaves output free-form (succeed kwargs passthrough)' do
      klass = Class.new(Actionable::Action) do
        define_method(:finish) { succeed(total: 5) }
        step :finish
      end

      expect(klass.run.output).to eq(total: 5)
    end

    it 'defaults output to an empty collection on auto-success' do
      klass = Class.new(Actionable::Action) do
        define_method(:noop) { nil }
        step :noop
      end

      expect(klass.run.output).to eq({})
    end
  end

  describe 'succeed/skip kwargs across lifecycle hooks' do
    it 'keeps succeed kwargs after an on_success hook refreshes the output' do
      klass = Class.new(Actionable::Action) do
        output { required :id, :integer }
        define_method(:go) { succeed('ok', id: 7) }
        define_method(:notify) { nil }
        step :go
        on_success :notify
      end

      result = klass.run

      expect(result).to be_success
      expect(result.output.id).to eq(7)
    end

    it 'keeps succeed kwargs winning over an ivar after an always hook' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:go) do
          @total = 1
          succeed(total: 99)
        end
        define_method(:log) { nil }
        step :go
        always :log
      end

      result = klass.run

      expect(result.output.total).to eq(99)
    end

    it 'keeps skip kwargs after a hook' do
      klass = Class.new(Actionable::Action) do
        output { optional :reason, :string }
        define_method(:go) { skip(:duplicate, nil, reason: 'seen') }
        define_method(:log) { nil }
        step :go
        always :log
      end

      expect(klass.run.output.reason).to eq('seen')
    end
  end

  describe 'best-effort output on a non-typed failure or skip' do
    it 'adds no output error to a failure' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:go) { fail!(:nope) }
        step :go
      end

      result = klass.run

      expect(result.code).to eq(:nope)
      expect(result.errors.to_h).to be_empty
      expect(result.errors.full_messages).to be_empty
    end

    it 'adds no output error to a skip' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:go) { skip!(:dup) }
        step :go
      end

      expect(klass.run.errors.to_h).to be_empty
    end

    it 'keeps errors the failure recorded itself' do
      klass = Class.new(Actionable::Action) do
        output { required :total, :integer }
        define_method(:go) { fail!(:invalid, nil, amount: ['is negative']) }
        step :go
      end

      expect(klass.run.errors.to_h).to eq(amount: ['is negative'])
    end
  end
end
