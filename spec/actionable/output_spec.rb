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
end
