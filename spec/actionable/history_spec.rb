# frozen_string_literal: true

RSpec.describe 'Actionable history and measurement' do
  describe 'measure :none (default)' do
    it 'records no history' do
      klass = Class.new(Actionable::Action) do
        define_method(:a) { nil }
        step :a
      end

      expect(klass.run.history).to be_empty
    end
  end

  describe 'measure :all' do
    it 'records each main step with its name, :main section, and a duration' do
      klass = Class.new(Actionable::Action) do
        measure :all
        define_method(:a) { nil }
        define_method(:b) { nil }
        step :a
        step :b
      end

      history = klass.run.history

      expect(history.steps.map(&:name)).to eq(%i[a b])
      expect(history.steps.map(&:section)).to eq(%i[main main])
      expect(history.steps).to all(have_attributes(duration: be >= 0))
      expect(history.took).to be >= 0
    end

    it 'records the result code only on the step that set it' do
      klass = Class.new(Actionable::Action) do
        measure :all
        define_method(:noop) { nil }
        define_method(:stop) { fail(:nope) }
        step :noop
        step :stop
      end

      history = klass.run.history

      expect(history.steps.map(&:name)).to eq(%i[noop stop])
      expect(history.steps.map(&:code)).to eq([nil, :nope])
    end

    it 'tags lifecycle hooks with their section' do
      klass = Class.new(Actionable::Action) do
        measure :all
        define_method(:main_step) { nil }
        define_method(:cleanup) { nil }
        define_method(:log) { nil }
        step :main_step
        on_success :cleanup
        always :log
      end

      history = klass.run.history

      expect(history.steps.map { |s| [s.section, s.name] }).to eq(
        [%i[main main_step], %i[success cleanup], %i[always log]]
      )
    end
  end

  describe 'cascade into nested actions' do
    it 'records a nested action\'s history even when the child does not opt in' do
      child = Class.new(Actionable::Action) do
        define_method(:c1) { nil }
        step :c1
      end
      parent = Class.new(Actionable::Action) do
        measure :all
        step child
      end

      action_step = parent.run.history.steps.first

      expect(action_step.nested).to be_a(Actionable::History)
      expect(action_step.nested.steps.map(&:name)).to eq(%i[c1])
    end
  end

  describe 'serialization via Oj' do
    it 'renders an array of step hashes' do
      klass = Class.new(Actionable::Action) do
        measure :all
        define_method(:a) { nil }
        step :a
      end

      loaded = Oj.load(klass.run.history.to_json)

      expect(loaded).to be_an(Array)
      expect(loaded.first['name']).to eq('a')
      expect(loaded.first['section']).to eq('main')
      expect(loaded.first).to have_key('duration')
    end
  end
end
