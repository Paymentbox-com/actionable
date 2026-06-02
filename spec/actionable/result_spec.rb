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
end
