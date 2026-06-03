# frozen_string_literal: true

RSpec.describe 'Actionable sampled measurement' do
  it 'records a History on every run at rate 1.0' do
    klass = Class.new(Actionable::Action) do
      measure :sampled, rate: 1.0
      step :work
      def work = nil
    end

    history = klass.run.history
    expect(history).to be_a(Actionable::History)
    expect(history.steps.map(&:name)).to eq(%i[work])
  end

  it 'records nothing on any run at rate 0.0' do
    klass = Class.new(Actionable::Action) do
      measure :sampled, rate: 0.0
      step :work
      def work = nil
    end

    expect(klass.run.history).to be_empty # the default, like measure :none
  end

  it 'cascades into nested actions when sampled in' do
    child = Class.new(Actionable::Action) do
      step :go
      def go = nil
    end
    parent = Class.new(Actionable::Action) do
      measure :sampled, rate: 1.0
      step child
      step :after
      def after = nil
    end

    history = parent.run.history
    expect(history).to be_a(Actionable::History)
    expect(history.steps.first.nested).to be_a(Actionable::History)
  end

  it 'reports the mode and rate' do
    klass = Class.new(Actionable::Action) do
      measure :sampled, rate: 0.25
    end

    expect(klass.measure).to eq(:sampled)
    expect(klass.measure_rate).to eq(0.25)
    expect(klass.measure_sampled?).to be(true)
  end

  it 'rejects :sampled without a valid rate' do
    expect { Class.new(Actionable::Action) { measure :sampled } }
      .to raise_error(ArgumentError, /rate/)
    expect { Class.new(Actionable::Action) { measure :sampled, rate: 2 } }
      .to raise_error(ArgumentError, /rate/)
  end

  it 'still rejects an unknown mode' do
    expect { Class.new(Actionable::Action) { measure :sometimes } }
      .to raise_error(ArgumentError, /unknown measure mode/)
  end

  it 'inherits mode and rate to subclasses' do
    parent = Class.new(Actionable::Action) { measure :sampled, rate: 0.5 }
    child = Class.new(parent)

    expect(child.measure).to eq(:sampled)
    expect(child.measure_rate).to eq(0.5)
  end
end
