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

# Named, so the generated result classes have names to check.
class TypedOutcomeSample < Actionable::Action
  typed_outcomes
  fails :refused
  skips :idle
  input { required :mode, :symbol }
  step :decide

  def decide
    case input.mode
    when :refuse then fail!(:refused, 'no', card: 'declined')
    when :idle then skip!(:idle)
    end
  end
end

class TypedOutcomeChild < TypedOutcomeSample
end

RSpec.describe 'typed outcome result classes (decision D23)' do
  it 'names one result class per outcome inside the action' do
    expect([TypedOutcomeSample::Success, TypedOutcomeSample::Failure, TypedOutcomeSample::Skipped].map(&:name))
      .to eq(%w[TypedOutcomeSample::Success TypedOutcomeSample::Failure TypedOutcomeSample::Skipped])
  end

  it 'makes each one the gem result class it stands for' do
    expect([TypedOutcomeSample::Success.superclass, TypedOutcomeSample::Failure.superclass, TypedOutcomeSample::Skipped.superclass])
      .to eq([Actionable::Success, Actionable::Failure, Actionable::Skipped])
  end

  it 'returns a success as the action’s own Success' do
    expect(TypedOutcomeSample.run(mode: :go)).to be_an_instance_of(TypedOutcomeSample::Success)
  end

  it 'returns a skip as the action’s own Skipped' do
    expect(TypedOutcomeSample.run(mode: :idle)).to be_an_instance_of(TypedOutcomeSample::Skipped)
  end

  it 'returns a failure as the action’s own Failure, with its message and errors intact' do
    result = TypedOutcomeSample.run(mode: :refuse)

    expect([result.class, result.code, result.message, result.errors.to_h])
      .to eq([TypedOutcomeSample::Failure, :refused, 'no', {card: ['declined']}])
  end

  it 'returns an input failure as the action’s own Failure' do
    expect(TypedOutcomeSample.run(mode: nil)).to be_an_instance_of(TypedOutcomeSample::Failure)
  end

  it 'gives a subclass its own classes, each a kind of its parent’s' do
    expect([TypedOutcomeChild::Success.superclass, TypedOutcomeChild.run(mode: :go).class])
      .to eq([TypedOutcomeSample::Success, TypedOutcomeChild::Success])
  end

  it 'defines none for an action without typed outcomes' do
    expect(Class.new(Actionable::Action).const_defined?(:Success, false)).to be(false)
  end

  it 'returns the gem classes for an action without typed outcomes' do
    plain = Class.new(Actionable::Action) do
      step :go
      def go = nil
    end

    expect(plain.run).to be_an_instance_of(Actionable::Success)
  end

  it 'refuses an action whose own constant is already named like one' do
    clashing = Class.new(Actionable::Action) { const_set(:Failure, Class.new) }

    expect { clashing.typed_outcomes }.to raise_error(Actionable::DefinitionError, /Failure/)
  end

  it 'turns a typed child’s failure into the parent’s own Failure when it crosses' do
    parent = Class.new(Actionable::Action) do
      typed_outcomes
      fails :refused, kind: :rejected
      step :choose
      step TypedOutcomeSample, input: [:mode]
      def choose = @mode = :refuse
    end

    result = parent.run

    expect([result.class, result.code, result.metadata]).to eq([parent::Failure, :refused, {kind: :rejected}])
  end

  it 'leaves a host’s own result subclass as it is' do
    host_failure = Class.new(Actionable::Failure)
    action = Class.new(Actionable::Action) do
      typed_outcomes
      step :refuse
      define_method(:refuse) { @result = host_failure.new(code: :refused) }
    end

    expect(action.run).to be_an_instance_of(host_failure)
  end
end

RSpec.describe 'typed failure output (decision D23)' do
  let(:form) { Struct.new(:name) }

  def failing(typed: true, &body)
    Class.new(Actionable::Action) do
      typed_outcomes if typed
      fails(:invalid) { required :form_record, :value }
      class_eval(&body)
    end
  end

  it 'takes its output from the output: keyword' do
    record = form.new('x')
    action = failing do
      step(:check)
      define_method(:check) { fail!(:invalid, 'bad', output: {form_record: record}, name: 'blank') }
    end

    result = action.run

    expect([result.code, result.form_record, result.errors.to_h]).to eq([:invalid, record, {name: ['blank']}])
  end

  it 'fails as invalid_output when the output breaks the code’s schema' do
    action = failing do
      step(:check)
      def check = fail!(:invalid)
    end

    expect(action.run.code).to eq(:invalid_output)
  end

  it 'takes output: on fail_with too' do
    record = form.new('x')
    action = failing do
      step(:check)
      define_method(:check) { fail_with!(Actionable::Success.new, output: {form_record: record}) }
    end

    expect(action.run.form_record).to eq(record)
  end

  it 'leaves output: an ordinary error on fail when typed outcomes are off' do
    action = Class.new(Actionable::Action) do
      step(:check)
      def check = fail!(:invalid, nil, output: 'is wrong')
    end

    expect(action.run.errors.to_h).to eq(output: ['is wrong'])
  end

  it 'refuses output: on fail_with when typed outcomes are off' do
    action = Class.new(Actionable::Action) do
      step(:check)
      def check = fail_with!(Actionable::Success.new, output: {})
    end

    expect { action.run }.to raise_error(ArgumentError, /typed_outcomes/)
  end

  describe 'a nested failure that crosses' do
    let(:child) do
      Class.new(Actionable::Action) do
        typed_outcomes
        fails(:refused) do
          required :reason, :string
          optional :extra, :integer
        end
        step(:refuse)
        def refuse = fail!(:refused, nil, output: {reason: 'card', extra: 1})
      end
    end

    it 'is held to the parent’s schema for its code, not the child’s' do
      inner = child
      parent = Class.new(Actionable::Action) do
        typed_outcomes
        fails(:refused) { required :reason, :string }
        step inner
      end

      result = parent.run

      expect([result.output.class, result.reason]).to eq([parent.failure_output_schema(:refused), 'card'])
    end

    it 'fails the parent as invalid_output when it breaks the parent’s schema' do
      inner = child
      parent = Class.new(Actionable::Action) do
        typed_outcomes
        fails(:refused) { required :card_id, :integer }
        step inner
      end

      expect(parent.run.code).to eq(:invalid_output)
    end

    it 'carries no output into a parent whose code declares no schema' do
      inner = child
      parent = Class.new(Actionable::Action) do
        typed_outcomes
        fails :refused
        step inner
      end

      expect(parent.run.output).to eq({})
    end

    it 'still needs the parent to declare its code' do
      inner = child
      parent = Class.new(Actionable::Action) do
        typed_outcomes
        fails :other
        step inner
      end

      expect { parent.run }.to raise_error(Actionable::DefinitionError, /refused/)
    end
  end
end

RSpec.describe 'typed outcome conversion (decision D23)' do
  it 'copies a failure’s errors once, not again on top of those the rebuild finds' do
    broken = Class.new(Actionable::Action) do
      typed_outcomes
      output { required :id, :integer }
      step(:finish)
      def finish = succeed(nil, id: 'x')
    end

    expect(broken.run.errors[:output]).to eq(['is invalid'])
  end
end
