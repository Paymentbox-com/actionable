# frozen_string_literal: true

require 'rbs'

# Named actions (the generator rejects anonymous classes).
class RbsSampleAction < Actionable::Action
  input do
    required :amount, :integer
    optional :name, :string
  end
  output do
    required :invoice, :string
    optional :paid, :boolean
    required :lines, :array, of: :string
  end
end

class RbsFreeFormAction < Actionable::Action
end

class RbsDeclaringAction < Actionable::Action
  fails :refused, kind: :rejected
  fails :not_found
  fails :invalid_input, kind: :invalid
end

class RbsSkippingAction < Actionable::Action
  skips :not_ready, retry: true
  skips :already_synced
end

class RbsBothAction < Actionable::Action
  fails :refused
  skips :not_ready
end

module RbsDemo
  class Namespaced < Actionable::Action
    output { required :id, :integer }
  end
end

RSpec.describe Actionable::RBS do
  describe '.generate' do
    subject(:rbs) { described_class.generate(RbsSampleAction) }

    it 'emits a typed .run signature from the input schema' do
      expect(rbs).to include('def self.run: (amount: ::Integer, ?name: ::String) -> Result')
    end

    it 'emits typed, nullability-aware output accessors' do
      expect(rbs).to include('attr_reader invoice: ::String')
      expect(rbs).to include('attr_reader paid: bool?')
      expect(rbs).to include('attr_reader lines: ::Array[::String?]')
    end

    it 'emits result-delegation methods for the declared output fields' do
      expect(rbs).to include('def invoice: () -> ::String')
      expect(rbs).to include('def paid: () -> bool?')
      expect(rbs).to include('def output: () -> Output')
    end

    it 'produces syntactically valid RBS' do
      expect { RBS::Parser.parse_signature(rbs) }.not_to raise_error
    end

    it 'uses (*untyped) and the base Result for a free-form action' do
      free_form = described_class.generate(RbsFreeFormAction)

      expect(free_form).to include('def self.run: (*untyped) -> ::Actionable::Result')
      expect(free_form).not_to include('class Output')
    end

    it 'lists the declared failure codes, plus the codes the gem emits, as a type alias' do
      declaring = described_class.generate(RbsDeclaringAction)

      expect(declaring).to include('type failure_code = :refused | :not_found | :invalid_input | :invalid_output')
      expect { RBS::Parser.parse_signature(declaring) }.not_to raise_error
    end

    it 'emits no failure_code alias for an action that declares no failures' do
      expect(rbs).not_to include('failure_code')
    end

    it 'lists the declared skip codes as a type alias' do
      skipping = described_class.generate(RbsSkippingAction)

      expect(skipping).to include('type skip_code = :not_ready | :already_synced')
      expect(skipping).not_to include('failure_code')
      expect { RBS::Parser.parse_signature(skipping) }.not_to raise_error
    end

    it 'emits both aliases, failures first, when an action declares both' do
      both = described_class.generate(RbsBothAction)

      expect(both).to include(
        "type failure_code = :refused | :invalid_input | :invalid_output\n  type skip_code = :not_ready\n"
      )
      expect { RBS::Parser.parse_signature(both) }.not_to raise_error
    end

    it 'emits no skip_code alias for an action that declares no skips' do
      expect(rbs).not_to include('skip_code')
      expect(described_class.generate(RbsDeclaringAction)).not_to include('skip_code')
    end

    it 'wraps a namespaced action in its module nesting' do
      namespaced = described_class.generate(RbsDemo::Namespaced)

      expect(namespaced).to match(/module RbsDemo\b/)
      expect(namespaced).to include('class Namespaced < ::Actionable::Action')
    end

    it 'rejects a non-action class and an anonymous class' do
      expect { described_class.generate(String) }.to raise_error(ArgumentError)
      expect { described_class.generate(Class.new(Actionable::Action)) }.to raise_error(ArgumentError)
    end
  end
end
