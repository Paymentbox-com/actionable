# frozen_string_literal: true

require 'tmpdir'
require 'actionable/rspec'
require 'actionable/rspec/coverage/tracker'
require 'actionable/rspec/coverage/report'

RSpec.describe Actionable::Coverage::Report do
  around do |example|
    Actionable::Coverage.enable!
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  ensure
    Actionable::Coverage.disable!
    Actionable::Coverage.reset!
    Actionable::Coverage.reset_config!
  end

  let(:coverage) { Actionable::Coverage }
  let!(:base) { stub_const('ReportBase', Class.new(Actionable::Action)) }
  let!(:charge) do
    stub_const('ReportCharge', Class.new(base) do
      fails :refused
      fails :not_found
      input { required :outcome, :symbol }
      step :decide

      def decide
        fail!(input.outcome) unless input.outcome == :ok
      end
    end)
  end
  let!(:refund) do
    stub_const('ReportRefund', Class.new(base) do
      step :go
      def go = nil
    end)
  end

  before { coverage.root = base }

  def baseline_path(name = 'baseline.json')
    File.join(@dir, name)
  end

  describe 'the totals' do
    it 'counts actions, expected outcomes, reached and missing' do
      charge.run(outcome: :ok)
      charge.run(outcome: :refused)

      expect(described_class.new.totals).to eq(actions: 2, expected: 4, reached: 2, missing: 2)
    end

    it 'does not count an outcome reached only through a stub' do
      allow_actionable_failure(charge, code: :not_found)
      charge.run

      expect(described_class.new.totals).to include(reached: 0, missing: 4)
    end
  end

  describe '#rows' do
    it 'gives each action its expected, reached, never-reached and stubbed-only outcomes' do
      charge.run(outcome: :ok)
      allow_actionable_failure(charge, code: :not_found)
      charge.run

      row = described_class.new.rows.find { |r| r[:action] == 'ReportCharge' }

      expect(row).to eq(
        action: 'ReportCharge',
        expected: %w[success failure:refused failure:not_found],
        reached: %w[success],
        missing: %w[failure:refused failure:not_found],
        stubbed_only: %w[failure:not_found]
      )
    end

    it 'reports only actions with an observed run when only_observed is set' do
      coverage.only_observed = true
      refund.run

      expect(described_class.new.rows.map { |r| r[:action] }).to eq(%w[ReportRefund])
    end
  end

  describe '#to_s' do
    it 'tables each action with never-reached outcomes, then the totals' do
      charge.run(outcome: :ok)
      allow_actionable_failure(charge, code: :not_found)
      charge.run

      text = described_class.new.to_s

      expect(text).to include('ReportCharge')
      expect(text).to match(/ReportCharge\s+failure:refused, failure:not_found\s+failure:not_found/)
      expect(text).to match(/ReportRefund\s+success/)
      expect(text).to include('Actions: 2', 'Expected outcomes: 4', 'Reached: 1', 'Missing: 3')
    end

    it 'says so when every expected outcome was reached' do
      coverage.only_observed = true
      refund.run

      expect(described_class.new.to_s).to include('every expected outcome was reached')
    end
  end

  describe '#to_json' do
    it 'carries the rows and totals' do
      refund.run
      parsed = Oj.load(described_class.new.to_json, mode: :compat)

      expect(parsed['totals']).to eq('actions' => 2, 'expected' => 4, 'reached' => 1, 'missing' => 3)
      expect(parsed['actions'].map { |row| row['action'] }).to eq(%w[ReportCharge ReportRefund])
    end
  end

  describe 'the baseline' do
    it 'passes without a baseline, however much is missing' do
      expect(described_class.new).to be_passed
    end

    it 'lists the current gaps as a baseline' do
      charge.run(outcome: :ok)

      expect(described_class.new.to_baseline).to eq(
        'ReportCharge' => %w[failure:refused failure:not_found],
        'ReportRefund' => %w[success]
      )
    end

    it 'writes the baseline to a JSON or YAML file' do
      report = described_class.new
      report.write_baseline(baseline_path)
      report.write_baseline(baseline_path('baseline.yml'))

      expect(Oj.load(File.read(baseline_path), mode: :compat)).to eq(report.to_baseline)
      expect(YAML.safe_load_file(baseline_path('baseline.yml'))).to eq(report.to_baseline)
    end

    it 'passes when the gaps match the baseline exactly' do
      described_class.new.write_baseline(baseline_path)
      coverage.baseline = baseline_path

      expect(described_class.new).to be_passed
    end

    it 'fails on an untested outcome the baseline does not list, naming it' do
      File.write(baseline_path, Oj.dump({'ReportCharge' => %w[failure:refused failure:not_found success]}, mode: :compat))
      coverage.baseline = baseline_path

      report = described_class.new

      expect(report).not_to be_passed
      expect(report.baseline_problems).to eq(new_gaps: {'ReportRefund' => %w[success]}, stale: {})
      expect(report.baseline_message).to include('ReportRefund: success')
    end

    it 'fails on a baseline entry that is now covered, telling you to remove it' do
      described_class.new.write_baseline(baseline_path)
      coverage.baseline = baseline_path
      refund.run

      report = described_class.new

      expect(report.baseline_problems).to eq(new_gaps: {}, stale: {'ReportRefund' => %w[success]})
      expect(report.baseline_message).to match(/remove .*from the baseline/i)
      expect(report.baseline_message).to include('ReportRefund: success')
    end

    it 'fails on a baseline entry no longer declared, or for an action that is gone' do
      described_class.new.write_baseline(baseline_path)
      baseline = Oj.load(File.read(baseline_path), mode: :compat)
      baseline['ReportCharge'] << 'failure:expired'
      baseline['ReportGone'] = %w[success]
      File.write(baseline_path, Oj.dump(baseline, mode: :compat))
      coverage.baseline = baseline_path

      expect(described_class.new.baseline_problems[:stale]).to eq(
        'ReportCharge' => %w[failure:expired],
        'ReportGone' => %w[success]
      )
    end

    it 'does not call an unobserved action stale under only_observed' do
      charge.run(outcome: :ok)
      described_class.new.write_baseline(baseline_path)
      coverage.baseline = baseline_path
      coverage.only_observed = true

      expect(described_class.new.baseline_problems).to eq(new_gaps: {}, stale: {})
    end

    it 'refuses a baseline file that does not exist' do
      coverage.baseline = baseline_path('missing.json')

      expect { described_class.new.baseline_problems }.to raise_error(Actionable::Error, /missing\.json/)
    end
  end

  describe 'shard files' do
    it 'writes the observations to a file a later report merges' do
      charge.run(outcome: :ok)
      allow_actionable_failure(charge, code: :not_found)
      charge.run
      path = File.join(@dir, 'shards', 'one.json')
      coverage.write(path)
      coverage.reset!

      expect(coverage.read(path)).to eq(
        observed: Set[['ReportCharge', :success, :success]],
        stubbed: Set[['ReportCharge', :failure, :not_found]]
      )
    end

    it 'merges several shard files with what this process recorded' do
      charge.run(outcome: :ok)
      coverage.write(File.join(@dir, 'a.json'))
      coverage.reset!
      charge.run(outcome: :refused)
      coverage.write(File.join(@dir, 'b.json'))
      coverage.reset!
      refund.run

      report = described_class.new(files: Dir[File.join(@dir, '*.json')])

      expect(report.totals).to eq(actions: 2, expected: 4, reached: 3, missing: 1)
    end

    it 'takes a glob' do
      charge.run(outcome: :ok)
      coverage.write(File.join(@dir, 'a.json'))
      coverage.reset!

      expect(described_class.new(files: File.join(@dir, '*.json')).totals[:reached]).to eq(1)
    end

    it 'refuses a glob that matches no file, rather than reporting every outcome missing' do
      expect { described_class.new(files: File.join(@dir, 'none-*.json')) }
        .to raise_error(Actionable::Error, /no coverage files match/)
    end
  end

  describe 'Coverage.report!' do
    let(:io) { StringIO.new }

    it 'prints the report and returns it' do
      report = coverage.report!(io: io)

      expect(io.string).to include('Actionable outcome coverage', 'Missing: 4')
      expect(report).to be_a(described_class)
    end

    it 'writes the JSON report when ACTIONABLE_COVERAGE_JSON names a path' do
      path = File.join(@dir, 'report.json')
      stub_const('ENV', ENV.to_h.merge('ACTIONABLE_COVERAGE_JSON' => path))

      coverage.report!(io: io)

      expect(Oj.load(File.read(path), mode: :compat)['totals']['missing']).to eq(4)
    end

    it 'raises with what to change when the baseline disagrees' do
      File.write(baseline_path, '{}')
      coverage.baseline = baseline_path

      expect { coverage.report!(io: io) }
        .to raise_error(Actionable::Coverage::BaselineMismatch, /ReportRefund: success/)
    end

    it 'rewrites the baseline instead of failing when ACTIONABLE_COVERAGE_UPDATE_BASELINE is true' do
      File.write(baseline_path, '{}')
      coverage.baseline = baseline_path
      stub_const('ENV', ENV.to_h.merge('ACTIONABLE_COVERAGE_UPDATE_BASELINE' => 'true'))

      coverage.report!(io: io)

      expect(Oj.load(File.read(baseline_path), mode: :compat)).to include('ReportRefund' => %w[success])
      expect(io.string).to include("wrote the baseline to #{baseline_path}")
    end
  end
end
