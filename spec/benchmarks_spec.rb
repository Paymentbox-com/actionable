# frozen_string_literal: true

require 'open3'
require 'rbconfig'

# A smoke test for the dependency-free benchmark script (`rake bench`), so it
# can't rot as the API changes. It runs every scenario a few times in a
# subprocess (the script defines its own actions; keeping them out of this
# process keeps the Registry clean) and checks the report's shape, not timings.
RSpec.describe 'benchmarks/run.rb' do
  let(:script) { File.expand_path('../benchmarks/run.rb', __dir__) }

  it 'runs every scenario and reports a timing for each' do
    out, err, status = Open3.capture3({'BENCH_ITERATIONS' => '5'}, RbConfig.ruby, script, chdir: File.expand_path('..', __dir__))

    expect(status).to be_success, err
    expect(out).to include('Ruby ', 'iterations: 5')
    ['trivial action', '5-step action, measure :none', '5-step action, measure :all',
     'input coercion (5 fields)', 'nested action, measure :none', 'nested action, measure :all',
     'history to_json (5 steps)'].each do |label|
      expect(out).to match(/^#{Regexp.escape(label)}\s+[\d.]+ µs/)
    end
  end
end
