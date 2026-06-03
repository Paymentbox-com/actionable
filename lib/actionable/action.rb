# frozen_string_literal: true

module Actionable
  # Base class for service objects. Subclass it, declare an ordered list of
  # steps with {.step}, implement each step as an instance method, and run it
  # with {.run} (decisions D1/D2).
  #
  #   class Greet < Actionable::Action
  #     step :build_message
  #     def build_message = @message = 'hello'
  #   end
  #
  #   Greet.run # => #<Actionable::Success ...>
  class Action
    class << self
      # The ordered, deduplicated set of steps declared on this action.
      # A +Set+ keyed by step identity ([type, name]) so a redeclared step
      # collapses to one entry; insertion order is preserved (decision D2).
      #
      # @return [Set<Steps::Base>]
      def steps
        @steps ||= Set.new
      end

      # Output field names that would collide with the result's own attributes
      # (so delegation silently breaks) or with the action's reserved instance
      # variables (+@result+ / +@input+, which the runner reads). Declaring one
      # raises a {DefinitionError} (decision D18).
      RESERVED_OUTPUT_FIELDS = %i[code message output history errors result input].freeze

      # Declare the action's typed output schema, or read it back.
      #
      # With a block, builds an anonymous +FieldStruct::Base+ subclass from the
      # FieldStruct DSL (+required+/+optional+/…) and stores it as this action's
      # output schema (decision D6). At the end of a run the {Runner} captures
      # the instance variables whose names match declared fields, coerces them
      # through the schema, and assigns the struct to +result.output+. Field names
      # in {RESERVED_OUTPUT_FIELDS} raise a {DefinitionError}.
      #
      #   output do
      #     required :invoice, Invoice
      #     optional :receipt, Receipt
      #   end
      #
      # @yield the FieldStruct field declarations
      # @raise [DefinitionError] when a field name is reserved
      # @return [Class<FieldStruct::Base>, nil] the output schema, or +nil+ when
      #   none has been declared (the free-form path)
      def output(&block)
        return @output_schema unless block

        schema = Class.new(FieldStruct::Base, &block)
        conflicting = schema.attribute_names & RESERVED_OUTPUT_FIELDS
        unless conflicting.empty?
          raise DefinitionError,
            "#{name || "action"}: output field(s) #{conflicting.map(&:inspect).join(", ")} " \
            'conflict with reserved result attributes / instance variables; rename them'
        end

        @output_schema = schema
      end

      # @return [Class<FieldStruct::Base>, nil] the declared output schema, or
      #   +nil+ for a free-form action
      attr_reader :output_schema

      # Declare the action's typed input schema (decision D7). Builds an
      # anonymous +FieldStruct::Base+ subclass from the FieldStruct DSL; +.run+
      # then coerces its arguments into this schema, validates them, and exposes
      # the struct to steps via the instance's +input+ reader. Declaring input
      # takes over the constructor role — steps read +input.field+ rather than
      # capturing positional/keyword args in a custom +initialize+.
      #
      #   input do
      #     required :amount, :big_decimal
      #     optional :name,   :string
      #   end
      #
      # @yield the FieldStruct field declarations
      # @return [Class<FieldStruct::Base>] the input schema
      def input(&block)
        @input_schema = Class.new(FieldStruct::Base, &block)
      end

      # @return [Class<FieldStruct::Base>, nil] the declared input schema, or
      #   +nil+ for a free-form action
      attr_reader :input_schema

      # Declare a step. The step type is inferred from +target+ (a Symbol or
      # String names an instance method — a {Steps::Method}).
      #
      # @param target [Symbol, String] the step target
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+)
      # @return [Set<Steps::Base>] the updated step set
      def step(target, **options)
        steps << Steps.build(target, **options)
      end

      # Lifecycle hooks that run after the main steps when the run succeeds.
      # @return [Set<Steps::Base>]
      def success_hooks
        @success_hooks ||= Set.new
      end

      # Lifecycle hooks that run after the main steps when the run fails.
      # @return [Set<Steps::Base>]
      def failure_hooks
        @failure_hooks ||= Set.new
      end

      # Lifecycle hooks that run after the main steps when the run was skipped.
      # @return [Set<Steps::Base>]
      def skip_hooks
        @skip_hooks ||= Set.new
      end

      # Lifecycle hooks that run after the main steps regardless of outcome.
      # @return [Set<Steps::Base>]
      def always_hooks
        @always_hooks ||= Set.new
      end

      # Declare a hook that runs at the end of a run iff it succeeded (D2).
      # @param target [Symbol, String] the instance method to run
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+)
      # @return [Set<Steps::Base>]
      def on_success(target, **options)
        success_hooks << Steps.build(target, **options)
      end

      # Declare a hook that runs at the end of a run iff it failed (D2).
      # @param target [Symbol, String] the instance method to run
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+)
      # @return [Set<Steps::Base>]
      def on_failure(target, **options)
        failure_hooks << Steps.build(target, **options)
      end

      # Declare a hook that runs at the end of a run iff it was skipped (D17).
      # @param target [Symbol, String] the instance method to run
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+)
      # @return [Set<Steps::Base>]
      def on_skip(target, **options)
        skip_hooks << Steps.build(target, **options)
      end

      # Declare a hook that runs at the end of a run regardless of outcome (D2).
      # @param target [Symbol, String] the instance method to run
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+)
      # @return [Set<Steps::Base>]
      def always(target, **options)
        always_hooks << Steps.build(target, **options)
      end

      # Declare a branching step (decision D3). The switch value is read from
      # +value_source+ (an instance method); the block declares branches with
      # +on(value, target)+ and an optional +default(target)+.
      #
      #   case_step :status do
      #     on 'active', :handle_active
      #     default :handle_unknown
      #   end
      #
      # @param value_source [Symbol, String] the method whose value is switched on
      # @param options [Hash{Symbol=>Object}] step options (e.g. +:if+, +:unless+)
      # @yield the branch declarations
      # @return [Set<Steps::Base>] the updated step set
      def case_step(value_source, **options, &block)
        steps << Steps::Case.define(value_source, **options, &block)
      end

      # Enable or read the action's measurement mode (decision D10). +:all+
      # records an execution {History}; +:none+ (the default) records nothing
      # for zero overhead. A measuring run cascades into the nested actions it
      # invokes regardless of their own setting.
      #
      # @param mode [:all, :none, nil] the mode to set; omit to read
      # @return [:all, :none] the resolved mode
      def measure(mode = nil)
        unless mode.nil?
          raise ArgumentError, "unknown measure mode #{mode.inspect}" unless %i[all none].include?(mode)

          @measure = mode
        end
        @measure ||= :none
      end

      # @return [Boolean] whether this action records history
      def measure_all?
        measure == :all
      end

      # A structured, at-a-glance summary of the action — its name, input/output
      # field metadata, ordered steps (with type), lifecycle hooks, measurement
      # mode, and transaction config (decision D18). Lets humans and agents
      # understand an action without reading its source.
      #
      # @return [Hash{Symbol=>Object}]
      def describe
        {
          name: name,
          input: input_schema&.metadata&.to_h,
          output: output_schema&.metadata&.to_h,
          steps: steps.map { |step| {type: step.kind, name: step.name, options: step.options} },
          hooks: {
            on_success: success_hooks.map(&:name),
            on_failure: failure_hooks.map(&:name),
            on_skip: skip_hooks.map(&:name),
            always: always_hooks.map(&:name)
          },
          measure: measure,
          transactional: respond_to?(:transaction_config) ? transaction_config : nil
        }
      end

      # A human/agent-readable rendering of {.describe} — the same information as
      # a multi-line summary instead of a Hash (decision D18). The input/output
      # field lines reuse FieldStruct's own +Metadata#describe+ (type,
      # required-ness, and the options each field's type accepts); only hook
      # sections that have hooks are listed.
      #
      #   Greet.describe_text
      #   # => "Greet (measure: none)\n  Input: (free-form)\n  ..."
      #
      # @return [String]
      def describe_text
        summary = describe
        transactional = summary[:transactional] ? ', transactional' : ''
        lines = ["#{summary[:name] || "action"} (measure: #{summary[:measure]}#{transactional})"]

        lines << "  Input:#{schema_summary(input_schema)}"
        lines << "  Output:#{schema_summary(output_schema)}"

        lines << '  Steps:'
        steps_summary = summary[:steps]
        lines << '    (none)' if steps_summary.empty?
        steps_summary.each { |step| lines << "    - #{step[:name]} (#{step[:type]})" }

        present_hooks = summary[:hooks].reject { |_, names| names.empty? }
        unless present_hooks.empty?
          lines << '  Hooks:'
          present_hooks.each { |section, names| lines << "    #{section}: #{names.join(", ")}" }
        end

        lines.join("\n")
      end

      # Run the action. With a declared input schema, coerce the arguments
      # (keyword args, or a single input-schema instance) into the input struct
      # and validate it — a required input that is missing or won't coerce
      # short-circuits to a +Failure(:invalid_input)+ without running any steps
      # (decision D7). Without an input schema, the arguments are forwarded
      # verbatim to the action's constructor (the free-form path).
      #
      # @return [Result] the run's {Success} or {Failure}
      def run(*args, **kwargs)
        if input_schema
          input = build_input(args, kwargs)
          return invalid_input_failure(input) unless input.valid?

          instance = new
          instance.instance_variable_set(:@input, input)
        else
          instance = new(*args, **kwargs)
        end

        ensure_steps_implemented!(instance)
        Runner.new(instance).run
      end

      private

      # One {.describe_text} block for an input/output schema: +" (free-form)"+
      # when none is declared, otherwise the FieldStruct +Metadata#describe+
      # field lines indented one level under their +Input:+/+Output:+ heading.
      #
      # @param schema [Class<FieldStruct::Base>, nil]
      # @return [String]
      def schema_summary(schema)
        return ' (free-form)' unless schema

        "\n#{schema.metadata.describe.lines(chomp: true).map { |line| "  #{line}" }.join("\n")}"
      end

      # Run-start guard (decision D18): every method a step needs (method steps,
      # case value sources and method branch targets, hook steps) must exist on
      # the instance, or raise a clear {DefinitionError} rather than a deep
      # +NoMethodError+. This is the earliest reliable point — steps are usually
      # declared above the methods that implement them.
      #
      # @param instance [Action]
      # @return [void]
      def ensure_steps_implemented!(instance)
        all = steps.to_a + success_hooks.to_a + failure_hooks.to_a + skip_hooks.to_a + always_hooks.to_a
        missing = all.flat_map(&:required_methods).uniq.reject { |method| instance.respond_to?(method, true) }
        return if missing.empty?

        raise DefinitionError,
          "#{name || "action"} declares step(s) calling #{missing.map(&:inspect).join(", ")} " \
          'but does not implement them'
      end

      # Coerce +.run+ arguments into the input struct: pass an existing input
      # instance through untouched, otherwise build one from the keyword args.
      #
      # @return [FieldStruct::Base]
      def build_input(args, kwargs)
        candidate = args.first
        return candidate if args.size == 1 && candidate.is_a?(input_schema)

        input_schema.new(**kwargs)
      end

      # @param input [FieldStruct::Base] the invalid input struct
      # @return [Failure] code +:invalid_input+, carrying the input's errors
      def invalid_input_failure(input)
        Failure.new(code: :invalid_input, message: 'input failed validation')
          .absorb_errors_from(input)
      end

      public

      # Give each subclass its own copy of the inherited step set, so adding
      # steps to a subclass never mutates the parent's (decision D2).
      #
      # @param subclass [Class]
      # @return [void]
      def inherited(subclass)
        super
        Actionable.registry.register(subclass)
        subclass.instance_variable_set(:@steps, steps.dup)
        subclass.instance_variable_set(:@output_schema, output_schema)
        subclass.instance_variable_set(:@input_schema, input_schema)
        subclass.instance_variable_set(:@success_hooks, success_hooks.dup)
        subclass.instance_variable_set(:@failure_hooks, failure_hooks.dup)
        subclass.instance_variable_set(:@skip_hooks, skip_hooks.dup)
        subclass.instance_variable_set(:@always_hooks, always_hooks.dup)
        subclass.instance_variable_set(:@measure, measure)
      end
    end

    # Default free-form constructor: accept and ignore any arguments, so an
    # action with no declared input still runs via {.run}. Subclasses override
    # this to capture their inputs (decision D7; typed input lands in a later
    # slice).
    def initialize(*_args, **_kwargs)
    end

    # The result recorded during the run, if any. The control-flow methods
    # (+fail+/+succeed+/+fail!+/+succeed!+) write here; +nil+ means "no explicit
    # result", which the {Runner} turns into an auto-{Success}.
    #
    # @return [Result, nil]
    attr_reader :result

    # The typed input struct for this run, when an +input+ schema is declared
    # (decision D7); +nil+ for a free-form action. Steps read +input.field+.
    #
    # @return [FieldStruct::Base, nil]
    attr_reader :input

    private

    # Record a {Failure} as the run's result without halting — later steps
    # still run, and the final result reflects the most recent record (decision
    # D4, "last write wins").
    #
    # @param code [Symbol] the error code
    # @param message [String, nil] human-readable description
    # @param errors [Hash{Symbol=>String, Array<String>}] field => message(s)
    #   added to the result's errors collection
    # @return [false] so a step can branch on the call
    def fail(code, message = nil, **errors)
      failure = Failure.new(code: code, message: message)
      errors.each { |field, messages| Array(messages).each { |m| failure.errors.add(field, m) } }
      @result = failure
      false
    end

    # Record a {Failure} that absorbs an arbitrary FieldStruct's validation
    # errors, without halting (decision D19). The same machinery
    # +Failure(:invalid_input)+ / +Failure(:invalid_output)+ use internally,
    # exposed as a verb so a step can validate a side struct and fail with its
    # errors directly.
    #
    #   def validate = fail_with(EventShape.new(payload), code: :invalid_event)
    #
    # @param source [#errors] any object exposing a FieldStruct-style +errors+
    #   collection (typically a +FieldStruct::Base+ instance)
    # @param code [Symbol] the error code; defaults to +:invalid+
    # @param message [String, nil] human-readable description
    # @return [false] so a step can branch on the call
    def fail_with(source, code: :invalid, message: nil)
      @result = Failure.new(code: code, message: message).absorb_errors_from(source)
      false
    end

    # Record a {Failure} absorbing +source+'s errors and halt the run
    # (decision D19). The halting companion to {#fail_with}.
    #
    # @param source [#errors] see {#fail_with}
    # @param code [Symbol] the error code; defaults to +:invalid+
    # @param message [String, nil] human-readable description
    # @return [void]
    def fail_with!(source, code: :invalid, message: nil)
      fail_with(source, code: code, message: message)
      halt!
    end

    # Record a {Success} as the run's result without halting (decision D4).
    #
    # @param message [String, nil] human-readable description
    # @param output [Hash{Symbol=>Object}] the success output payload
    # @return [true] so a step can branch on the call
    def succeed(message = nil, **output)
      @result = Success.new(message: message, output: output)
      true
    end

    # Record a {Failure} and halt the run, skipping the remaining steps
    # (decision D4).
    #
    # @param code [Symbol] the error code
    # @param message [String, nil] human-readable description
    # @param errors [Hash{Symbol=>String, Array<String>}] field => message(s)
    # @raise [UncaughtThrowError] never escapes the {Runner}'s halt catch
    # @return [void]
    def fail!(code, message = nil, **errors)
      fail(code, message, **errors)
      halt!
    end

    # Record a {Success} and halt the run, skipping the remaining steps
    # (decision D4).
    #
    # @param message [String, nil] human-readable description
    # @param output [Hash{Symbol=>Object}] the success output payload
    # @return [void]
    def succeed!(message = nil, **output)
      succeed(message, **output)
      halt!
    end

    # Record a {Skipped} as the run's result without halting — the action had
    # nothing to do (decision D17). Not a failure; later steps still run and the
    # final result reflects the most recent record (last write wins).
    #
    # @param code [Symbol] the skip reason; defaults to +:skipped+
    # @param message [String, nil] human-readable description
    # @param output [Hash{Symbol=>Object}] the skip output payload — captured
    #   best-effort like a {Success}'s output, but never validated (decision
    #   D17). Lets an idempotent hit return the existing record's data.
    # @return [false] so a step can branch on the call (the run did not succeed here)
    def skip(code = :skipped, message = nil, **output)
      @result = Skipped.new(code: code, message: message, output: output)
      false
    end

    # Record a {Skipped} and halt the run, skipping the remaining steps — the
    # common "nothing to do, stop here" case (decision D17).
    #
    # @param code [Symbol] the skip reason; defaults to +:skipped+
    # @param message [String, nil] human-readable description
    # @param output [Hash{Symbol=>Object}] the skip output payload (see {#skip})
    # @return [void]
    def skip!(code = :skipped, message = nil, **output)
      skip(code, message, **output)
      halt!
    end

    # Halt the run immediately, keeping whatever result was already recorded
    # (a prior +fail+/+succeed+/+skip+, or auto-{Success} if none). Control flow
    # only — not an exception (decision D4).
    #
    # @return [void]
    def halt!
      throw HALT
    end
  end
end
