# frozen_string_literal: true

# A named subclass so it has a name at `inherited` time (anonymous classes don't).
class RegistrySampleAction < Actionable::Action
end

RSpec.describe Actionable::Registry do
  it 'registers a named action subclass, retrievable by name' do
    expect(Actionable.registry['RegistrySampleAction']).to eq(RegistrySampleAction)
  end

  it 'returns nil for an unknown name' do
    expect(Actionable.registry['NoSuchAction']).to be_nil
  end

  it 'exposes read-only iteration' do
    registry = Actionable.registry

    expect(registry.keys).to include('RegistrySampleAction')
    expect(registry.values).to include(RegistrySampleAction)
    expect(registry.size).to be >= 1
    expect(registry).not_to be_empty

    collected = {}
    registry.each { |name, klass| collected[name] = klass }
    expect(collected['RegistrySampleAction']).to eq(RegistrySampleAction)
  end

  it 'does not register anonymous action subclasses' do
    anonymous = Class.new(Actionable::Action)

    expect(Actionable.registry.values).not_to include(anonymous)
  end
end
