# frozen_string_literal: true

require 'logger'
require 'actionable/job'

active_job_loaded =
  begin
    require 'active_job'
    true
  rescue LoadError
    false
  end

# Real ActiveJob (test adapter): what `retry_on Actionable::Job::RetryableFailure`
# actually does with Job's dispositions, including honor_retry_metadata. Runs
# with gemfiles/jobs.gemfile (the `jobs` CI lane); skipped in the default suite,
# which has no activejob.
RSpec.describe 'Actionable::Job on real ActiveJob',
  skip: (active_job_loaded ? false : 'activejob not installed (BUNDLE_GEMFILE=gemfiles/jobs.gemfile)') do
  let(:adapter) { ActiveJob::QueueAdapters::TestAdapter.new }
  let(:runs) { [] }

  # A job that runs the named action and retries RetryableFailure up to 3
  # executions, the documented ActiveJob integration.
  let(:job_class) do
    test_adapter = adapter
    stub_const('ActionableBackendJob', Class.new(ActiveJob::Base) do
      self.queue_adapter = test_adapter
      self.logger = Logger.new(IO::NULL)
      include Actionable::Job::Mixin

      retry_on Actionable::Job::RetryableFailure, wait: 0, attempts: 3

      def perform(action_name) = run_actionable(Object.const_get(action_name))
    end)
  end

  # Define a named action (ActiveJob arguments must be serializable, so the
  # job takes the constant's name). +outcomes+ is consumed one per run; the
  # last one repeats. Each run appends its result to +runs+.
  def define_action(name, *outcomes, honor: true, &declarations)
    log = runs
    stub_const(name, Class.new(Actionable::Action) do
      honor_retry_metadata if honor
      class_eval(&declarations)
      step :go
      define_method(:go) do
        outcome = outcomes.length > 1 ? outcomes.shift : outcomes.first
        log << outcome
        send(*outcome)
      end
    end)
  end

  # Execute enqueued jobs (a retry is a re-enqueue) until the queue is empty,
  # returning the executions counter of each job run.
  def drain
    executions = []
    until adapter.enqueued_jobs.empty?
      payload = adapter.enqueued_jobs.shift
      executions << payload.fetch('executions')
      ActiveJob::Base.execute(payload)
    end
    executions
  end

  context 'with honor_retry_metadata' do
    it 're-enqueues a retry: true failure and acks once the action succeeds' do
      define_action('FlakyOnce', %i[fail! timeout_soon], %i[succeed]) { fails :timeout_soon, retry: true }
      job_class.perform_later('FlakyOnce')

      expect(drain).to eq([0, 1])
      expect(runs).to eq([%i[fail! timeout_soon], %i[succeed]])
      expect(adapter.performed_jobs).to be_empty # performed via execute, not the adapter
    end

    it 'retries a retry: true failure (even a permanent code) until attempts run out, then raises' do
      define_action('AlwaysMissing', %i[fail! not_found]) { fails :not_found, retry: true }
      job_class.perform_later('AlwaysMissing')

      expect { drain }.to raise_error(Actionable::Job::RetryableFailure) { |e| expect(e.result.code).to eq(:not_found) }
      expect(runs.length).to eq(3)
    end

    it 're-enqueues a retry: true skip' do
      define_action('NotReadyOnce', %i[skip! not_ready], %i[succeed]) { skips :not_ready, retry: true }
      job_class.perform_later('NotReadyOnce')

      expect(drain).to eq([0, 1])
    end

    it 'discards a retry: false failure (even a transient code): no raise, no re-enqueue' do
      define_action('GiveUp', %i[fail! timeout]) { fails :timeout, retry: false }
      job_class.perform_later('GiveUp')

      expect(drain).to eq([0])
      expect(runs).to eq([%i[fail! timeout]])
    end

    it 'acks a retry: false skip: no raise, no re-enqueue' do
      define_action('Duplicate', %i[skip! duplicate]) { skips :duplicate, retry: false }
      job_class.perform_later('Duplicate')

      expect(drain).to eq([0])
    end
  end

  context 'without honor_retry_metadata (the default)' do
    it 'acks a skip even when it declares retry: true' do
      define_action('NotReadyDefault', %i[skip! not_ready], honor: false) { skips :not_ready, retry: true }
      job_class.perform_later('NotReadyDefault')

      expect(drain).to eq([0])
    end

    it 'still retries a transient failure declared retry: false' do
      define_action('TimeoutDefault', %i[fail! timeout], %i[succeed], honor: false) { fails :timeout, retry: false }
      job_class.perform_later('TimeoutDefault')

      expect(drain).to eq([0, 1])
    end

    it 'still discards a permanent failure' do
      define_action('MissingDefault', %i[fail! not_found], honor: false) { fails :not_found }
      job_class.perform_later('MissingDefault')

      expect(drain).to eq([0])
    end
  end
end
