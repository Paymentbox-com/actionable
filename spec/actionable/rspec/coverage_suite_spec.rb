# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'

# End to end: `require 'actionable/rspec/coverage'` in a real RSpec run, in a
# child process so its end-of-suite hook doesn't attach to this suite.
RSpec.describe 'require actionable/rspec/coverage' do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:lib) { File.expand_path('../../../lib', __dir__) }

  def write_suite
    path = File.join(@dir, 'suite_spec.rb')
    File.write(path, <<~RUBY)
      require 'actionable/rspec'
      require 'actionable/rspec/coverage'

      Actionable::Coverage.include_prefixes = %w[Suite]
      Actionable::Coverage.baseline = ENV['SUITE_BASELINE']

      class SuiteCharge < Actionable::Action
        fails :refused
        step :go
        def go = nil
      end

      class SuiteAbstract < Actionable::Action
      end

      RSpec.describe('a host suite') { it('runs an action') { SuiteCharge.run } }
    RUBY
    path
  end

  def run_suite(env = {})
    command = [RbConfig.ruby, '-rbundler/setup', '-I', lib, Gem.bin_path('rspec-core', 'rspec'), write_suite]
    Open3.capture2e(env, *command, chdir: @dir)
  end

  it 'prints the report at the end of the suite' do
    output, status = run_suite

    expect(status).to be_success, output
    expect(output).to match(/SuiteCharge\s+failure:refused/)
    expect(output).to include('Actions: 1  Expected outcomes: 2  Reached: 1  Missing: 1')
    expect(output).not_to include('SuiteAbstract')
  end

  it 'writes a shard file instead of reporting when ACTIONABLE_COVERAGE_FILE is set' do
    shard = File.join(@dir, 'coverage', 'shard-1.json')
    output, status = run_suite('ACTIONABLE_COVERAGE_FILE' => shard)

    expect(status).to be_success, output
    expect(output).not_to include('Actionable outcome coverage')
    expect(File.read(shard)).to include('SuiteCharge')
  end

  it 'fails the suite, saying what to change, when the gaps differ from the baseline' do
    baseline = File.join(@dir, 'baseline.json')
    File.write(baseline, '{"SuiteCharge": ["failure:refused", "failure:expired"]}')

    output, status = run_suite('SUITE_BASELINE' => baseline)

    expect(status).not_to be_success
    expect(output).to include('Remove each one from the baseline', 'SuiteCharge: failure:expired')
  end

  it 'passes the suite when the gaps match the baseline' do
    baseline = File.join(@dir, 'baseline.json')
    File.write(baseline, '{"SuiteCharge": ["failure:refused"]}')

    output, status = run_suite('SUITE_BASELINE' => baseline)

    expect(status).to be_success, output
  end
end
