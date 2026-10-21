# frozen_string_literal: true

require 'actionable/rspec/coverage/tracker'

RSpec.describe Actionable::Coverage do
  around do |example|
    described_class.enable!
    example.run
  ensure
    described_class.disable!
    described_class.reset!
  end

  # Named fixture actions: a run is recorded under the class name, so each one
  # gets a constant for the example.
  let!(:charge) do
    stub_const('CoverageCharge', Class.new(Actionable::Action) do
      fails :refused
      input { required :outcome, :symbol }
      step :decide

      def decide
        case input.outcome
        when :refused then fail!(:refused)
        when :skip then skip!(:duplicate)
        end
      end
    end)
  end

  describe 'recording a real run' do
    it 'records the class name, outcome and code of each run' do
      charge.run(outcome: :ok)
      charge.run(outcome: :refused)
      charge.run(outcome: :skip)

      expect(described_class.observed).to contain_exactly(
        ['CoverageCharge', :success, :success],
        ['CoverageCharge', :failure, :refused],
        ['CoverageCharge', :skipped, :duplicate]
      )
    end

    it 'records the invalid_input failure the gem builds before any step runs' do
      charge.run

      expect(described_class.observed).to contain_exactly(['CoverageCharge', :failure, :invalid_input])
    end

    it 'records a nested action run as well as its parent' do
      stub_const('CoverageCheckout', Class.new(Actionable::Action) do
        fails :refused
        step CoverageCharge, input: %i[outcome]
        def initialize(outcome: :ok)
          super()
          @outcome = outcome
        end
      end)

      CoverageCheckout.run(outcome: :refused)

      expect(described_class.observed).to contain_exactly(
        ['CoverageCharge', :failure, :refused],
        ['CoverageCheckout', :failure, :refused]
      )
    end

    it 'records every run of run_each' do
      charge.run_each(%i[ok refused]) { |outcome| {outcome: outcome} }

      expect(described_class.observed).to contain_exactly(
        ['CoverageCharge', :success, :success],
        ['CoverageCharge', :failure, :refused]
      )
    end

    it 'does not record an anonymous action, which has no name to report under' do
      anonymous = Class.new(Actionable::Action) do
        step :go
        def go = nil
      end

      anonymous.run

      expect(described_class.observed).to be_empty
    end

    it 'records nothing while disabled' do
      described_class.disable!
      charge.run(outcome: :ok)

      expect(described_class.observed).to be_empty
    end

    it 'records nothing when the run raises, since an exception is not an outcome' do
      stub_const('CoverageBoom', Class.new(Actionable::Action) do
        step :go
        def go = raise('boom')
      end)

      expect { CoverageBoom.run }.to raise_error(RuntimeError, 'boom')
      expect(described_class.observed).to be_empty
    end
  end

  describe 'a stubbed run' do
    it 'is not recorded as the action being tested, because the stub replaces .run' do
      allow(charge).to receive(:run).and_return(Actionable::Success.new)

      charge.run(outcome: :ok)

      expect(described_class.observed).to be_empty
    end

    it 'is recorded when the stub calls the original' do
      allow(charge).to receive(:run).and_call_original

      charge.run(outcome: :ok)

      expect(described_class.observed).to contain_exactly(['CoverageCharge', :success, :success])
    end
  end
end
