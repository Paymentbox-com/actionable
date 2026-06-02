# frozen_string_literal: true

RSpec.describe Actionable::Action do
  describe 'running an action' do
    it 'runs its steps in declared order' do
      calls = []
      klass = Class.new(described_class) do
        define_method(:a) { calls << :a }
        define_method(:b) { calls << :b }
        step :a
        step :b
      end

      klass.run

      expect(calls).to eq(%i[a b])
    end

    it 'auto-succeeds when no result was set' do
      klass = Class.new(described_class) do
        define_method(:noop) { nil }
        step :noop
      end

      result = klass.run

      expect(result).to be_a(Actionable::Success)
      expect(result).to be_success
    end

    it 'forwards constructor arguments to the action instance' do
      seen = []
      klass = Class.new(described_class) do
        define_method(:initialize) { |label:| @label = label }
        define_method(:record) { seen << @label }
        step :record
      end

      klass.run(label: :hi)

      expect(seen).to eq([:hi])
    end
  end

  describe 'halting the pipeline' do
    it 'stops running steps once the halt tag is thrown' do
      calls = []
      klass = Class.new(described_class) do
        define_method(:a) do
          calls << :a
          throw Actionable::HALT
        end
        define_method(:b) { calls << :b }
        step :a
        step :b
      end

      result = klass.run

      expect(calls).to eq([:a])
      expect(result).to be_success
    end

    it 'lets a raised StandardError propagate to the caller (D4)' do
      klass = Class.new(described_class) do
        define_method(:boom) { raise ArgumentError, 'kaboom' }
        step :boom
      end

      expect { klass.run }.to raise_error(ArgumentError, 'kaboom')
    end
  end

  describe 'step guards' do
    it 'skips steps whose :if/:unless guard says to' do
      calls = []
      klass = Class.new(described_class) do
        define_method(:initialize) { |run_b:| @run_b = run_b }
        define_method(:run_b?) { @run_b }
        define_method(:a) { calls << :a }
        define_method(:b) { calls << :b }
        step :a
        step :b, if: :run_b?
      end

      klass.run(run_b: false)

      expect(calls).to eq([:a])
    end
  end

  describe 'the step set' do
    it 'dedups a step declared more than once, running it once' do
      calls = []
      klass = Class.new(described_class) do
        define_method(:a) { calls << :a }
        step :a
        step :a
      end

      klass.run

      expect(calls).to eq([:a])
    end

    it 'inherits parent steps and appends subclass steps, order-preserving' do
      parent = Class.new(described_class) { step :a }
      child = Class.new(parent) { step :b }

      expect(child.steps.map(&:name)).to eq(%i[a b])
      expect(parent.steps.map(&:name)).to eq(%i[a])
    end
  end
end
