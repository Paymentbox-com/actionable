# frozen_string_literal: true

RSpec.describe Actionable::Steps::Method do
  let(:instance) do
    Class.new do
      def greet
        :hello
      end
    end.new
  end

  it 'invokes the named instance method and returns its value' do
    expect(described_class.new(:greet).call(instance)).to eq(:hello)
  end

  it 'normalizes a String name to a Symbol' do
    expect(described_class.new('greet').name).to eq(:greet)
  end
end
