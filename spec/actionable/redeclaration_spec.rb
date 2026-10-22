# frozen_string_literal: true

RSpec.describe Actionable::Action, 'redeclaring a step or hook' do
  it 'lets the last declaration of a step win, keeping its original position' do
    calls = []
    klass = Class.new(described_class) do
      define_method(:a) { calls << :a }
      define_method(:b) { calls << :b }
      define_method(:never?) { false }
      step :a, if: :never?
      step :b
      step :a
    end

    klass.run

    expect(calls).to eq(%i[a b])
    expect(klass.steps.map(&:name)).to eq(%i[a b])
    expect(klass.steps.first.options).to eq({})
  end

  it 'lets a later declaration add guards to an earlier one' do
    calls = []
    klass = Class.new(described_class) do
      define_method(:a) { calls << :a }
      step :a
      step :a, if: ->(_instance) { false }
    end

    klass.run

    expect(calls).to be_empty
  end

  it 'lets a subclass override an inherited step in place without touching the parent' do
    calls = []
    parent = Class.new(described_class) do
      define_method(:a) { calls << :a }
      define_method(:b) { calls << :b }
      step :a
      step :b
    end
    child = Class.new(parent) { step :a, if: ->(_instance) { false } }

    child.run
    expect(calls).to eq(%i[b])
    expect(child.steps.map(&:name)).to eq(%i[a b])

    calls.clear
    parent.run
    expect(calls).to eq(%i[a b])
    expect(parent.steps.first.options).to eq({})
  end

  it 'replaces a redeclared nested action step, keeping its position' do
    inner = Class.new(described_class) do
      output { required :token, :string }
      step :issue
      define_method(:issue) { @token = 'abc' }
    end
    seen = []
    klass = Class.new(described_class) do
      output { optional :token, :string }
      step inner, expose: []
      step :record
      step inner
      define_method(:record) { seen << @token }
    end

    klass.run

    expect(klass.steps.map(&:kind)).to eq(%i[action method])
    expect(seen).to eq(['abc'])
  end

  it 'replaces a redeclared case_step with the last block, keeping its position' do
    calls = []
    klass = Class.new(described_class) do
      define_method(:kind) { :x }
      define_method(:old) { calls << :old }
      define_method(:new_branch) { calls << :new }
      define_method(:after) { calls << :after }
      case_step(:kind) { on :x, :old }
      step :after
      case_step(:kind) { on :x, :new_branch }
    end

    klass.run

    expect(calls).to eq(%i[new after])
  end

  it 'keeps a method step and a case_step of the same name as two steps' do
    klass = Class.new(described_class) do
      step :kind
      case_step(:kind) { default :kind }
    end

    expect(klass.steps.map(&:kind)).to eq(%i[method case])
  end

  %i[on_success on_failure on_skip always].each do |hook|
    it "applies the same rule to #{hook} hooks" do
      calls = []
      klass = Class.new(described_class) do
        define_method(:work) do
          case hook
          when :on_failure then fail(:nope)
          when :on_skip then skip
          end
        end
        define_method(:first) { calls << :first }
        define_method(:second) { calls << :second }
        step :work
        __send__(hook, :first, if: ->(_instance) { false })
        __send__(hook, :second)
        __send__(hook, :first)
      end

      klass.run

      expect(calls).to eq(%i[first second])
    end
  end

  it 'lets a subclass override an inherited hook without touching the parent' do
    calls = []
    parent = Class.new(described_class) do
      step :work
      define_method(:work) { nil }
      define_method(:notify) { calls << :notify }
      on_success :notify
    end
    child = Class.new(parent) { on_success :notify, unless: ->(_instance) { true } }

    child.run
    expect(calls).to be_empty

    parent.run
    expect(calls).to eq(%i[notify])
  end
end
