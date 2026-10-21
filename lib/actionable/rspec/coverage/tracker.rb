# frozen_string_literal: true

require 'fileutils'
require 'oj'
require_relative '../../../actionable'

module Actionable
  # Outcome coverage for a test suite (decision D22). While enabled, every real
  # +.run+ of a named action class is recorded as +[class name, outcome, code]+,
  # where outcome is +:success+, +:failure+ or +:skipped+. At the end of the
  # suite those observations are compared with the outcomes each action can
  # end with (its declarations, read at run time), and the outcomes no spec
  # reached are reported.
  #
  # Loaded by +require 'actionable/rspec/coverage'+, which also installs the
  # suite hook. Nothing here is loaded by the core.
  module Coverage
    # Prepended onto {Actionable::Action}'s singleton class, so every
    # subclass's +.run+ (nested {Steps::Action} runs and {Action.run_each}
    # included) passes through it. An RSpec stub of +.run+ defines the method
    # on the subclass itself, ahead of this module, so a stubbed run is never
    # recorded as the action being tested.
    module Recorder
      # Run the action and record the result's outcome.
      #
      # @return [Result]
      def run(*, **)
        result = super
        Coverage.record(self, result)
        result
      end
    end

    @mutex = Mutex.new
    @observed = Set.new
    @stubbed = Set.new
    @enabled = false

    class << self
      # The class whose named descendants are reported. Defaults to
      # {Actionable::Action}.
      # @return [Class<Actionable::Action>]
      attr_accessor :root

      # Name filters for the report. A String matches as a name prefix, a
      # Regexp by +match?+. With any include filter, only matching names are
      # reported; an exclude filter drops matching names.
      # @return [Array<String, Regexp>]
      attr_accessor :include_prefixes, :exclude_prefixes

      # Called before the actions are listed, so a host can load every action
      # class first (+-> { Rails.application.eager_load! }+). Unloaded classes
      # cannot be reported.
      # @return [#call, nil]
      attr_accessor :loader

      # When true, report only actions with at least one real run, so a
      # partial or targeted run doesn't flag every action it never touched.
      # @return [Boolean]
      attr_accessor :only_observed

      # Path to the committed baseline of known gaps, a JSON or YAML file of
      # +{"Action::Name" => [outcome keys]}+. With one set, the report fails
      # on a gap the baseline doesn't list and on a stale entry; see
      # {Report#baseline_problems}. +nil+ (the default) never fails.
      # @return [String, nil]
      attr_accessor :baseline

      # @return [Array<Symbol>] the gem failure codes counted as expected
      #   outcomes; see {.gem_codes=}
      attr_reader :gem_codes

      # Count some of {Actionable::Action::GEM_FAILURE_CODES} as expected
      # outcomes. +:invalid_input+ counts for an action whose input has a
      # required field; +:invalid_output+ for one whose output has a required
      # field. Defaults to none, so an adopter opts in.
      #
      # @param codes [Array<Symbol, String>]
      # @raise [ArgumentError] for a code the gem never emits
      # @return [void]
      def gem_codes=(codes)
        codes = Array(codes).map(&:to_sym)
        unknown = codes - Actionable::Action::GEM_FAILURE_CODES
        unless unknown.empty?
          raise ArgumentError,
            "not a gem failure code: #{unknown.map(&:inspect).join(", ")} " \
            "(the gem emits #{Actionable::Action::GEM_FAILURE_CODES.map(&:inspect).join(", ")})"
        end

        @gem_codes = codes
      end

      # Restore every setting to its default.
      #
      # @return [void]
      def reset_config!
        @root = Actionable::Action
        @include_prefixes = []
        @exclude_prefixes = []
        @loader = nil
        @gem_codes = []
        @only_observed = false
        @baseline = nil
      end

      # The outcomes +action_class+ can end with, as outcome keys:
      # +"success"+, +"failure:<code>"+ for each declared failure (D20) and
      # +"skipped:<code>"+ for each declared skip (D21), plus any configured
      # {.gem_codes} that apply. Read from the declarations at run time.
      #
      # @param action_class [Class<Actionable::Action>]
      # @return [Array<String>]
      def expected_outcomes(action_class)
        keys = ['success']
        keys.concat(action_class.declared_failures.keys.map { |code| "failure:#{code}" })
        keys.concat(action_class.declared_skips.keys.map { |code| "skipped:#{code}" })
        gem_codes.each { |code| keys << "failure:#{code}" if gem_code_applies?(action_class, code) }
        keys.uniq
      end

      # The action classes to report: named descendants of {.root} that have
      # steps, whose name still resolves to the class, filtered by
      # {.include_prefixes} and {.exclude_prefixes}. Calls {.loader} first.
      #
      # @return [Array<Class<Actionable::Action>>] sorted by name
      def actions
        loader&.call
        descendants(root).select { |klass| reportable?(klass) }.sort_by(&:name)
      end

      # The outcome key an observation counts toward: +"success"+, or
      # +"<outcome>:<code>"+.
      #
      # @param outcome [Symbol, String]
      # @param code [Symbol, String]
      # @return [String]
      def outcome_key(outcome, code)
        outcome.to_s == 'success' ? 'success' : "#{outcome}:#{code}"
      end

      # Start recording runs. Installs {Recorder} the first time; safe to call
      # again.
      #
      # @return [void]
      def enable!
        singleton = Actionable::Action.singleton_class
        singleton.prepend(Recorder) unless singleton.ancestors.include?(Recorder)
        @enabled = true
      end

      # Stop recording runs. {Recorder} stays installed but records nothing.
      #
      # @return [void]
      def disable!
        @enabled = false
      end

      # @return [Boolean] whether runs are being recorded
      def enabled?
        @enabled
      end

      # Record one real run. Ignores anonymous classes and anything that isn't
      # a {Result}.
      #
      # @param action_class [Class<Actionable::Action>]
      # @param result [Result]
      # @return [void]
      def record(action_class, result)
        observation = observation_for(action_class, result)
        @mutex.synchronize { @observed << observation } if observation
      end

      # Record one run answered by the gem's stub helpers
      # (+allow_actionable_success+ and the rest). Kept apart from {.observed}:
      # a stubbed outcome was never produced by the action, so it never counts
      # as tested, but the report shows it.
      #
      # @param action_class [Class<Actionable::Action>]
      # @param result [Result]
      # @return [void]
      def record_stub(action_class, result)
        observation = observation_for(action_class, result)
        @mutex.synchronize { @stubbed << observation } if observation
      end

      # The runs answered by a gem stub helper so far, deduplicated.
      #
      # @return [Set<Array(String, Symbol, Symbol)>] +[class name, outcome, code]+
      def stubbed
        @mutex.synchronize { @stubbed.dup }
      end

      # The real runs recorded so far, deduplicated.
      #
      # @return [Set<Array(String, Symbol, Symbol)>] +[class name, outcome, code]+
      def observed
        @mutex.synchronize { @observed.dup }
      end

      # Write the runs recorded so far to +path+ as JSON, for a sharded suite:
      # each shard writes its own file and one {Report} merges them. Creates
      # the directory.
      #
      # @param path [String]
      # @return [String] +path+
      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        data = {version: 1, observed: observed.to_a.sort, stubbed: stubbed.to_a.sort}
        File.write(path, Oj.dump(data, mode: :compat))
        path
      end

      # Read a file written by {.write}.
      #
      # @param path [String]
      # @return [Hash{Symbol=>Set<Array(String, Symbol, Symbol)>}] +{observed:, stubbed:}+
      def read(path)
        data = Oj.load(File.read(path), mode: :compat)
        %w[observed stubbed].to_h do |set|
          [set.to_sym, Array(data[set]).to_set { |name, outcome, code| [name, outcome.to_sym, code.to_sym] }]
        end
      end

      # Forget every recorded run, real and stubbed.
      #
      # @return [void]
      def reset!
        @mutex.synchronize do
          @observed.clear
          @stubbed.clear
        end
      end

      private

      # @return [Array<Class>] every subclass below +klass+, recursively
      def descendants(klass)
        klass.subclasses.flat_map { |subclass| [subclass, *descendants(subclass)] }
      end

      # Abstract actions are left out: an anonymous class has no name to
      # report, and an action with no steps is a base class. A class whose
      # name no longer resolves to it (a removed +stub_const+, a reloaded
      # constant) is left out too.
      def reportable?(klass)
        name = klass.name
        return false if name.nil? || klass.steps.empty?
        return false unless resolves_to?(name, klass)
        return false if include_prefixes.any? && include_prefixes.none? { |pattern| matches?(pattern, name) }

        exclude_prefixes.none? { |pattern| matches?(pattern, name) }
      end

      def resolves_to?(name, klass)
        Object.const_get(name).equal?(klass)
      rescue NameError
        false
      end

      def matches?(pattern, name)
        pattern.is_a?(Regexp) ? pattern.match?(name) : name.start_with?(pattern.to_s)
      end

      def gem_code_applies?(action_class, code)
        case code
        when :invalid_input then input_can_be_invalid?(action_class)
        when :invalid_output then output_schemas(action_class).any? { |schema| requires_field?(schema) }
        end
      end

      # A fixed input with a required field, or a discriminated input with no
      # default shape (an unmatched value fails) or a shape with one.
      def input_can_be_invalid?(action_class)
        return requires_field?(action_class.input_schema) if action_class.input_schema

        dispatch = action_class.input_dispatch
        return false unless dispatch

        dispatch.default_schema.nil? || dispatch.schemas.any? { |schema| requires_field?(schema) }
      end

      # Every output schema a run can be held to: the success's, and each skip
      # or failure code's (decision D23), any of which can end it as
      # +invalid_output+.
      def output_schemas(action_class)
        skips = action_class.skip_declarations.keys.map { |code| action_class.skip_output_schema(code) }
        failures = action_class.failure_declarations.keys.map { |code| action_class.failure_output_schema(code) }
        [action_class.output_schema, *skips, *failures].compact
      end

      def requires_field?(schema)
        return false unless schema

        schema.metadata.to_h.values.any? { |field| field[:required] }
      end

      # @return [Array(String, Symbol, Symbol), nil]
      def observation_for(action_class, result)
        return unless enabled? && result.is_a?(Actionable::Result)

        name = action_class.name
        return if name.nil?

        [name, outcome_of(result), result.code.to_sym]
      end

      # @param result [Result]
      # @return [Symbol] +:success+, +:failure+ or +:skipped+
      def outcome_of(result)
        if result.failure? then :failure
        elsif result.skipped? then :skipped
        else :success
        end
      end
    end

    reset_config!
  end
end
