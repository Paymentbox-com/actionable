# frozen_string_literal: true

RSpec.describe Actionable::Steps::Action do
  describe 'threading input and absorbing output' do
    it 'runs the child with parent ivars as input and absorbs exposed output' do
      notify = Class.new(Actionable::Action) do
        output { required :receipt, :string }
        define_method(:initialize) { |invoice:| @invoice = invoice }
        define_method(:build) { @receipt = "receipt for #{@invoice}" }
        step :build
      end
      parent = Class.new(Actionable::Action) do
        output { required :receipt, :string }
        define_method(:build_invoice) { @invoice = 'INV-1' }
        step :build_invoice
        step notify, input: %i[invoice], expose: %i[receipt]
      end

      result = parent.run

      expect(result).to be_success
      expect(result.output.receipt).to eq('receipt for INV-1')
    end

    it 'absorbs only the exposed fields' do
      child = Class.new(Actionable::Action) do
        output do
          required :receipt, :string
          required :tracking, :string
        end
        define_method(:build) do
          @receipt = 'RCP'
          @tracking = 'TRK'
        end
        step :build
      end
      parent = Class.new(Actionable::Action) do
        output do
          optional :receipt, :string
          optional :tracking, :string
        end
        step child, expose: %i[receipt]
      end

      result = parent.run

      expect(result.output.receipt).to eq('RCP')
      expect(result.output.tracking).to be_nil
    end

    it 'absorbs all child outputs when no :expose is given' do
      child = Class.new(Actionable::Action) do
        output do
          required :receipt, :string
          required :tracking, :string
        end
        define_method(:build) do
          @receipt = 'RCP'
          @tracking = 'TRK'
        end
        step :build
      end
      parent = Class.new(Actionable::Action) do
        output do
          optional :receipt, :string
          optional :tracking, :string
        end
        step child
      end

      result = parent.run

      expect(result.output.receipt).to eq('RCP')
      expect(result.output.tracking).to eq('TRK')
    end

    it 'leaves a parent ivar alone when a successful child never set that field' do
      child = Class.new(Actionable::Action) do
        output { optional :val, :string }
        define_method(:noop) { nil }
        step :noop
      end
      parent = Class.new(Actionable::Action) do
        output { optional :val, :string }
        define_method(:prime) { @val = 'parent' }
        step :prime
        step child
      end

      expect(parent.run.output.val).to eq('parent')
    end

    it 'does not overwrite a parent ivar with a field default the child never set' do
      child = Class.new(Actionable::Action) do
        output { optional :status, :string, default: 'new' }
        define_method(:noop) { nil }
        step :noop
      end
      parent = Class.new(Actionable::Action) do
        output { optional :status, :string }
        define_method(:prime) { @status = 'settled' }
        step :prime
        step child
      end

      expect(parent.run.output.status).to eq('settled')
    end

    it 'absorbs a field the child set by succeed kwarg' do
      child = Class.new(Actionable::Action) do
        output { optional :val, :string }
        define_method(:go) { succeed(val: 'child') }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        output { optional :val, :string }
        define_method(:prime) { @val = 'parent' }
        step :prime
        step child
      end

      expect(parent.run.output.val).to eq('child')
    end

    it 'leaves a parent ivar alone when a skipped child never set that field' do
      child = Class.new(Actionable::Action) do
        output { optional :val, :string }
        define_method(:go) { skip!(:duplicate) }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        output { optional :val, :string }
        define_method(:prime) { @val = 'parent' }
        step :prime
        step child
      end

      expect(parent.run.output.val).to eq('parent')
    end

    it 'leaves a parent ivar alone when a declared-skip child with a hook never set that field' do
      child = Class.new(Actionable::Action) do
        skips(:nope) do
          optional :a, :string
          optional :b, :string
        end
        define_method(:go) { skip!(:nope, nil, a: 'x') }
        define_method(:noop) { nil }
        step :go
        always :noop
      end
      stub_const('SkipChildWithHook', child)
      parent = Class.new(Actionable::Action) do
        output do
          optional :a, :string
          optional :b, :string
        end
        define_method(:prime) { @b = 'parent-b' }
        step :prime
        step SkipChildWithHook
      end

      result = parent.run

      expect(result.output.a).to eq('x')
      expect(result.output.b).to eq('parent-b')
    end

    it 'leaves a parent ivar alone when a typed-outcomes child never set that field' do
      child = Class.new(Actionable::Action) do
        typed_outcomes
        output { optional :val, :string }
        define_method(:noop) { nil }
        step :noop
      end
      stub_const('TypedChild', child)
      parent = Class.new(Actionable::Action) do
        output { optional :val, :string }
        define_method(:prime) { @val = 'parent' }
        step :prime
        step TypedChild
      end

      expect(parent.run.output.val).to eq('parent')
    end
  end

  describe 'nested failure' do
    it 'fails the parent with the child code/message and halts the remaining steps' do
      ran = []
      child = Class.new(Actionable::Action) do
        define_method(:go) { fail!(:child_err, 'child blew up') }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        define_method(:after) { ran << :after }
        step child
        step :after
      end

      result = parent.run

      expect(result).to be_failure
      expect(result.code).to eq(:child_err)
      expect(result.message).to eq('child blew up')
      expect(ran).to eq([])
    end

    it 'propagates the child errors collection onto the parent' do
      child = Class.new(Actionable::Action) do
        define_method(:go) { fail!(:invalid, 'bad', name: 'is required') }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        step child
      end

      result = parent.run

      expect(result.errors[:name]).to eq(['is required'])
    end

    it 'keeps a child error keyed like a keyword the parent fail takes' do
      child = Class.new(Actionable::Action) do
        define_method(:go) { fail!(:invalid, 'bad', kind: 'is not a known kind', name: 'is required') }
        step :go
      end
      # A host base class that, like pbx did, gives fail its own keyword.
      parent = Class.new(Actionable::Action) do
        step child

        def fail(code, message = nil, kind: nil, **errors)
          raise ArgumentError, "kind #{kind.inspect} is not a Symbol" if kind && !kind.is_a?(Symbol)

          super(code, message, **errors)
        end
      end

      result = parent.run

      expect(result.code).to eq(:invalid)
      expect(result.errors[:kind]).to eq(['is not a known kind'])
      expect(result.errors[:name]).to eq(['is required'])
    end

    it "carries the child's declared metadata onto the parent failure" do
      child = Class.new(Actionable::Action) do
        fails :refused, kind: :rejected, retryable: false
        define_method(:go) { fail!(:refused, 'card refused') }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        fails :refused
        step child
      end

      result = parent.run

      expect(result.code).to eq(:refused)
      expect(result.message).to eq('card refused')
      expect(result.metadata).to eq(kind: :rejected, retryable: false)
    end

    it "fills in the parent's declared metadata under the child's" do
      child = Class.new(Actionable::Action) do
        fails :refused, kind: :rejected
        define_method(:go) { fail!(:refused) }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        fails :refused, kind: :conflict, http_status: 409
        step child
      end

      expect(parent.run.metadata).to eq(kind: :rejected, http_status: 409)
    end

    it "keeps the child's failure class and its extra attributes" do
      host_failure = Class.new(Actionable::Failure) { optional :kind, :symbol }
      child = Class.new(Actionable::Action) do
        define_method(:go) do
          @result = host_failure.new(code: :refused, kind: :rejected)
          halt!
        end
        step :go
      end
      parent = Class.new(Actionable::Action) { step child }

      result = parent.run

      expect(result).to be_a(host_failure)
      expect(result.kind).to eq(:rejected)
    end

    it 'refuses a child code that a declaring parent does not declare' do
      child = Class.new(Actionable::Action) do
        define_method(:go) { fail!(:refused) }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        fails :not_found
        step child
      end

      expect { parent.run }.to raise_error(Actionable::DefinitionError, /fails with :refused/)
    end
  end

  describe 'skip guards' do
    it 'skips the nested action when an :if guard opts out' do
      ran = []
      child = Class.new(Actionable::Action) do
        define_method(:go) { ran << :child }
        step :go
      end
      parent = Class.new(Actionable::Action) do
        define_method(:initialize) { |run_child:| @run_child = run_child }
        define_method(:run_child?) { @run_child }
        step child, if: :run_child?
      end

      parent.run(run_child: false)

      expect(ran).to eq([])
    end
  end
end
