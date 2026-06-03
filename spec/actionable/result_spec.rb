# frozen_string_literal: true

RSpec.describe 'Actionable result value objects' do
  describe Actionable::Success do
    it 'reports success and not failure' do
      result = described_class.new

      expect(result).to be_success
      expect(result).to be_successful
      expect(result).not_to be_failure
      expect(result).not_to be_failed
    end

    it 'defaults its code to :success' do
      expect(described_class.new.code).to eq(:success)
    end

    it 'carries message, output, and history' do
      result = described_class.new(
        message: 'all good',
        output: {invoice: 7},
        history: [:built]
      )

      expect(result.message).to eq('all good')
      expect(result.output).to eq(invoice: 7)
      expect(result.history).to eq([:built])
    end

    it 'defaults errors/output/history to fresh, empty collections' do
      a = described_class.new
      b = described_class.new

      expect(a.errors).to be_empty
      expect(a.output).to eq({})
      expect(a.history).to eq([])
      # fresh per instance — mutating one must not leak into the next
      expect(a.output).not_to equal(b.output)
    end
  end

  describe Actionable::Failure do
    it 'reports failure and not success' do
      result = described_class.new(code: :not_found)

      expect(result).to be_failure
      expect(result).to be_failed
      expect(result).not_to be_success
      expect(result).not_to be_successful
    end

    it 'preserves the error code it is given' do
      expect(described_class.new(code: :not_found).code).to eq(:not_found)
    end

    it 'has a Symbol code by default' do
      expect(described_class.new.code).to be_a(Symbol)
    end

    it 'accumulates structured errors via its FieldStruct errors collection' do
      result = described_class.new(code: :invalid)
      result.errors.add(:name, 'is required')

      expect(result.errors).not_to be_empty
      expect(result.errors[:name]).to eq(['is required'])
    end

    it 'renders human-readable error sentences via FieldStruct full_messages' do
      result = described_class.new(code: :invalid)
      result.errors.add(:first_name, 'is required')

      expect(result.errors.full_messages).to eq(['First name is required'])
    end
  end

  describe 'value semantics' do
    it 'is equal by class and attributes' do
      a = Actionable::Failure.new(code: :nope, message: 'stop')
      b = Actionable::Failure.new(code: :nope, message: 'stop')

      expect(a).to eq(b)
    end

    it 'distinguishes Success from Failure even with identical attributes' do
      success = Actionable::Success.new(code: :success)
      failure = Actionable::Failure.new(code: :success)

      expect(success).not_to eq(failure)
    end
  end

  describe 'deterministic representation' do
    it 'inspects with the class name and all five attributes in sorted order' do
      string = Actionable::Success.new.inspect

      expect(string).to start_with('#<Actionable::Success')
      names = %w[code errors history message output]
      positions = names.map { |name| string.index("#{name}=") }
      expect(positions).to all(be_truthy)
      expect(positions).to eq(positions.compact.sort)
    end

    it 'surfaces accumulated errors in the representation' do
      result = Actionable::Failure.new(code: :invalid)
      result.errors.add(:name, 'is required')

      expect(result.inspect).to include('errors={:name=>["is required"]}')
    end

    it 'renders identically for equal results' do
      a = Actionable::Failure.new(code: :nope, message: 'stop')
      b = Actionable::Failure.new(code: :nope, message: 'stop')

      expect(a.inspect).to eq(b.inspect)
      expect(a.to_s).to eq(b.to_s)
    end
  end

  describe '#to_h' do
    it 'returns code, message, output, history, and errors as a plain Hash' do
      result = Actionable::Success.new(code: :success, message: 'done', output: {id: 7})

      expect(result.to_h).to eq(
        code: :success, message: 'done', output: {id: 7}, history: [], errors: {}
      )
    end

    it 'includes the errors collection as a Hash' do
      result = Actionable::Failure.new(code: :invalid)
      result.errors.add(:name, 'is required')

      expect(result.to_h[:errors]).to eq(name: ['is required'])
    end

    it 'renders a FieldStruct output through its own to_h' do
      shape = Class.new(FieldStruct::Base) { optional :total, :integer }
      result = Actionable::Success.new(output: shape.new(total: 5))

      expect(result.to_h[:output]).to eq(total: 5)
    end
  end

  describe '#to_api_h' do
    it 'yields an API element with index, status, id, and errors' do
      shape = Class.new(FieldStruct::Base) { optional :id, :integer }
      result = Actionable::Success.new(output: shape.new(id: 99))

      expect(result.to_api_h(index: 0)).to eq(index: 0, status: :success, id: 99, errors: {})
    end

    it 'reports the failure status and errors, with a nil id when absent' do
      result = Actionable::Failure.new(code: :invalid_input)
      result.errors.add(:amount, 'is required')

      expect(result.to_api_h(index: 3)).to eq(
        index: 3, status: :failure, id: nil, errors: {amount: ['is required']}
      )
    end

    it 'reports the skipped status' do
      expect(Actionable::Skipped.new.to_api_h[:status]).to eq(:skipped)
    end
  end
end
