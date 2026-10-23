# frozen_string_literal: true

# These actions misplace verbs on purpose, and RuboCop's core cops read their
# `fail` as Kernel#fail (raise).
# rubocop:disable Actionable/VerbNotLast, Lint/UnreachableCode, Layout/EmptyLineAfterGuardClause

require 'open3'
require 'rbconfig'
require 'tempfile'

# The first-run check (owner ruling R5): a step or hook method that calls a
# non-bang recording verb with more code after it raises a DefinitionError
# instead of silently running on.
RSpec.describe 'the recording-verb position check' do
  it 'raises naming the class, method, file:line, verb and fix' do
    stub_const('LateFail', Class.new(Actionable::Action) do
      step :charge
      def charge
        fail :card_expired if expired?
        @charged = true
      end

      def expired? = true
    end)
    line = __LINE__ - 6

    expect { LateFail.run }.to raise_error(Actionable::DefinitionError) { |error|
      expect(error.message).to include('LateFail#charge', "#{__FILE__}:#{line}", '`fail`',
        'use fail! to stop here, or make it the method\'s last expression')
    }
  end

  it 'lists every offense in every step method' do
    action = Class.new(Actionable::Action) do
      step :one
      step :two
      def one
        skip :idle
        work
      end

      def two
        succeed
        work
      end

      def work = nil
    end

    expect { action.run }.to raise_error(Actionable::DefinitionError, /#one .*`skip`.*\n.*#two .*`succeed`/)
  end

  it 'checks fail_with like fail (owner ruling R10)' do
    action = Class.new(Actionable::Action) do
      step :validate
      def validate
        fail_with(Struct.new(:errors).new([]), code: :bad_shape)
        work
      end

      def work = nil
    end

    expect { action.run }.to raise_error(Actionable::DefinitionError, /#validate .*`fail_with`.*use fail_with! to stop here/)
  end

  it 'runs an action whose verbs are all in tail position' do
    action = Class.new(Actionable::Action) do
      step :check
      step :finish
      def check
        prepare
        fail :bad if bad?
      end

      def finish = succeed('done')
      def prepare = nil
      def bad? = false
    end

    expect(action.run.message).to eq('done')
  end

  %i[on_success on_failure on_skip always].each do |hook|
    it "checks #{hook} hook methods" do
      action = Class.new(Actionable::Action) do
        step :outcome
        public_send(hook, :hook)
        define_method(:outcome) { nil }
        def hook
          fail :late
          nil
        end
      end

      expect { action.run }.to raise_error(Actionable::DefinitionError, /#hook/)
    end
  end

  it 'checks case_step method branch targets but not the value source' do
    action = Class.new(Actionable::Action) do
      case_step :status do
        on :bad, :handle_bad
      end

      def status
        skip :never_mind
        :bad
      end

      def handle_bad
        fail :bad
        nil
      end
    end

    expect { action.run }.to raise_error(Actionable::DefinitionError) { |error|
      expect(error.message).to include('#handle_bad')
      expect(error.message).not_to include('#status')
    }
  end

  it 'checks a subclass against its own method overrides' do
    parent = Class.new(Actionable::Action) do
      step :work
      def work = succeed
    end
    child = Class.new(parent) do
      def work
        succeed
        nil
      end
    end

    expect(parent.run).to be_success
    expect { child.run }.to raise_error(Actionable::DefinitionError, /#work/)
  end

  it 'checks once per class: a later run does not read the source again' do
    action = Class.new(Actionable::Action) do
      step :work
      def work = succeed
    end
    action.run
    allow(Actionable::VerbPosition).to receive(:method_offenses).and_call_original

    action.run

    expect(Actionable::VerbPosition).not_to have_received(:method_offenses)
  end

  it 'raises on every run until the method is fixed' do
    action = Class.new(Actionable::Action) do
      step :work
      def work
        succeed
        nil
      end
    end

    2.times { expect { action.run }.to raise_error(Actionable::DefinitionError) }
  end

  it 'skips a method with no source file (eval)' do
    action = Class.new(Actionable::Action) { step :work }
    # A missing file, and a real file whose line 1 holds no `def other`.
    action.class_eval("def work\n  fail :x\n  nil\nend\n", __FILE__.sub('.rb', '_missing.rb'), 1) # rubocop:disable Style/EvalWithLocation
    action.class_eval("def other\n  fail :x\n  nil\nend\n", __FILE__, 1) # rubocop:disable Style/EvalWithLocation

    expect(action.run).to be_failure
  end

  it 'skips a method whose file does not parse cleanly (e.g. Markdown, as doctests eval it)' do
    source = "def work\n  fail :x\n  nil\nend\n"
    Tempfile.create(['usage', '.md']) do |file|
      file.write("#{source}\n```\nNot Ruby: (\n")
      file.flush
      action = Class.new(Actionable::Action) { step :work }
      action.class_eval(source, file.path, 1)

      expect(action.run).to be_failure
    end
  end

  it 'checks a step that names an alias_method of the offending def' do
    action = Class.new(Actionable::Action) do
      step :charge
      def do_charge
        fail :late
        @charged = true
      end
      alias_method :charge, :do_charge
    end

    expect { action.run }.to raise_error(Actionable::DefinitionError, /#charge .*`fail`/)
  end

  it 'skips a method defined with define_method' do
    action = Class.new(Actionable::Action) do
      step :work
      define_method(:work) do
        fail :x
        nil
      end
    end

    expect(action.run).to be_failure
  end

  describe 'the production opt-out (Actionable.verb_position_check)' do
    around do |example|
      example.run
    ensure
      Actionable.verb_position_check = true
    end

    let(:late_fail) do
      Class.new(Actionable::Action) do
        step :work
        def work
          fail :x
          nil
        end
      end
    end

    it 'is on by default' do
      expect(Actionable.verb_position_check?).to be(true)
    end

    it 'runs an action unchecked when off, without reading any source' do
      allow(Actionable::VerbPosition).to receive(:method_offenses).and_call_original
      Actionable.verb_position_check = false

      expect(late_fail.run).to be_failure
      expect(Actionable::VerbPosition).not_to have_received(:method_offenses)
    end

    it 'does not cache a class run while off as checked: turning it back on checks it' do
      Actionable.verb_position_check = false
      late_fail.run
      Actionable.verb_position_check = true

      expect { late_fail.run }.to raise_error(Actionable::DefinitionError, /#work/)
    end

    it 'keeps the code check on' do
      Actionable.verb_position_check = false
      action = Class.new(Actionable::Action) do
        step :work
        def work = fail!('card expired')
      end

      expect { action.run }.to raise_error(ArgumentError, /not an identifier/)
    end

    it 'does not load Prism when off' do
      script = <<~RUBY
        require 'actionable'
        Actionable.verb_position_check = ARGV.first == 'on'
        class LateFail < Actionable::Action
          step :work
          def work
            fail :x
            nil
          end
        end
        outcome = begin
          LateFail.run.code
        rescue Actionable::DefinitionError
          :raised
        end
        print [outcome, defined?(Prism) ? :prism : :no_prism].inspect
      RUBY
      outputs = Tempfile.create(['late_fail', '.rb']) do |file|
        file.write(script)
        file.flush
        %w[off on].map do |state|
          Open3.capture2e(RbConfig.ruby, '-Ilib', file.path, state, chdir: File.expand_path('../..', __dir__)).first
        end
      end

      expect(outputs).to eq(['[:x, :no_prism]', '[:raised, :prism]'])
    end
  end

  context 'when Prism cannot be loaded (Ruby 3.2 without the gem)' do
    around do |example|
      had = Actionable::VerbPosition.instance_variable_defined?(:@prism)
      saved = Actionable::VerbPosition.instance_variable_get(:@prism)
      Actionable::VerbPosition.remove_instance_variable(:@prism) if had
      example.run
    ensure
      Actionable::VerbPosition.remove_instance_variable(:@prism) if Actionable::VerbPosition.instance_variable_defined?(:@prism)
      Actionable::VerbPosition.instance_variable_set(:@prism, saved) if had
    end

    it 'runs the action unchecked' do
      allow(Actionable::VerbPosition).to receive(:require).and_call_original
      allow(Actionable::VerbPosition).to receive(:require).with('prism').and_raise(LoadError)
      action = Class.new(Actionable::Action) do
        step :work
        def work
          fail :x
          nil
        end
      end

      expect(Actionable::VerbPosition.prism?).to be(false)
      expect(action.run).to be_failure
    end
  end
end
# rubocop:enable Actionable/VerbNotLast, Lint/UnreachableCode, Layout/EmptyLineAfterGuardClause
