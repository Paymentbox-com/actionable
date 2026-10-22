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

  describe '.disposition with honor_retry: true (owner ruling P10)' do
    def failure(code, **metadata) = Actionable::Failure.new(code: code, metadata: metadata)
    def skipped(code, **metadata) = Actionable::Skipped.new(code: code, metadata: metadata)

    it 'retries a skip whose metadata says retry: true' do
      expect(described_class.disposition(skipped(:not_ready, retry: true), honor_retry: true)).to eq(:retry)
    end

    it 'retries a permanent-code failure whose metadata says retry: true' do
      expect(described_class.disposition(failure(:not_found, retry: true), honor_retry: true)).to eq(:retry)
    end

    it 'discards a transient failure whose metadata says retry: false' do
      expect(described_class.disposition(failure(:timeout, retry: false), honor_retry: true)).to eq(:discard)
    end

    it 'acks a skip whose metadata says retry: false' do
      expect(described_class.disposition(skipped(:not_ready, retry: false), honor_retry: true)).to eq(:ack)
    end

    it 'falls back to the default mapping when the metadata has no retry: key' do
      expect(described_class.disposition(failure(:timeout, kind: :x), honor_retry: true)).to eq(:retry)
      expect(described_class.disposition(failure(:not_found), honor_retry: true)).to eq(:discard)
      expect(described_class.disposition(skipped(:not_ready), honor_retry: true)).to eq(:ack)
      expect(described_class.disposition(Actionable::Success.new, honor_retry: true)).to eq(:ack)
    end

    it 'ignores retry: metadata by default (D20/D21 neutrality)' do
      expect(described_class.disposition(skipped(:not_ready, retry: true))).to eq(:ack)
      expect(described_class.disposition(failure(:not_found, retry: true))).to eq(:discard)
      expect(described_class.disposition(failure(:timeout, retry: false))).to eq(:retry)
    end
  end

  describe 'the honor_retry_metadata action macro' do
    let(:job_class) do
      Class.new do
        include Actionable::Job::Mixin

        def perform(action_class) = run_actionable(action_class)
      end
    end

    let(:not_ready) do
      Class.new(Actionable::Action) do
        skips :not_ready, retry: true
        step :go
        def go = skip!(:not_ready)
      end
    end

    it 'is off by default' do
      expect(not_ready.honor_retry_metadata?).to be(false)
    end

    it 'leaves the job neutral when the action does not opt in' do
      result = job_class.new.perform(not_ready)

      expect(result).to be_skipped
    end

    it 'makes the job raise RetryableFailure for a skip declared retry: true' do
      opted_in = Class.new(not_ready) { honor_retry_metadata }

      expect { job_class.new.perform(opted_in) }
        .to raise_error(Actionable::Job::RetryableFailure, /skipped with retryable code :not_ready/) { |e|
          expect(e.result).to be_skipped
        }
    end

    it 'makes the job discard a failure declared retry: false' do
      opted_in = Class.new(Actionable::Action) do
        honor_retry_metadata
        fails :timeout, retry: false
        step :go
        def go = fail!(:timeout)
      end

      expect(job_class.new.perform(opted_in).code).to eq(:timeout)
    end

    it 'stays neutral for a duck-typed runner that lacks the macro' do
      runner = Object.new
      def runner.run = Actionable::Skipped.new(code: :not_ready, metadata: {retry: true})

      expect(job_class.new.perform(runner)).to be_skipped
    end

    it 'is inherited, and a subclass can turn it off without touching the parent' do
      parent = Class.new(not_ready) { honor_retry_metadata }
      child = Class.new(parent)
      opted_out = Class.new(parent) { honor_retry_metadata(enabled: false) }

      expect(child.honor_retry_metadata?).to be(true)
      expect(opted_out.honor_retry_metadata?).to be(false)
      expect(parent.honor_retry_metadata?).to be(true)
      expect(job_class.new.perform(opted_out)).to be_skipped
    end
  end

  describe 'a run whose hook calls fail!' do
    it 'is not acked' do
      klass = Class.new(Actionable::Action) do
        step :go
        on_success :verify
        def go = nil
        def verify = fail!(:timeout)
      end

      expect(described_class.disposition(klass.run)).to eq(:retry)
    end
  end
end
