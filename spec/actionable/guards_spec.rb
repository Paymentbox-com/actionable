# frozen_string_literal: true

RSpec.describe 'Actionable definition guards' do
  it 'Actionable::DefinitionError is an Actionable::Error' do
    expect(Actionable::DefinitionError.ancestors).to include(Actionable::Error)
  end

  describe 'reserved output field names (definition time)' do
    it 'rejects an output field that shadows a result attribute' do
      expect do
        Class.new(Actionable::Action) { output { required :message, :string } }
      end.to raise_error(Actionable::DefinitionError, /message/)
    end

    it 'rejects an output field that collides with a reserved ivar' do
      expect do
        Class.new(Actionable::Action) { output { required :result, :string } }
      end.to raise_error(Actionable::DefinitionError, /result/)
    end

    it 'allows ordinary output field names' do
      expect do
        Class.new(Actionable::Action) { output { required :invoice, :string } }
      end.not_to raise_error
    end

    it 'does not guard input field names (they do not collide)' do
      expect do
        Class.new(Actionable::Action) { input { required :code, :symbol } }
      end.not_to raise_error
    end
  end

  describe 'missing step methods (run start)' do
    it 'raises when a declared method step is not implemented' do
      klass = Class.new(Actionable::Action) { step :ghost }

      expect { klass.run }.to raise_error(Actionable::DefinitionError, /ghost/)
    end

    it 'raises when a lifecycle hook method is not implemented' do
      klass = Class.new(Actionable::Action) do
        define_method(:work) { nil }
        step :work
        on_success :notify_missing
      end

      expect { klass.run }.to raise_error(Actionable::DefinitionError, /notify_missing/)
    end

    it 'raises when a case step value source is not implemented' do
      klass = Class.new(Actionable::Action) do
        case_step :status do
          on 'a', :handle_a
        end
        define_method(:handle_a) { nil }
      end

      expect { klass.run }.to raise_error(Actionable::DefinitionError, /status/)
    end

    it 'does not raise when every step method is implemented' do
      klass = Class.new(Actionable::Action) do
        define_method(:work) { nil }
        step :work
      end

      expect { klass.run }.not_to raise_error
    end
  end
end
