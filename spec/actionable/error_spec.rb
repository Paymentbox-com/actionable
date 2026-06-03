# frozen_string_literal: true

RSpec.describe Actionable::Error do
  it 'is a StandardError, so an ordinary rescue catches it' do
    expect(described_class.ancestors).to include(StandardError)
  end

  it 'roots the gem error family so callers can rescue them together' do
    specific = Class.new(described_class)

    expect { raise specific, 'boom' }.to raise_error(Actionable::Error, 'boom')
  end
end
