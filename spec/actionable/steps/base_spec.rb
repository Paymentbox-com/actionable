# frozen_string_literal: true

RSpec.describe Actionable::Steps::Base do
  # A minimal stand-in for an action instance, with a private predicate so
  # the specs prove guards may be private.
  let(:fake_class) do
    Class.new do
      def initialize(ready: true)
        @ready = ready
      end

      private

      def ready?
        @ready
      end
    end
  end
  let(:ready) { fake_class.new(ready: true) }
  let(:not_ready) { fake_class.new(ready: false) }

  describe 'identity (Set dedup keyed by [type, name])' do
    it 'treats same-type, same-name steps as equal and dedups them in a Set' do
      a = Actionable::Steps::Method.new(:save)
      b = Actionable::Steps::Method.new(:save)

      expect(a).to eq(b)
      expect(a).to eql(b)
      expect(a.hash).to eq(b.hash)
      expect(Set.new([a, b]).size).to eq(1)
    end

    it 'distinguishes steps with different names' do
      expect(Actionable::Steps::Method.new(:a)).not_to eq(Actionable::Steps::Method.new(:b))
    end

    it 'distinguishes different step types that share a name' do
      method = Actionable::Steps::Method.new(:run)
      base = described_class.new(:run)

      expect(method).not_to eq(base)
      expect(Set.new([method, base]).size).to eq(2)
    end
  end

  describe 'skip logic' do
    it 'does not skip when no guard is given' do
      expect(Actionable::Steps::Method.new(:x).skip?(ready)).to be(false)
    end

    it ':if with a Symbol skips when the (possibly private) predicate is falsey' do
      step = Actionable::Steps::Method.new(:x, if: :ready?)

      expect(step.skip?(ready)).to be(false)
      expect(step.skip?(not_ready)).to be(true)
    end

    it ':unless with a Symbol skips when the predicate is truthy' do
      step = Actionable::Steps::Method.new(:x, unless: :ready?)

      expect(step.skip?(ready)).to be(true)
      expect(step.skip?(not_ready)).to be(false)
    end

    it ':if with a callable is passed the instance' do
      step = Actionable::Steps::Method.new(:x, if: ->(instance) { instance.equal?(ready) })

      expect(step.skip?(ready)).to be(false)
      expect(step.skip?(not_ready)).to be(true)
    end

    it 'skips when either :if or :unless says to' do
      step = Actionable::Steps::Method.new(:x, if: :ready?, unless: :ready?)

      expect(step.skip?(ready)).to be(true)
      expect(step.skip?(not_ready)).to be(true)
    end
  end

  it 'leaves #call abstract on the base' do
    expect { described_class.new(:x).call(ready) }.to raise_error(NotImplementedError)
  end
end
