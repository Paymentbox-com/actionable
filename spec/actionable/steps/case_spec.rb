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
end
