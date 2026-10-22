# frozen_string_literal: true

module Actionable
  # Executes an action instance's steps and produces the {Result}.
  #
  # The main loop runs inside {Actionable.catch_halt}, so a halting step
  # (+throw Actionable::HALT+) unwinds out of the loop without running the
  # remaining steps. Genuine exceptions are not caught — they propagate to the
  # caller (decision D4). When no step recorded a result, the run auto-succeeds.
  #
  # After the main steps the runner picks the lifecycle hook category from the
  # outcome (+on_success+ vs +on_failure+) and runs it, then the +always+ hooks
  # (decision D2). Hooks are ordinary methods: they may record via the
  # control-flow verbs, and a halting verb (+fail!+ / +skip!+ / +succeed!+ /
  # +halt!+) has its result adopted, then stops the remaining hooks. The output
  # is refreshed (re-captured and re-validated) after the main steps and after
  # each hook (decision D6).
  #
  # When the action (or an enclosing measuring run) enables measurement, the
  # runner records a {History} of every step — section, name, timing, result
  # code, and nested child history (decision D10).
  class Runner
    # @param instance [Action] the action instance to run
    def initialize(instance)
      @instance = instance
    end

    # Run the action's steps and lifecycle hooks, returning the finalized result.
    #
    # @return [Result] the recorded result (or a fresh {Success} if none was
    #   set), with its typed output and (when measuring) history assigned
    def run
      @measuring = @instance.class.measure_all? || @instance.class.measure_sample_hit? || Measurement.active?
      @history = History.new if @measuring
      measured { perform }
      @result.history = @history if @measuring
      @result
    end

    private

    # Run the body, marking measurement active so nested runs cascade.
    def measured(&)
      return yield unless @measuring

      Measurement.measuring(&)
    end

    # The main steps, then the outcome and always lifecycle hooks.
    def perform
      Actionable.catch_halt { run_steps }
      @result = instance_result || Success.new
      refresh_output
      run_lifecycle
    end

    # Run each declared step in order, skipping any whose guard opts out.
    #
    # @return [void]
    def run_steps
      @instance.class.steps.each { |step| call_step(:main, step) }
    end

    # Run the outcome-appropriate hooks then the +always+ hooks, all inside a
    # single halt catch so a hook's +halt!+ stops every remaining hook. The
    # category is fixed by the post-main-steps outcome — it does not re-dispatch
    # if a hook later flips the result.
    #
    # @return [void]
    def run_lifecycle
      section, hooks =
        if @result.success?
          [:success, @instance.class.success_hooks]
        elsif @result.skipped?
          [:skip, @instance.class.skip_hooks]
        else
          [:failure, @instance.class.failure_hooks]
        end
      Actionable.catch_halt do
        hooks.each { |hook| run_hook(section, hook) }
        @instance.class.always_hooks.each { |hook| run_hook(:always, hook) }
      end
    end

    # Run one hook, then adopt any result it recorded and refresh the output.
    # A hook that halts is caught here first so its result is adopted too, then
    # the halt is re-thrown to stop the remaining hooks.
    #
    # @param section [Symbol]
    # @param hook [Steps::Base]
    # @return [void]
    def run_hook(section, hook)
      return if hook.skip?(@instance)

      before = @instance.result
      completed = false
      Actionable.catch_halt do
        record(section, hook) { hook.call(@instance) }
        completed = true
      end
      @result = instance_result unless instance_result.equal?(before)
      refresh_output
      throw HALT unless completed
    end

    # Run one main step, skipping it when its guard opts out.
    #
    # @param section [Symbol]
    # @param step [Steps::Base]
    # @return [void]
    def call_step(section, step)
      return if step.skip?(@instance)

      record(section, step) { step.call(@instance) }
    end

    # Time and record a step into the history when measuring; otherwise just run
    # it. The result code is recorded only when the step changed the recorded
    # result, so steps that merely set ivars carry a nil code.
    #
    # @param section [Symbol]
    # @param step [Steps::Base]
    # @return [void]
    def record(section, step, &)
      return yield unless @measuring

      entry = History::Step.new(section: section, name: step.name, started_at: Time.now)
      before = @instance.result
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        Measurement.recording(entry, &)
      ensure
        entry.duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        entry.code = instance_result&.code unless @instance.result.equal?(before)
        @history << entry
      end
    end

    # Capture, coerce, and attach the typed output (decision D6). Free-form
    # actions (no schema) keep whatever output was recorded. With a schema,
    # capture the declared-field ivars overlaid with any +succeed+ kwargs
    # (kwargs win) and coerce them. Only a strict {Success} is validated — its
    # output failing validation means it can't really have succeeded, so
    # +@result+ becomes a +Failure(:invalid_output)+.
    #
    # A {Failure} or {Skipped} whose code declares its own output schema
    # (decision D23) is built from its kwargs alone and validated the same way.
    # Without one it carries an empty output under typed outcomes, and
    # otherwise a best-effort, unvalidated capture into the success schema
    # (decisions D6/D17). The failures the gem builds keep their output.
    #
    # @return [void]
    def refresh_output
      return refresh_success_output if @result.success?

      if (schema = outcome_schema)
        attach_validated(build_output(schema, outcome_attributes(schema)))
      elsif @instance.class.typed_outcomes?
        @result.output = {} unless gem_failure?
      elsif (schema = @instance.class.output_schema) && !gem_failure?
        attach_unvalidated(build_output(schema, captured_attributes(schema)))
      end
    end

    # @return [void]
    def refresh_success_output
      schema = @instance.class.output_schema
      return unless schema

      attach_validated(build_output(schema, captured_attributes(schema)))
    end

    # Build the output struct and note on the result which fields the run
    # actually set, so a parent absorbing this run copies only those (D3).
    #
    # @param schema [Class<FieldStruct::Base>]
    # @param attrs [Hash{Symbol=>Object}]
    # @return [FieldStruct::Base]
    def build_output(schema, attrs)
      @result.output_fields_set = attrs.keys
      schema.new(**attrs)
    end

    # The result the action instance recorded, refusing anything else stored
    # in the reserved +@result+ ivar with a clear error instead of a deep
    # +NoMethodError+.
    #
    # @raise [DefinitionError] when +@result+ holds something other than a {Result}
    # @return [Result, nil]
    def instance_result
      result = @instance.result
      return result if result.nil? || result.is_a?(Result)

      raise DefinitionError,
        "#{@instance.class.name || "action"} set @result to a #{result.class}; " \
        '@result is reserved for the run\'s result, so rename the instance variable'
    end

    # Attach +output+ when it is valid; otherwise the run ends as a
    # +Failure(:invalid_output)+ carrying it.
    #
    # @param output [FieldStruct::Base]
    # @return [void]
    def attach_validated(output)
      output.valid? ? (@result.output = output) : (@result = invalid_output_failure(output))
    end

    # Attach a best-effort output to a failure or skip without validating it
    # (decisions D6/D17). Assigning a struct makes the result validate it, which
    # would add an +output+ error, so only the errors the result already had
    # are kept.
    #
    # @param output [FieldStruct::Base]
    # @return [void]
    def attach_unvalidated(output)
      kept = Array(@result.errors.to_h[:output]).dup
      @result.output = output
      @result.errors.clear(:output)
      kept.each { |message| @result.errors.add(:output, message) }
    end

    # @return [Class<FieldStruct::Base>, nil] the output schema the skip or
    #   failure's code declares (decision D23), if any
    def outcome_schema
      klass = @instance.class
      @result.skipped? ? klass.skip_output_schema(@result.code) : klass.failure_output_schema(@result.code)
    end

    # A skip or failure's output fields, from the kwargs it was recorded with,
    # never from instance variables (decision D23). After a hook refresh the
    # output is already the struct, so its own attributes are reused.
    #
    # @param schema [Class<FieldStruct::Base>]
    # @return [Hash{Symbol=>Object}]
    def outcome_attributes(schema)
      recorded = @result.output
      recorded = recorded.attributes if recorded.is_a?(FieldStruct::Base)
      recorded.is_a?(Hash) ? recorded.slice(*schema.attribute_names) : {}
    end

    # @return [Boolean] whether the result is a failure the gem itself built
    #   ({Action::GEM_FAILURE_CODES}), whose output is left as it is
    def gem_failure?
      @result.failure? && Action::GEM_FAILURE_CODES.include?(@result.code)
    end

    # Declared-field ivars from the action instance, overlaid with the recorded
    # +succeed+ / +skip+ kwargs, kwargs winning on conflict.
    #
    # @param schema [Class<FieldStruct::Base>]
    # @return [Hash{Symbol=>Object}]
    def captured_attributes(schema)
      attrs = {}
      schema.attribute_names.each do |name|
        ivar = :"@#{name}"
        attrs[name] = @instance.instance_variable_get(ivar) if @instance.instance_variable_defined?(ivar)
      end
      attrs.merge(recorded_overrides.slice(*schema.attribute_names))
    end

    # The +succeed+ / +skip+ kwargs recorded with the current result. They sit
    # on +@result.output+ as a Hash only until the first refresh replaces it
    # with the struct, so they are kept here to overlay every later refresh
    # (after each hook) as well.
    #
    # @return [Hash{Symbol=>Object}]
    def recorded_overrides
      if @result.output.is_a?(Hash)
        @overrides_owner = @result
        @overrides = @result.output
      end
      @overrides_owner.equal?(@result) ? @overrides : {}
    end

    # @param output [FieldStruct::Base] the invalid output struct
    # @return [Failure] code +:invalid_output+, with the output's validation
    #   errors copied onto the failure and the (invalid) output attached
    def invalid_output_failure(output)
      failure = Failure.new(
        code: :invalid_output,
        message: 'output failed validation',
        metadata: @instance.class.declared_failures.fetch(:invalid_output, {})
      ).absorb_errors_from(output)
      failure.output = output
      failure
    end
  end
end
