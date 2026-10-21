# frozen_string_literal: true

require 'actionable/rspec'
require 'actionable/rspec/coverage/tracker'

RSpec.describe Actionable::Coverage do
  around do |example|
    described_class.enable!
    example.run
  ensure
    described_class.disable!
    described_class.reset!
    described_class.reset_config!
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

  describe 'the gem stub helpers' do
    it 'record a stubbed run in the stubbed set, never as observed' do
      allow_actionable_failure(charge, code: :refused)
      charge.run

      expect(described_class.observed).to be_empty
      expect(described_class.stubbed).to contain_exactly(['CoverageCharge', :failure, :refused])
    end

    it 'record each stub helper when it is called, not when it is set up' do
      stub_actionable_skip(charge, code: :duplicate)

      expect(described_class.stubbed).to be_empty

      charge.run

      expect(described_class.stubbed).to contain_exactly(['CoverageCharge', :skipped, :duplicate])
    end

    it 'still return the very result they built' do
      built = allow_actionable_success(charge, output: {id: 7})

      expect(charge.run).to equal(built)
    end
  end

  describe '.expected_outcomes' do
    it 'expects success and every declared failure' do
      expect(described_class.expected_outcomes(charge)).to eq(%w[success failure:refused])
    end

    it 'expects every declared skip' do
      charge.skips :duplicate

      expect(described_class.expected_outcomes(charge)).to eq(%w[success failure:refused skipped:duplicate])
    end

    it 'leaves the gem codes out by default' do
      expect(described_class.gem_codes).to eq([])
    end

    it 'expects invalid_input when configured and the input has a required field' do
      described_class.gem_codes = %i[invalid_input]

      expect(described_class.expected_outcomes(charge)).to include('failure:invalid_input')
    end

    it 'does not expect invalid_input when no input field is required' do
      described_class.gem_codes = %i[invalid_input]
      optional_only = Class.new(Actionable::Action) { input { optional :note, :string } }

      expect(described_class.expected_outcomes(optional_only)).to eq(%w[success])
    end

    it 'expects invalid_output when configured and the output has a required field' do
      described_class.gem_codes = %i[invalid_output]
      with_output = Class.new(Actionable::Action) { output { required :id, :integer } }

      expect(described_class.expected_outcomes(with_output)).to eq(%w[success failure:invalid_output])
    end

    it 'expects invalid_output when a skip schema has a required field (decision D23)' do
      described_class.gem_codes = %i[invalid_output]
      skipping = Class.new(Actionable::Action) { skips(:idle) { required :id, :integer } }

      expect(described_class.expected_outcomes(skipping)).to eq(%w[success skipped:idle failure:invalid_output])
    end

    it 'expects invalid_output when a failure schema has a required field (decision D23)' do
      described_class.gem_codes = %i[invalid_output]
      failing = Class.new(Actionable::Action) { fails(:refused) { required :reason, :string } }

      expect(described_class.expected_outcomes(failing)).to eq(%w[success failure:refused failure:invalid_output])
    end

    it 'does not expect invalid_output when no schema has a required field' do
      described_class.gem_codes = %i[invalid_output]
      optional_only = Class.new(Actionable::Action) { skips(:idle) { optional :id, :integer } }

      expect(described_class.expected_outcomes(optional_only)).to eq(%w[success skipped:idle])
    end

    it 'lists a declared gem code once' do
      described_class.gem_codes = %i[invalid_input]
      charge.fails :invalid_input, kind: :invalid

      expect(described_class.expected_outcomes(charge).count('failure:invalid_input')).to eq(1)
    end

    it 'refuses a gem code the gem never emits' do
      expect { described_class.gem_codes = %i[refused] }.to raise_error(ArgumentError, /refused/)
    end
  end

  describe '.actions' do
    let!(:base) { stub_const('CoverageBase', Class.new(Actionable::Action)) }
    let!(:billing) do
      stub_const('CoverageBilling', Class.new(base) do
        step :go
        def go = nil
      end)
    end
    let!(:shipping) do
      stub_const('CoverageShipping', Class.new(billing))
    end
    # A named intermediate base with no steps of its own: abstract.
    let!(:abstract) { stub_const('CoverageAbstract', Class.new(base)) }

    before { described_class.root = base }

    it 'lists the named descendants of the root that have steps' do
      expect(described_class.actions).to contain_exactly(billing, shipping)
    end

    it 'leaves out an abstract action, one with no steps' do
      expect(described_class.actions).not_to include(abstract)
    end

    it 'leaves out an anonymous action' do
      anonymous = Class.new(billing)

      expect(described_class.actions).not_to include(anonymous)
    end

    it 'leaves out a class whose name no longer resolves to it, such as a removed stub_const' do
      stale = Class.new(billing)
      Object.const_set(:CoverageStale, stale)
      Object.send(:remove_const, :CoverageStale)

      expect(described_class.actions).not_to include(stale)
    end

    it 'keeps only names starting with an include prefix' do
      described_class.include_prefixes = %w[CoverageShip]

      expect(described_class.actions).to contain_exactly(shipping)
    end

    it 'drops names starting with an exclude prefix' do
      described_class.exclude_prefixes = ['CoverageShip', /\ACoverageBill/]

      expect(described_class.actions).to be_empty
    end

    it 'calls the loader first, so a host can eager-load its actions' do
      loaded = false
      described_class.loader = -> { loaded = true }

      described_class.actions

      expect(loaded).to be(true)
    end
  end
end
