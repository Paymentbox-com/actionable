# frozen_string_literal: true

require 'logger'
require 'actionable/job'

sidekiq_loaded =
  begin
    require 'sidekiq'
    true
  rescue LoadError
    false
  end

# Real Sidekiq in its inline testing mode (no Redis): Job is backend-neutral,
# so the Sidekiq contract is just that RetryableFailure propagates out of
# perform, where Sidekiq's own retry picks it up. Runs with
# gemfiles/jobs.gemfile (the `jobs` CI lane); skipped in the default suite.
RSpec.describe 'Actionable::Job on real Sidekiq (inline testing mode)',
  skip: (sidekiq_loaded ? false : 'sidekiq not installed (BUNDLE_GEMFILE=gemfiles/jobs.gemfile)') do
  around { |example| Sidekiq.testing!(:inline) { example.run } }

  before do
    Sidekiq.default_configuration.logger = Logger.new(IO::NULL)
    stub_const('ActionableSidekiqJob', Class.new do
      include Sidekiq::Job
      include Actionable::Job::Mixin

      def perform(action_name) = run_actionable(Object.const_get(action_name))
    end)
  end

  def define_action(name, verb, code, retry_flag)
    stub_const(name, Class.new(Actionable::Action) do
      honor_retry_metadata
      verb == :fail! ? fails(code, retry: retry_flag) : skips(code, retry: retry_flag)
      step :go
      define_method(:go) { send(verb, code) }
    end)
  end

  it 'raises RetryableFailure out of perform_async for a retry: true skip' do
    define_action('SidekiqNotReady', :skip!, :not_ready, true)

    expect { ActionableSidekiqJob.perform_async('SidekiqNotReady') }
      .to raise_error(Actionable::Job::RetryableFailure) { |e| expect(e.result).to be_skipped }
  end

  it 'completes without raising for a retry: false failure (discard)' do
    define_action('SidekiqGiveUp', :fail!, :timeout, false)

    expect { ActionableSidekiqJob.perform_async('SidekiqGiveUp') }.not_to raise_error
  end
end
