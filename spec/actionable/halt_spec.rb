# frozen_string_literal: true

RSpec.describe 'the halt primitive' do
  it 'exposes the throw/catch tag' do
    expect(Actionable::HALT).to eq(:actionable_halt)
  end

  describe 'Actionable.catch_halt' do
    it 'returns the block value when nothing halts' do
      expect(Actionable.catch_halt { 42 }).to eq(42)
    end

    it 'unwinds to the catch point when the halt tag is thrown' do
      steps = []
      Actionable.catch_halt do
        steps << :before
        throw Actionable::HALT
      end
      steps << :after_catch

      expect(steps).to eq(%i[before after_catch])
    end

    it 'returns the value passed with the throw' do
      expect(Actionable.catch_halt { throw Actionable::HALT, :stopped }).to eq(:stopped)
    end

    it 'lets a raised StandardError propagate past the catch (D4)' do
      expect { Actionable.catch_halt { raise ArgumentError, 'kaboom' } }
        .to raise_error(ArgumentError, 'kaboom')
    end
  end
end
