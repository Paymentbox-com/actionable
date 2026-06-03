# frozen_string_literal: true

RSpec.describe 'Actionable discriminated input (input_for)' do
  let(:sale_shape) { Class.new(FieldStruct::Base) { required :amount, :integer } }
  let(:refund_shape) { Class.new(FieldStruct::Base) { required :original_id, :integer } }

  # An action that picks its input schema from the :event_type discriminator,
  # then captures whichever typed field arrived.
  let(:klass) do
    sale = sale_shape
    refund = refund_shape
    Class.new(Actionable::Action) do
      input_for(:event_type) do
        on 'sale', sale
        on 'refund', refund
      end
      output do
        optional :amount, :integer
        optional :original_id, :integer
      end
      step :capture
      define_method(:capture) do
        @amount = input.amount if input.respond_to?(:amount)
        @original_id = input.original_id if input.respond_to?(:original_id)
      end
    end
  end

  it 'coerces and validates the schema chosen by the discriminator' do
    expect(klass.run(event_type: 'sale', amount: '5').output.amount).to eq(5)
    expect(klass.run(event_type: 'refund', original_id: 9).output.original_id).to eq(9)
  end

  it 'fails :invalid_input when the chosen schema is invalid' do
    result = klass.run(event_type: 'sale') # missing required :amount

    expect(result).to be_failure
    expect(result.code).to eq(:invalid_input)
    expect(result.errors[:amount]).to eq(['is required'])
  end

  it 'fails :invalid_input when no branch matches and there is no default' do
    result = klass.run(event_type: 'unknown')

    expect(result).to be_failure
    expect(result.code).to eq(:invalid_input)
    expect(result.message).to match(/event_type/)
  end

  it 'accepts a pre-built instance of any declared shape' do
    result = klass.run(sale_shape.new(amount: 3))

    expect(result).to be_success
    expect(result.output.amount).to eq(3)
  end

  it 'matches by Array membership and falls through to a default shape' do
    sale = sale_shape
    k = Class.new(Actionable::Action) do
      input_for(:kind) do
        on %w[a b], sale
        default sale
      end
      output { optional :amount, :integer }
      step :go
      define_method(:go) { @amount = input.amount }
    end

    expect(k.run(kind: 'b', amount: 1).output.amount).to eq(1) # array hit
    expect(k.run(kind: 'z', amount: 2).output.amount).to eq(2) # default
  end

  it 'reflects the discrimination in describe / describe_text' do
    expect(klass.describe[:input]).to include(discriminated_on: :event_type)
    expect(klass.describe[:input][:shapes]).to include('sale', 'refund')
    expect(klass.describe_text).to match(/discriminated on event_type/)
  end
end
