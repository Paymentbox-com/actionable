# frozen_string_literal: true

RSpec.describe 'Actionable typed input' do
  let(:doubler) do
    Class.new(Actionable::Action) do
      input do
        required :amount, :integer
        optional :name, :string
      end
      output { required :doubled, :integer }
      define_method(:compute) { @doubled = input.amount * 2 }
      step :compute
    end
  end

  describe 'coercing run arguments into the input struct' do
    it 'exposes the typed input to the steps' do
      result = doubler.run(amount: 5, name: 'Acme')

      expect(result).to be_success
      expect(result.output.doubled).to eq(10)
    end

    it 'coerces the input values through FieldStruct' do
      expect(doubler.run(amount: '5').output.doubled).to eq(10)
    end

    it 'accepts an already-built input instance' do
      input = doubler.input_schema.new(amount: 5)

      expect(doubler.run(input).output.doubled).to eq(10)
    end
  end

  describe 'invalid input' do
    it 'fails with :invalid_input and runs no steps when a required input is missing' do
      ran = []
      klass = Class.new(Actionable::Action) do
        input { required :amount, :integer }
        define_method(:compute) { ran << :compute }
        step :compute
      end

      result = klass.run # no amount

      expect(result).to be_failure
      expect(result.code).to eq(:invalid_input)
      expect(result.errors[:amount]).to include('is required')
      expect(ran).to eq([])
    end
  end

  describe 'the free-form fallback' do
    it 'forwards run arguments to a custom constructor when no input block is declared' do
      seen = []
      klass = Class.new(Actionable::Action) do
        define_method(:initialize) { |label:| @label = label }
        define_method(:record) { seen << @label }
        step :record
      end

      klass.run(label: :hi)

      expect(seen).to eq([:hi])
    end

    it 'leaves the input reader nil for a free-form action' do
      captured = []
      klass = Class.new(Actionable::Action) do
        define_method(:check) { captured << input }
        step :check
      end

      klass.run

      expect(captured).to eq([nil])
    end
  end
end
