# frozen_string_literal: true

# Indicative micro-benchmarks for Actionable's hot paths. Dependency-free on
# purpose: `benchmark` is no longer a default gem on Ruby 4 and benchmark-ips
# isn't in the Gemfile, so this times loops with the monotonic clock.
#
#   bundle exec rake bench                        # default iterations
#   BENCH_ITERATIONS=2000 bundle exec rake bench  # quicker, noisier
#
# Each scenario is warmed up, then timed over BENCH_ITERATIONS runs; the
# report is microseconds per run (lower is better) and runs per second. The
# numbers are for comparing changes on one machine, not across machines.

require 'bundler/setup'
require_relative '../lib/actionable'

module ActionableBench
  # One method step that does nothing: the floor cost of a run.
  class Trivial < Actionable::Action
    step :work
    def work = nil
  end

  # Five method steps, no measurement (the default `measure :none`).
  class FiveSteps < Actionable::Action
    step :one
    step :two
    step :three
    step :four
    step :five
    def one = nil
    def two = nil
    def three = nil
    def four = nil
    def five = nil
  end

  # The same five steps with a History recorded on every run.
  class FiveStepsMeasured < FiveSteps
    measure :all
  end

  # A five-field input schema fed strings that all need coercing.
  class Coerce < Actionable::Action
    input do
      required :id, :integer
      required :amount, :decimal
      required :name, :string
      required :active, :boolean
      optional :due_on, :date
    end
    step :work
    def work = nil
  end

  COERCE_INPUT = {id: '42', amount: '19.99', name: 'Acme', active: 'true', due_on: '2026-10-22'}.freeze

  # A child action with a typed output, called as a parent's step.
  class Child < Actionable::Action
    output { required :receipt, :string }
    step :work
    def work = @receipt = 'R-1'
  end

  class Parent < Actionable::Action
    output { optional :receipt, :string }
    step Child, expose: %i[receipt]
  end

  # The same nesting with a History recorded, which cascades into the child.
  class ParentMeasured < Parent
    measure :all
  end

  MEASURED_RESULT = FiveStepsMeasured.run

  SCENARIOS = {
    'trivial action' => -> { Trivial.run },
    '5-step action, measure :none' => -> { FiveSteps.run },
    '5-step action, measure :all' => -> { FiveStepsMeasured.run },
    'input coercion (5 fields)' => -> { Coerce.run(**COERCE_INPUT) },
    'nested action, measure :none' => -> { Parent.run },
    'nested action, measure :all' => -> { ParentMeasured.run },
    'history to_json (5 steps)' => -> { MEASURED_RESULT.history.to_json }
  }.freeze

  module_function

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # @return [Float] microseconds per call
  def time(iterations, callable)
    [iterations / 10, 1].max.times { callable.call } # warm-up
    started = clock
    iterations.times { callable.call }
    (clock - started) * 1_000_000 / iterations
  end

  # Time the happy path only: a scenario that quietly failed (say, an input
  # that stopped coercing) would measure the wrong thing.
  def check!
    SCENARIOS.each do |label, callable|
      value = callable.call
      raise "#{label}: expected a success, got #{value.inspect}" if value.is_a?(Actionable::Result) && !value.success?
    end
  end

  def run(iterations, io = $stdout)
    check!
    yjit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? 'on' : 'off'
    io.puts "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}), YJIT #{yjit}, " \
            "actionable #{Actionable::VERSION}, iterations: #{iterations}"
    width = SCENARIOS.keys.map(&:length).max
    SCENARIOS.each do |label, callable|
      micros = time(iterations, callable)
      io.puts format("%-#{width}s %9.2f µs/run %12s runs/s", label, micros, (1_000_000 / micros).round.to_s)
    end
  end
end

ActionableBench.run(Integer(ENV.fetch('BENCH_ITERATIONS', '20000'))) if $PROGRAM_NAME == __FILE__
