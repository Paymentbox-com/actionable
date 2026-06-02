# frozen_string_literal: true

require 'actionable/rails'

RSpec.describe Actionable::ProxyValidator do
  let(:rules) do
    Class.new(described_class) do
      validates :amount, presence: true
      validates :amount, numericality: {greater_than: 0}, allow_nil: true
    end
  end
  let(:delegate) { Struct.new(:amount) }

  it 'runs its ActiveModel rules against the delegate\'s attributes' do
    expect(rules.new(delegate.new(5))).to be_valid
    expect(rules.new(delegate.new(nil))).to be_invalid
    expect(rules.new(delegate.new(-1))).to be_invalid
  end

  it 'exposes formatted_errors keyed by attribute' do
    validator = rules.new(delegate.new(nil))

    expect(validator.formatted_errors[:amount]).to include("can't be blank")
  end

  it 'is usable inside a step to fail an action with the delegate errors' do
    rule_class = rules
    delegate_class = delegate
    klass = Class.new(Actionable::Action) do
      define_method(:validate_amount) do
        validator = rule_class.new(delegate_class.new(nil))
        fail(:invalid, 'bad amount', **validator.formatted_errors) unless validator.valid?
      end
      step :validate_amount
    end

    result = klass.run

    expect(result).to be_failure
    expect(result.code).to eq(:invalid)
    expect(result.errors[:amount]).to include("can't be blank")
  end
end
