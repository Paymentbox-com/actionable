# frozen_string_literal: true

require 'actionable/rails'

RSpec.describe 'Actionable::Rails transactional macro' do
  # A stub standing in for an ActiveRecord model: it records the transaction
  # lifecycle and mimics rollback-on-exception (AR rolls back then re-raises).
  let(:model) do
    Class.new do
      class << self
        attr_reader :opened, :committed, :rolled_back

        def transaction(**options)
          @opened = options
          @committed = false
          @rolled_back = false
          yield
          @committed = true
        rescue StandardError
          @rolled_back = true
          raise
        end
      end
    end
  end

  it 'commits when the action succeeds' do
    stub = model
    klass = Class.new(Actionable::Action) do
      transactional model: stub
      define_method(:go) { succeed }
      step :go
    end

    result = klass.run

    expect(result).to be_success
    expect(stub.committed).to be(true)
    expect(stub.rolled_back).to be(false)
  end

  it 'rolls back when the action records a failure' do
    stub = model
    klass = Class.new(Actionable::Action) do
      transactional model: stub
      define_method(:go) { fail!(:nope) }
      step :go
    end

    result = klass.run

    expect(result).to be_failure
    expect(result.code).to eq(:nope)
    expect(stub.rolled_back).to be(true)
    expect(stub.committed).to be(false)
  end

  it 'commits when the action skips (a skip is not a failure)' do
    stub = model
    klass = Class.new(Actionable::Action) do
      transactional model: stub
      define_method(:go) { skip!(:not_ready) }
      step :go
    end

    result = klass.run

    expect(result).to be_skipped
    expect(stub.committed).to be(true)
    expect(stub.rolled_back).to be(false)
  end

  it 'rolls back and propagates a raised exception' do
    stub = model
    klass = Class.new(Actionable::Action) do
      transactional model: stub
      define_method(:go) { raise ArgumentError, 'boom' }
      step :go
    end

    expect { klass.run }.to raise_error(ArgumentError, 'boom')
    expect(stub.rolled_back).to be(true)
  end

  it 'passes transaction options through to the model' do
    stub = model
    klass = Class.new(Actionable::Action) do
      transactional model: stub, requires_new: true
      define_method(:go) { succeed }
      step :go
    end

    klass.run

    expect(stub.opened).to eq(requires_new: true)
  end

  it 'resolves a Symbol model name to a constant' do
    stub_const('Widget', model)
    klass = Class.new(Actionable::Action) do
      transactional model: :widget
      define_method(:go) { succeed }
      step :go
    end

    klass.run

    expect(Widget.committed).to be(true)
  end

  it 'leaves non-transactional actions untouched' do
    klass = Class.new(Actionable::Action) do
      define_method(:go) { succeed }
      step :go
    end

    expect(klass.run).to be_success
  end
end
