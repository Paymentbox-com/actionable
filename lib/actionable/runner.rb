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
  # control-flow verbs and +halt!+ stops the remaining hooks. The output is
  # refreshed (re-captured and re-validated) after the main steps and after each
  # hook (decision D6).
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
      @measuring = @instance.class.measure_all? || Measurement.active?
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
      @result = @instance.result || Success.new
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
    #
    # @param section [Symbol]
    # @param hook [Steps::Base]
    # @return [void]
    def run_hook(section, hook)
      return if hook.skip?(@instance)

      before = @instance.result
      record(section, hook) { hook.call(@instance) }
      @result = @instance.result unless @instance.result.equal?(before)
      refresh_output
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
        entry.code = @instance.result&.code unless @instance.result.equal?(before)
        @history << entry
      end
    end

    # Capture, coerce, and attach the typed output (decision D6). Free-form
    # actions (no schema) keep whatever output was recorded. With a schema,
    # capture the declared-field ivars overlaid with any +succeed+ kwargs
    # (kwargs win) and coerce them. Only a strict {Success} is validated — its
    # output failing validation means it can't really have succeeded, so
    # +@result+ becomes a +Failure(:invalid_output)+. A {Failure} or {Skipped}
    # captures best-effort and is never validated (decisions D6/D17).
    #
    # @return [void]
    def refresh_output
      schema = @instance.class.output_schema
      return unless schema

      output = schema.new(**captured_attributes(schema))

      unless @result.success?
        @result.output = output
        return
      end

      output.valid? ? (@result.output = output) : (@result = invalid_output_failure(output))
    end

    # Declared-field ivars from the action instance, overlaid with the recorded
    # +succeed+ kwargs (kept on +@result.output+ as a Hash until captured),
    # kwargs winning on conflict.
    #
    # @param schema [Class<FieldStruct::Base>]
    # @return [Hash{Symbol=>Object}]
    def captured_attributes(schema)
      attrs = {}
      schema.attribute_names.each do |name|
        ivar = :"@#{name}"
        attrs[name] = @instance.instance_variable_get(ivar) if @instance.instance_variable_defined?(ivar)
      end
      overrides = @result.output.is_a?(Hash) ? @result.output : {}
      attrs.merge(overrides.slice(*schema.attribute_names))
    end

    # @param output [FieldStruct::Base] the invalid output struct
    # @return [Failure] code +:invalid_output+, with the output's validation
    #   errors copied onto the failure and the (invalid) output attached
    def invalid_output_failure(output)
      failure = Failure.new(code: :invalid_output, message: 'output failed validation')
        .absorb_errors_from(output)
      failure.output = output
      failure
    end
  end
end
