# frozen_string_literal: true

require 'actionable/job'

RSpec.describe Actionable::Job do
  describe '.disposition' do
    it 'acks a success' do
      expect(described_class.disposition(Actionable::Success.new)).to eq(:ack)
    end

    it 'acks a skip — a skip is not an error to retry' do
      expect(described_class.disposition(Actionable::Skipped.new(code: :duplicate))).to eq(:ack)
    end

    it 'retries a transient failure' do
      expect(described_class.disposition(Actionable::Failure.new(code: :timeout))).to eq(:retry)
    end

    it 'discards a permanent failure (bad input can\'t be fixed by retrying)' do
      expect(described_class.disposition(Actionable::Failure.new(code: :invalid_input))).to eq(:discard)
    end

    it 'honors a custom permanent set' do
      result = Actionable::Failure.new(code: :unprocessable)
      expect(described_class.disposition(result, permanent: %i[unprocessable])).to eq(:discard)
    end
  end

  describe Actionable::Job::Mixin do
    let(:job_class) do
      Class.new do
        include Actionable::Job::Mixin

        def perform(action_class, **kwargs) = run_actionable(action_class, **kwargs)
      end
    end

    let(:succeeds) do
      Class.new(Actionable::Action) do
        step :go
        def go = succeed('done')
      end
    end

    let(:fails_transient) do
      Class.new(Actionable::Action) do
        step :go
        def go = fail!(:timeout)
      end
    end

    let(:fails_permanent) do
      Class.new(Actionable::Action) do
        step :go
        def go = fail!(:invalid_input)
      end
    end

    let(:raises) do
      Class.new(Actionable::Action) do
        step :go
        def go = raise('boom')
      end
    end

    it 'returns the result and records it for an ack outcome' do
      job = job_class.new
      result = job.perform(succeeds)

      expect(result).to be_success
      expect(job.actionable_result).to be(result)
    end

    it 'returns (does not raise) for a discard outcome, recording the result' do
      job = job_class.new
      result = job.perform(fails_permanent)

      expect(result).to be_failure
      expect(result.code).to eq(:invalid_input)
      expect(job.actionable_result).to be(result)
    end

    it 'raises RetryableFailure for a retry outcome, carrying the result' do
      expect { job_class.new.perform(fails_transient) }
        .to raise_error(Actionable::Job::RetryableFailure) { |e| expect(e.result.code).to eq(:timeout) }
    end

    it 'lets a genuine exception propagate (the queue retries it)' do
      expect { job_class.new.perform(raises) }.to raise_error(RuntimeError, 'boom')
    end

    it 'respects an overridden permanent-code set' do
      custom_job = Class.new do
        include Actionable::Job::Mixin

        def perform(action_class) = run_actionable(action_class)
        def actionable_permanent_codes = %i[timeout]
      end

      # :timeout is now permanent → discard → returns instead of raising
      result = custom_job.new.perform(fails_transient)
      expect(result.code).to eq(:timeout)
    end
  end
end
