# frozen_string_literal: true

RSpec.describe 'Actionable lifecycle hooks' do
  describe 'outcome-based dispatch' do
    it 'runs on_success (not on_failure) after a successful run' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:main) { calls << :main }
        define_method(:cleanup) { calls << :cleanup }
        define_method(:rollback) { calls << :rollback }
        step :main
        on_success :cleanup
        on_failure :rollback
      end

      klass.run

      expect(calls).to eq(%i[main cleanup])
    end

    it 'runs on_failure (not on_success) after a failed run' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:main) { fail(:nope) }
        define_method(:cleanup) { calls << :cleanup }
        define_method(:rollback) { calls << :rollback }
        step :main
        on_success :cleanup
        on_failure :rollback
      end

      klass.run

      expect(calls).to eq(%i[rollback])
    end

    it 'runs always hooks after the outcome hooks, regardless of outcome' do
      succeeded = []
      failed = []
      build = lambda do |collector, fails|
        Class.new(Actionable::Action) do
          define_method(:main) { fail(:nope) if fails }
          define_method(:cleanup) { collector << :cleanup }
          define_method(:rollback) { collector << :rollback }
          define_method(:log) { collector << :log }
          step :main
          on_success :cleanup
          on_failure :rollback
          always :log
        end
      end

      build.call(succeeded, false).run
      build.call(failed, true).run

      expect(succeeded).to eq(%i[cleanup log])
      expect(failed).to eq(%i[rollback log])
    end

    it 'runs hooks within a category in declaration order' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:main) { nil }
        define_method(:first) { calls << :first }
        define_method(:second) { calls << :second }
        step :main
        on_success :first
        on_success :second
      end

      klass.run

      expect(calls).to eq(%i[first second])
    end
  end

  describe 'hooks using control flow' do
    it 'lets an on_failure hook recover the run into a success without re-dispatching on_success' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:main) { fail(:nope) }
        define_method(:recover) do
          calls << :recover
          succeed('recovered')
        end
        define_method(:on_success_hook) { calls << :on_success_hook }
        step :main
        on_failure :recover
        on_success :on_success_hook
      end

      result = klass.run

      expect(result).to be_success
      expect(result.message).to eq('recovered')
      expect(calls).to eq(%i[recover]) # category fixed by the post-main outcome
    end

    it 'stops the remaining hooks (including always) when a hook calls halt!' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:main) { nil }
        define_method(:a) do
          calls << :a
          halt!
        end
        define_method(:b) { calls << :b }
        define_method(:log) { calls << :log }
        step :main
        on_success :a
        on_success :b
        always :log
      end

      klass.run

      expect(calls).to eq(%i[a])
    end
  end

  describe 'output refreshed after each hook' do
    it 'captures ivars a hook sets into the typed output' do
      klass = Class.new(Actionable::Action) do
        output do
          required :invoice, :string
          optional :receipt, :string
        end
        define_method(:main) { @invoice = 'INV' }
        define_method(:attach) { @receipt = 'RCP' }
        step :main
        on_success :attach
      end

      result = klass.run

      expect(result.output.invoice).to eq('INV')
      expect(result.output.receipt).to eq('RCP')
    end

    it 're-validates, flipping a success to :invalid_output when a hook corrupts output' do
      klass = Class.new(Actionable::Action) do
        output { required :count, :integer }
        define_method(:main) { @count = 5 }
        define_method(:corrupt) { @count = 'not a number' }
        step :main
        on_success :corrupt
      end

      result = klass.run

      expect(result).to be_failure
      expect(result.code).to eq(:invalid_output)
    end
  end

  describe 'bang verbs inside hooks' do
    it 'adopts a fail! from an on_success hook and stops the remaining hooks' do
      calls = []
      klass = Class.new(Actionable::Action) do
        define_method(:main) { nil }
        define_method(:verify) { fail!(:verification_failed) }
        define_method(:later) { calls << :later }
        step :main
        on_success :verify
        on_success :later
        always :later
      end

      result = klass.run

      expect(result).to be_failure
      expect(result.code).to eq(:verification_failed)
      expect(calls).to be_empty
    end

    it 'adopts a skip! from an on_success hook' do
      klass = Class.new(Actionable::Action) do
        define_method(:main) { nil }
        define_method(:check) { skip!(:not_ready) }
        step :main
        on_success :check
      end

      result = klass.run

      expect(result).to be_skipped
      expect(result.code).to eq(:not_ready)
    end

    it 'adopts a succeed! from an on_failure hook' do
      klass = Class.new(Actionable::Action) do
        define_method(:main) { fail(:nope) }
        define_method(:recover) { succeed!('recovered') }
        step :main
        on_failure :recover
      end

      result = klass.run

      expect(result).to be_success
      expect(result.message).to eq('recovered')
    end

    it 'adopts a fail! from an always hook' do
      klass = Class.new(Actionable::Action) do
        define_method(:main) { nil }
        define_method(:audit) { fail!(:audit_failed) }
        step :main
        always :audit
      end

      result = klass.run

      expect(result).to be_failure
      expect(result.code).to eq(:audit_failed)
    end

    it 'fails the run and stops the remaining hooks when a nested-action hook fails' do
      calls = []
      child = Class.new(Actionable::Action) do
        define_method(:go) { fail!(:child_bad) }
        step :go
      end
      stub_const('FailingChild', child)
      klass = Class.new(Actionable::Action) do
        define_method(:main) { nil }
        define_method(:log) { calls << :log }
        step :main
        on_success FailingChild
        always :log
      end

      result = klass.run

      expect(result.code).to eq(:child_bad)
      expect(calls).to be_empty
    end

    it 'records the adopted code in the history when measuring' do
      klass = Class.new(Actionable::Action) do
        measure :all
        define_method(:main) { nil }
        define_method(:verify) { fail!(:verification_failed) }
        step :main
        on_success :verify
      end

      result = klass.run

      expect(result.code).to eq(:verification_failed)
      expect(result.history.steps.map(&:code)).to include(:verification_failed)
    end
  end
end
