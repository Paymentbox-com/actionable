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

RSpec.describe 'typed outcome output (decision D23)' do
  def action(typed: true, &body)
    Class.new(Actionable::Action) do
      typed_outcomes if typed
      output { optional :id, :integer }
      class_eval(&body)
    end
  end

  describe 'a skip whose code declares an output schema' do
    let(:activate) do
      action do
        skips(:already_active) { required :id, :integer }
        input { optional :id, :value }
        step :check

        def check
          @id = 99
          input.id ? skip!(:already_active, nil, id: input.id) : skip!(:already_active)
        end
      end
    end

    it 'carries its kwargs as that schema' do
      result = activate.run(id: '7')

      expect([result.code, result.output.class, result.id]).to eq([:already_active, activate.skip_output_schema(:already_active), 7])
    end

    it 'fails as invalid_output when the kwargs break the schema' do
      result = activate.run(id: 'seven')

      expect([result.code, result.errors.to_h]).to match([:invalid_output, hash_including(:id)])
    end

    it 'never fills a field from an instance variable' do
      expect(activate.run.code).to eq(:invalid_output)
    end

    it 'is validated even when typed outcomes are off' do
      untyped = action(typed: false) do
        skips(:idle) { required :id, :integer }
        step(:idle)
        def idle = skip!(:idle)
      end

      expect(untyped.run.code).to eq(:invalid_output)
    end

    it 'keeps its output through a hook that runs after it' do
      hooked = action do
        skips(:idle) { required :id, :integer }
        step :idle
        always :note
        def idle = skip!(:idle, nil, id: 3)
        def note = nil
      end

      expect(hooked.run.output.id).to eq(3)
    end
  end

  describe 'a skip whose code declares no output schema' do
    let(:body) do
      proc do
        skips :idle
        step :idle

        def idle
          @id = 5
          skip!(:idle, nil, id: 5)
        end
      end
    end

    it 'carries an empty output when typed outcomes are on' do
      expect(action(&body).run.output).to eq({})
    end

    it 'still captures into the success schema when they are off' do
      expect(action(typed: false, &body).run.output.id).to eq(5)
    end
  end

  describe 'a failure whose code declares no output schema' do
    it 'carries an empty output when typed outcomes are on, whatever the steps left behind' do
      failing = action do
        fails :refused
        step :refuse

        def refuse
          @id = 5
          fail!(:refused)
        end
      end

      expect(failing.run.output).to eq({})
    end
  end

  describe 'a failure the gem builds' do
    it 'keeps the invalid success output on invalid_output through a hook, for debugging' do
      broken = action do
        output { required :id, :integer }
        step(:finish)
        always :note
        def finish = succeed(nil, id: 'x')
        def note = nil
      end

      expect(broken.run.output).to be_a(broken.output_schema)
    end
  end
end
