# frozen_string_literal: true

require 'oj'
require 'yaml'
require_relative 'tracker'

module Actionable
  module Coverage
    # Raised when the outcomes no spec reached differ from the committed
    # baseline (decision D22). Its message says exactly what to change.
    class BaselineMismatch < Actionable::Error; end

    # The outcome-coverage report (decision D22): for each reported action
    # ({Coverage.actions}), the outcomes it can end with
    # ({Coverage.expected_outcomes}) against the outcomes real runs reached.
    # A text table for people, JSON for machines, and a check against the
    # baseline of known gaps in {Coverage.baseline}.
    class Report
      # @param observed [Enumerable<Array(String, Symbol, Symbol)>] real runs,
      #   as +[class name, outcome, code]+; defaults to {Coverage.observed}
      # @param stubbed [Enumerable<Array(String, Symbol, Symbol)>] runs answered
      #   by a stub helper; defaults to {Coverage.stubbed}
      def initialize(observed: Coverage.observed, stubbed: Coverage.stubbed)
        @observed = keys_by_action(observed)
        @stubbed = keys_by_action(stubbed)
      end

      # One row per reported action. Under {Coverage.only_observed}, only
      # actions with at least one real run are reported.
      #
      # @return [Array<Hash{Symbol=>Object}>] +{action:, expected:, reached:,
      #   missing:, stubbed_only:}+, outcome lists as outcome keys
      def rows
        @rows ||= reported_actions.map do |klass|
          expected = Coverage.expected_outcomes(klass)
          seen = @observed.fetch(klass.name, Set.new)
          stubbed = @stubbed.fetch(klass.name, Set.new)
          missing = expected.reject { |key| seen.include?(key) }
          {
            action: klass.name,
            expected: expected,
            reached: expected.select { |key| seen.include?(key) },
            missing: missing,
            stubbed_only: missing.select { |key| stubbed.include?(key) }
          }
        end
      end

      # @return [Hash{Symbol=>Integer}] +{actions:, expected:, reached:, missing:}+
      def totals
        {
          actions: rows.size,
          expected: rows.sum { |row| row[:expected].size },
          reached: rows.sum { |row| row[:reached].size },
          missing: rows.sum { |row| row[:missing].size }
        }
      end

      # A text table of each action with never-reached outcomes, the subset
      # only ever stubbed, and the totals.
      #
      # @return [String]
      def to_s
        lines = ['Actionable outcome coverage']
        gaps = rows.reject { |row| row[:missing].empty? }
        if gaps.empty?
          lines << '  every expected outcome was reached'
        else
          table = [['Action', 'Never reached', 'Stubbed only']] +
            gaps.map { |row| [row[:action], row[:missing].join(', '), row[:stubbed_only].join(', ')] }
          widths = table.transpose.map { |column| column.map(&:length).max }
          table.each { |cells| lines << "  #{cells.each_with_index.map { |cell, i| cell.ljust(widths[i]) }.join("  ").rstrip}" }
        end
        t = totals
        lines << "Actions: #{t[:actions]}  Expected outcomes: #{t[:expected]}  " \
                 "Reached: #{t[:reached]}  Missing: #{t[:missing]}"
        lines.join("\n")
      end

      # @return [Hash{Symbol=>Object}] +{actions: rows, totals:}+
      def to_h
        {actions: rows, totals: totals}
      end

      # @return [String] {#to_h} as JSON
      def to_json(*)
        Oj.dump(to_h, mode: :compat)
      end

      # The current gaps in baseline form: each action with never-reached
      # outcomes, mapped to them.
      #
      # @return [Hash{String=>Array<String>}]
      def to_baseline
        rows.reject { |row| row[:missing].empty? }.to_h { |row| [row[:action], row[:missing]] }
      end

      # Write {#to_baseline} to +path+, as YAML for a +.yml+ / +.yaml+ path
      # and JSON otherwise. For adoption day, and for accepting a change in
      # the gaps deliberately.
      #
      # @param path [String]
      # @return [String] +path+
      def write_baseline(path = Coverage.baseline)
        raise ArgumentError, 'no baseline path given and Coverage.baseline is not set' if path.nil?

        contents = yaml?(path) ? YAML.dump(to_baseline) : "#{Oj.dump(to_baseline, mode: :compat, indent: 2)}\n"
        File.write(path, contents)
        path
      end

      # The differences from {Coverage.baseline}: never-reached outcomes it
      # doesn't list (+new_gaps+), and entries that are now reached, no longer
      # expected, or name an action that no longer exists (+stale+). Under
      # {Coverage.only_observed}, an existing action with no run is not
      # judged. Both empty without a baseline.
      #
      # @return [Hash{Symbol=>Hash{String=>Array<String>}}] +{new_gaps:, stale:}+
      # @raise [Actionable::Error] when the baseline file doesn't exist
      def baseline_problems
        @baseline_problems ||= compare_with_baseline
      end

      # Whether the report agrees with {Coverage.baseline}. Always true
      # without a baseline: missing outcomes alone never fail.
      #
      # @return [Boolean]
      def passed?
        baseline_problems.values.all?(&:empty?)
      end

      # What to change so the report agrees with the baseline, or +nil+ when
      # it already does.
      #
      # @return [String, nil]
      def baseline_message
        return if passed?

        problems = baseline_problems
        lines = ["Actionable outcome coverage differs from the baseline in #{Coverage.baseline}."]
        unless problems[:new_gaps].empty?
          lines << 'New untested outcomes. Write a spec that reaches each one, or add it to the baseline:'
          lines.concat(entry_lines(problems[:new_gaps]))
        end
        unless problems[:stale].empty?
          lines << 'Covered, or no longer declared. Remove each one from the baseline:'
          lines.concat(entry_lines(problems[:stale]))
        end
        lines << 'To rewrite the baseline from the current gaps, run the report with ' \
                 'ACTIONABLE_COVERAGE_UPDATE_BASELINE=true.'
        lines.join("\n")
      end

      private

      # @return [Hash{String=>Set<String>}] outcome keys reached, by action name
      def keys_by_action(observations)
        observations.each_with_object({}) do |(name, outcome, code), by_action|
          (by_action[name.to_s] ||= Set.new) << Coverage.outcome_key(outcome, code)
        end
      end

      def all_actions
        @all_actions ||= Coverage.actions
      end

      def reported_actions
        return all_actions unless Coverage.only_observed

        all_actions.select { |klass| @observed.key?(klass.name) }
      end

      def compare_with_baseline
        return {new_gaps: {}, stale: {}} if Coverage.baseline.nil?

        baseline = load_baseline(Coverage.baseline)
        gaps = to_baseline
        new_gaps = gaps.filter_map do |action, missing|
          added = missing - baseline.fetch(action, [])
          [action, added] unless added.empty?
        end.to_h
        {new_gaps: new_gaps, stale: stale_entries(baseline, gaps)}
      end

      # Baseline entries to remove: the action is gone, or it is reported and
      # the outcome is no longer a gap (reached, or no longer expected).
      def stale_entries(baseline, gaps)
        known = all_actions.map(&:name)
        reported = rows.map { |row| row[:action] }
        baseline.filter_map do |action, keys|
          stale = if !known.include?(action) then keys
                  elsif reported.include?(action) then keys - gaps.fetch(action, [])
                  else []
                  end
          [action, stale] unless stale.empty?
        end.to_h
      end

      def load_baseline(path)
        raise Actionable::Error, "Coverage.baseline #{path} does not exist; write it with Report#write_baseline" unless File.exist?(path)

        data = yaml?(path) ? YAML.safe_load_file(path) : Oj.load(File.read(path), mode: :compat)
        (data || {}).to_h { |action, keys| [action.to_s, Array(keys).map(&:to_s)] }
      end

      def entry_lines(entries)
        entries.map { |action, keys| "  #{action}: #{keys.join(", ")}" }
      end

      def yaml?(path)
        path.to_s.end_with?('.yml', '.yaml')
      end
    end
  end
end
