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
