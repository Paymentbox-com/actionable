# frozen_string_literal: true

require 'active_record'
require 'actionable/rails'

# Real ActiveRecord on in-memory SQLite: "after the outermost commit" and
# "never after a rollback" are transaction behaviour a stub model cannot show.
RSpec.describe 'Actionable::Rails after_commit hooks on ActiveRecord' do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define { create_table(:ac_widgets) { |t| t.string :name } }
    Object.const_set(:AcWidget, Class.new(ActiveRecord::Base) { self.table_name = 'ac_widgets' })
  end

  after(:all) do
    Object.send(:remove_const, :AcWidget)
    ActiveRecord::Base.remove_connection
  end

  let(:log) { [] }

  before { AcWidget.delete_all }

  # An action that writes a row, then (unless +fail_with+ is given) succeeds.
  # Its after_commit hook logs its name and whether a transaction was still open.
  def action(label, log, transactional: true, fail_with: nil, **hook_options)
    Class.new(Actionable::Action) do
      transactional model: AcWidget if transactional
      define_method(:write) { AcWidget.create!(name: label) }
      define_method(:check) { fail!(fail_with) if fail_with }
      define_method(:notify) { log << [label, AcWidget.connection.transaction_open?] }
      step :write
      step :check
      after_commit :notify, **hook_options
    end
  end

  it 'runs after the commit of a top-level transactional success' do
    result = action('top', log).run

    expect(result).to be_success
    expect(log).to eq([['top', false]])
  end

  it 'runs only after the outer transaction commits, not at the action savepoint' do
    AcWidget.transaction do
      action('inner', log).run
      expect(log).to eq([])
    end

    expect(log).to eq([['inner', false]])
  end

  it 'never runs when the outer transaction rolls back' do
    AcWidget.transaction do
      action('inner', log).run
      raise ActiveRecord::Rollback
    end

    expect(log).to eq([])
    expect(AcWidget.count).to eq(0)
  end

  it 'never runs when the action fails' do
    result = action('failing', log, fail_with: :nope).run

    expect(result.code).to eq(:nope)
    expect(log).to eq([])
  end

  it 'never runs when the action is skipped' do
    klass = Class.new(Actionable::Action) do
      define_method(:nothing) { skip!(:nothing_to_do) }
      define_method(:notify) { raise 'must not run' }
      step :nothing
      after_commit :notify
    end

    expect(klass.run).to be_skipped
  end

  it 'runs immediately after a non-transactional run outside any transaction' do
    result = action('plain', log, transactional: false).run

    expect(result).to be_success
    expect(log).to eq([['plain', false]])
  end

  it 'waits for the outer transaction when a non-transactional action runs inside one' do
    AcWidget.transaction do
      action('plain', log, transactional: false).run
      expect(log).to eq([])
    end

    expect(log).to eq([['plain', false]])
  end

  it 'runs each nested action hook once, child first, after the outermost commit' do
    log = self.log
    child = action('child', log)
    parent = Class.new(Actionable::Action) do
      transactional model: AcWidget
      define_method(:notify) { log << ['parent', AcWidget.connection.transaction_open?] }
      step child
      after_commit :notify
    end

    AcWidget.transaction do
      parent.run
      expect(log).to eq([])
    end

    expect(log).to eq([['child', false], ['parent', false]])
  end

  it "drops a successful child's hook when the transactional parent then fails" do
    child = action('child', log)
    parent = Class.new(Actionable::Action) do
      transactional model: AcWidget
      define_method(:boom) { fail!(:parent_failed) }
      step child
      step :boom
    end

    AcWidget.transaction { parent.run }

    expect(log).to eq([])
    expect(AcWidget.count).to eq(0)
  end

  it 'accepts a nested action as the hook target, run after the commit' do
    log = self.log
    notifier = Class.new(Actionable::Action) do
      define_method(:initialize) { |widget_name:| @widget_name = widget_name }
      define_method(:call_out) { log << [:notifier, @widget_name, AcWidget.connection.transaction_open?] }
      step :call_out
    end
    klass = Class.new(Actionable::Action) do
      transactional model: AcWidget
      define_method(:write) { @widget_name = AcWidget.create!(name: 'w').name }
      step :write
      after_commit notifier, input: %i[widget_name]
    end

    AcWidget.transaction do
      klass.run
      expect(log).to eq([])
    end

    expect(log).to eq([[:notifier, 'w', false]])
  end

  it 'honours :if / :unless guards' do
    log = self.log
    klass = Class.new(Actionable::Action) do
      define_method(:work) { nil }
      define_method(:yes) { log << :yes }
      define_method(:no) { log << :no }
      define_method(:enabled?) { false }
      step :work
      after_commit :yes, unless: :enabled?
      after_commit :no, if: :enabled?
    end

    klass.run

    expect(log).to eq([:yes])
  end

  it 'propagates an error raised in the hook, after the writes committed' do
    klass = Class.new(Actionable::Action) do
      transactional model: AcWidget
      define_method(:write) { AcWidget.create!(name: 'kept') }
      define_method(:notify) { raise ArgumentError, 'hook broke' }
      step :write
      after_commit :notify
    end

    expect { klass.run }.to raise_error(ArgumentError, 'hook broke')
    expect(AcWidget.pluck(:name)).to eq(%w[kept])
  end

  it 'cannot change the returned result; a halt stops the remaining after_commit hooks' do
    log = self.log
    klass = Class.new(Actionable::Action) do
      define_method(:work) { nil }
      define_method(:first) do
        log << :first
        fail!(:too_late)
      end
      define_method(:second) { log << :second }
      step :work
      after_commit :first
      after_commit :second
    end

    result = klass.run

    expect(result).to be_success
    expect(log).to eq([:first])
  end

  it 'leaves after_commit hooks out of the history' do
    klass = action('measured', log)
    klass.measure :all

    result = klass.run

    expect(result.history.steps.map(&:name)).to eq(%i[write check])
    expect(log).to eq([['measured', false]])
  end

  it 'is inherited, and a subclass addition does not leak to the parent' do
    log = self.log
    parent = action('parent', log, transactional: false)
    child = Class.new(parent) do
      define_method(:extra) { log << :extra }
      after_commit :extra
    end

    parent.run
    child.run

    expect(log).to eq([['parent', false], ['parent', false], :extra])
  end

  it 'raises a DefinitionError at run start when the hook method is missing' do
    klass = Class.new(Actionable::Action) do
      define_method(:work) { nil }
      step :work
      after_commit :not_there
    end

    expect { klass.run }.to raise_error(Actionable::DefinitionError, /:not_there/)
  end

  it 'raises a DefinitionError at run start when a hook calls a recording verb before more code' do
    klass = Class.new(Actionable::Action) do
      define_method(:work) { nil }
      step :work
      after_commit :notify

      def notify
        skip :quiet_hours # rubocop:disable Actionable/VerbNotLast -- the offense under test
        nil
      end
    end

    expect { klass.run }.to raise_error(Actionable::DefinitionError, /#notify .*`skip`/)
  end

  it 'raises at declaration on an ActiveRecord without after_all_transactions_commit' do
    allow(ActiveRecord).to receive(:respond_to?).and_call_original
    allow(ActiveRecord).to receive(:respond_to?).with(:after_all_transactions_commit).and_return(false)

    expect { Class.new(Actionable::Action) { after_commit :notify } }
      .to raise_error(Actionable::DefinitionError, /ActiveRecord >= 7\.2/)
  end

  describe 'in describe / describe_text' do
    let(:nested) { Class.new(Actionable::Action) { def self.name = 'NotifyWarehouse' } }
    let(:klass) do
      hook_action = nested
      Class.new(Actionable::Action) do
        def self.name = 'PlaceOrder'
        define_method(:notify) { nil }
        step :notify
        after_commit :notify
        after_commit hook_action
      end
    end

    it 'lists the after_commit hooks alongside the core hook sections' do
      hooks = klass.describe[:hooks]

      expect(hooks[:after_commit]).to eq(klass.after_commit_hooks.map(&:name))
      expect(hooks[:after_commit].first).to eq(:notify)
      expect(hooks[:after_commit].size).to eq(2)
      expect(hooks.keys).to eq(%i[on_success on_failure on_skip always after_commit])
    end

    it 'reports an empty after_commit section for an action without any' do
      expect(Class.new(Actionable::Action).describe[:hooks][:after_commit]).to eq([])
    end

    it 'renders an after_commit line in describe_text only when there are hooks' do
      expect(klass.describe_text).to include("after_commit: #{klass.after_commit_hooks.map(&:name).join(", ")}")
      expect(Class.new(Actionable::Action).describe_text).not_to include('after_commit')
    end
  end
end
