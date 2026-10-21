# frozen_string_literal: true

# Optional outcome coverage for an RSpec suite (decision D22). Load it with
# `require 'actionable/rspec/coverage'`, typically from spec/support. Never
# loaded by the core or by `actionable/rspec`.
#
# Requiring it starts recording every real action run and, when RSpec is
# loaded, adds an end-of-suite hook: it writes the runs to the file named by
# +ACTIONABLE_COVERAGE_FILE+ when that is set (one shard of a sharded suite),
# and otherwise prints the report and holds it to {Actionable::Coverage.baseline}.
require_relative 'coverage/tracker'
require_relative 'coverage/report'

module Actionable
  module Coverage
    class << self
      # Start recording and, under RSpec, add the end-of-suite hook once.
      #
      # @return [void]
      def install!
        enable!
        return if @installed || !defined?(::RSpec) || !::RSpec.respond_to?(:configure)

        @installed = true
        ::RSpec.configure { |config| config.after(:suite) { Actionable::Coverage.finish_suite! } }
      end

      # The end-of-suite step: write this process's runs to
      # +ACTIONABLE_COVERAGE_FILE+ when it is set, since one shard can't judge
      # the whole suite, and otherwise {.report!}.
      #
      # @param io [IO] where the text report goes
      # @return [Report, String] the report, or the shard file's path
      def finish_suite!(io: $stdout)
        path = ENV['ACTIONABLE_COVERAGE_FILE'].to_s
        return write(path) unless path.empty?

        io.puts # the progress formatter leaves its line open
        report!(io: io)
      end
    end
  end
end

Actionable::Coverage.install!
