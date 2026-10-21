# frozen_string_literal: true

RSpec.describe 'typed outcomes (decision D23)' do
  describe '.typed_outcomes' do
    it 'is off by default' do
      expect(Class.new(Actionable::Action).typed_outcomes?).to be(false)
    end

    it 'turns on for the action that declares it' do
      expect(Class.new(Actionable::Action) { typed_outcomes }.typed_outcomes?).to be(true)
    end

    it 'is inherited, so a base class can turn it on for its descendants' do
      base = Class.new(Actionable::Action) { typed_outcomes }

      expect(Class.new(base).typed_outcomes?).to be(true)
    end

    it 'can be turned off again by a subclass without touching its parent' do
      base = Class.new(Actionable::Action) { typed_outcomes }
      child = Class.new(base) { typed_outcomes enabled: false }

      expect([base.typed_outcomes?, child.typed_outcomes?]).to eq([true, false])
    end
  end

  describe 'a per-code output schema' do
    let(:action) do
      Class.new(Actionable::Action) do
        skips :already_active, 'already on', retry: false do
          required :id, :integer
        end
        skips :not_ready
        fails :refused, kind: :rejected do
          optional :reason, :string
        end
      end
    end

    it 'is declared with a block on skips' do
      expect(action.skip_output_schema(:already_active).attribute_names).to eq([:id])
    end

    it 'is declared with a block on fails' do
      expect(action.failure_output_schema(:refused).attribute_names).to eq([:reason])
    end

    it 'is nil for a code declared without a block' do
      expect(action.skip_output_schema(:not_ready)).to be_nil
    end

    it 'is nil for a code that is not declared' do
      expect(action.failure_output_schema(:other)).to be_nil
    end

    it 'accepts a String code' do
      expect(action.skip_output_schema('already_active')).to eq(action.skip_output_schema(:already_active))
    end

    it 'leaves the declared message and metadata as they were' do
      expect(action.skip_declarations[:already_active]).to include(message: 'already on', metadata: {retry: false})
    end

    it 'refuses a reserved field name, like the success output does' do
      expect { Class.new(Actionable::Action) { skips(:idle) { required :code, :symbol } } }
        .to raise_error(Actionable::DefinitionError, /:code/)
    end

    it 'is inherited by a subclass' do
      expect(Class.new(action).skip_output_schema(:already_active)).to eq(action.skip_output_schema(:already_active))
    end

    it 'goes when a subclass redeclares the code without a block' do
      child = Class.new(action) { skips :already_active }

      expect([child.skip_output_schema(:already_active), action.skip_output_schema(:already_active)])
        .to eq([nil, action.skip_output_schema(:already_active)])
    end

    it 'shows in describe as the fields of each code that has one' do
      expect(action.describe.dig(:skips, :already_active, :output)).to eq(action.skip_output_schema(:already_active).metadata.to_h)
    end

    it 'shows nothing in describe for a code without one' do
      expect(action.describe.dig(:skips, :not_ready)).not_to have_key(:output)
    end
  end
end
