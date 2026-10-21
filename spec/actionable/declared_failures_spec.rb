# frozen_string_literal: true

RSpec.describe 'declared failures (fails)' do
  let(:charge) do
    Class.new(Actionable::Action) do
      fails :refused, 'the card was refused', kind: :rejected
      fails :not_found, kind: :not_found

      input { required :outcome, :symbol }
      step :decide

      def decide
        case input.outcome
        when :refused then fail!(:refused)
        when :refused_with_message then fail!(:refused, 'card 4242 refused')
        when :not_found then fail(:not_found, nil, card: 'is unknown')
        end
      end
    end
  end

  describe '.declared_failures' do
    it 'maps each declared code to its metadata' do
      expect(charge.declared_failures).to eq(refused: {kind: :rejected}, not_found: {kind: :not_found})
    end

    it 'is empty for an action that declares none' do
      expect(Class.new(Actionable::Action).declared_failures).to eq({})
    end

    it 'accepts a String code as its Symbol' do
      action = Class.new(Actionable::Action) { fails 'gone' }

      expect(action.declared_failures).to eq(gone: {})
    end

    it 'lets a redeclared code replace its metadata' do
      action = Class.new(Actionable::Action) do
        fails :refused, kind: :rejected
        fails :refused, kind: :conflict
      end

      expect(action.declared_failures).to eq(refused: {kind: :conflict})
    end
  end

  describe 'inheritance' do
    it 'gives a subclass its parent declarations, which it can extend' do
      child = Class.new(charge) { fails :expired, kind: :rejected }

      expect(child.declared_failures.keys).to eq(%i[refused not_found expired])
    end

    it 'never mutates the parent when the subclass declares more' do
      Class.new(charge) { fails :expired, kind: :rejected }

      expect(charge.declared_failures.keys).to eq(%i[refused not_found])
    end
  end

  describe 'the failure result' do
    it 'carries the metadata of its declared code' do
      result = charge.run(outcome: :refused)

      expect(result.code).to eq(:refused)
      expect(result.metadata).to eq(kind: :rejected)
    end

    it 'uses the declared message when fail gives none' do
      expect(charge.run(outcome: :refused).message).to eq('the card was refused')
    end

    it 'keeps the message fail gives over the declared one' do
      expect(charge.run(outcome: :refused_with_message).message).to eq('card 4242 refused')
    end

    it 'keeps errors from fail beside the metadata' do
      result = charge.run(outcome: :not_found)

      expect(result.metadata).to eq(kind: :not_found)
      expect(result.errors[:card]).to eq(['is unknown'])
    end

    it 'defaults metadata to an empty Hash' do
      expect(Actionable::Failure.new(code: :nope).metadata).to eq({})
    end

    it 'attaches declared metadata to fail_with' do
      shape = Class.new(FieldStruct::Base) { required :name, :string }
      action = Class.new(Actionable::Action) do
        fails :invalid_event, kind: :invalid
        step :check
        define_method(:check) { fail_with(shape.new, code: :invalid_event) }
      end

      result = action.run

      expect(result.metadata).to eq(kind: :invalid)
      expect(result.errors[:name]).not_to be_empty
    end

    it 'shows the metadata in to_h' do
      expect(charge.run(outcome: :refused).to_h).to include(metadata: {kind: :rejected})
    end
  end

  describe 'codes the gem emits itself' do
    it 'attach declared metadata to an :invalid_input failure' do
      action = Class.new(Actionable::Action) do
        fails :invalid_input, kind: :invalid
        input { required :amount, :integer }
      end

      expect(action.run.metadata).to eq(kind: :invalid)
    end

    it 'attach declared metadata to an :invalid_output failure' do
      action = Class.new(Actionable::Action) do
        fails :invalid_output, kind: :internal
        output { required :invoice, :string }
      end

      result = action.run

      expect(result.code).to eq(:invalid_output)
      expect(result.metadata).to eq(kind: :internal)
    end

    it 'attach declared metadata to an unmatched discriminator' do
      shape = Class.new(FieldStruct::Base) { required :type, :string }
      action = Class.new(Actionable::Action) do
        fails :invalid_input, kind: :invalid
        input_for(:type) { on 'sale', shape }
      end

      expect(action.run(type: 'refund').metadata).to eq(kind: :invalid)
    end

    it 'carry no metadata when the action declares none for them' do
      action = Class.new(Actionable::Action) { input { required :amount, :integer } }

      expect(action.run.metadata).to eq({})
    end
  end

  describe 'fail keyword arguments' do
    it 'binds an error named like a metadata key to errors, never to metadata' do
      action = Class.new(Actionable::Action) do
        fails :invalid, kind: :invalid
        step :check
        def check = fail(:invalid, nil, kind: 'is not a known kind')
      end

      result = action.run

      expect(result.metadata).to eq(kind: :invalid)
      expect(result.errors[:kind]).to eq(['is not a known kind'])
    end
  end

  it 'reserves metadata as an output field name' do
    expect { Class.new(Actionable::Action) { output { optional :metadata, :value } } }
      .to raise_error(Actionable::DefinitionError, /:metadata/)
  end
end
