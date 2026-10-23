# frozen_string_literal: true

RSpec.describe Actionable::Steps::Case do
  describe 'matching a branch' do
    it 'runs the branch whose value equals the switch value' do
      klass = Class.new(Actionable::Action) do
        output { optional :handled, :symbol }
        define_method(:initialize) { |status:| @status = status }
        define_method(:status) { @status }
        define_method(:handle_active) { @handled = :active }
        define_method(:handle_inactive) { @handled = :inactive }
        case_step :status do
          on 'active', :handle_active
          on 'inactive', :handle_inactive
        end
      end

      expect(klass.run(status: 'inactive').output.handled).to eq(:inactive)
    end

    it 'matches a Regexp branch value' do
      klass = Class.new(Actionable::Action) do
        output { optional :kind, :symbol }
        define_method(:initialize) { |code:| @code = code }
        define_method(:code) { @code }
        define_method(:client_error) { @kind = :client }
        define_method(:server_error) { @kind = :server }
        case_step :code do
          on(/\A4\d\d\z/, :client_error)
          on(/\A5\d\d\z/, :server_error)
        end
      end

      expect(klass.run(code: '404').output.kind).to eq(:client)
    end

    it 'matches when the switch value is a member of an Array branch value' do
      klass = Class.new(Actionable::Action) do
        output { optional :decision, :symbol }
        define_method(:initialize) { |status:| @status = status }
        define_method(:status) { @status }
        define_method(:grant) { @decision = :grant }
        define_method(:deny) { @decision = :deny }
        case_step :status do
          on %w[active trial], :grant
          default :deny
        end
      end

      expect(klass.run(status: 'trial').output.decision).to eq(:grant)
    end
  end

  describe 'the default branch' do
    it 'runs when no branch matches' do
      klass = Class.new(Actionable::Action) do
        output { optional :decision, :symbol }
        define_method(:initialize) { |status:| @status = status }
        define_method(:status) { @status }
        define_method(:grant) { @decision = :grant }
        define_method(:deny) { @decision = :deny }
        case_step :status do
          on 'active', :grant
          default :deny
        end
      end

      expect(klass.run(status: 'whatever').output.decision).to eq(:deny)
    end

    it 'is a no-op when nothing matches and no default is declared' do
      klass = Class.new(Actionable::Action) do
        output { optional :decision, :symbol }
        define_method(:initialize) { |status:| @status = status }
        define_method(:status) { @status }
        define_method(:grant) { @decision = :grant }
        case_step :status do
          on 'active', :grant
        end
      end

      result = klass.run(status: 'none')

      expect(result).to be_success
      expect(result.output.decision).to be_nil
    end
  end

  describe 'a nested action as a branch target' do
    it 'runs the action and absorbs its output' do
      child = Class.new(Actionable::Action) do
        output { required :note, :string }
        define_method(:go) { @note = 'from child' }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        output { optional :note, :string }
        define_method(:initialize) { |kind:| @kind = kind }
        define_method(:kind) { @kind }
        case_step :kind do
          on 'child', child
        end
      end

      expect(parent.run(kind: 'child').output.note).to eq('from child')
    end
  end

  describe 'branch guards' do
    def guarded(enabled:, **branch_options)
      Class.new(Actionable::Action) do
        output { optional :handled, :symbol }
        define_method(:initialize) { |status:| @status = status }
        define_method(:status) { @status }
        define_method(:enabled?) { enabled }
        define_method(:handle_active) { @handled = :active }
        define_method(:handle_other) { @handled = :other }
        case_step :status do
          on 'active', :handle_active, **branch_options
          default :handle_other
        end
      end
    end

    it 'runs a matched branch whose if: guard holds' do
      expect(guarded(enabled: true, if: :enabled?).run(status: 'active').output.handled).to eq(:active)
    end

    it 'does not run a matched branch whose if: guard is false' do
      expect(guarded(enabled: false, if: :enabled?).run(status: 'active').output.handled).to be_nil
    end

    it 'does not run a matched branch whose unless: guard is true' do
      expect(guarded(enabled: true, unless: :enabled?).run(status: 'active').output.handled).to be_nil
    end

    it 'does not fall through to the default when the matched branch is guarded out' do
      result = guarded(enabled: false, if: :enabled?).run(status: 'active')

      expect(result).to be_success
      expect(result.output.handled).to be_nil
    end

    it 'honours a guard on the default branch' do
      klass = Class.new(Actionable::Action) do
        output { optional :handled, :symbol }
        define_method(:status) { 'unknown' }
        define_method(:handle_other) { @handled = :other }
        case_step :status do
          on 'active', :handle_other
          default :handle_other, if: ->(_) { false }
        end
      end

      expect(klass.run.output.handled).to be_nil
    end

    it 'does not run a guarded-out nested action branch' do
      ran = []
      child = Class.new(Actionable::Action) do
        define_method(:go) { ran << :child }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        define_method(:kind) { 'child' }
        case_step :kind do
          on 'child', child, unless: ->(_) { true }
        end
      end

      expect(parent.run).to be_success
      expect(ran).to be_empty
    end
  end
end
