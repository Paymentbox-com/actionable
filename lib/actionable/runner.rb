# frozen_string_literal: true

module Actionable
  # Executes an action instance's steps and produces the {Result}.
  #
  # The main loop runs inside {Actionable.catch_halt}, so a halting step
  # (+throw Actionable::HALT+) unwinds out of the loop without running the
  # remaining steps. Genuine exceptions are not caught — they propagate to the
  # caller (decision D4). When no step recorded a result, the run auto-succeeds.
  class Runner
    # @param instance [Action] the action instance to run
    def initialize(instance)
      @instance = instance
    end

    # Run the action's steps and return its finalized result.
    #
    # @return [Result] the recorded result (or a fresh {Success} if none was
    #   set), with its typed output captured and assigned
    def run
      Actionable.catch_halt { run_steps }
      finalize(@instance.result || Success.new)
    end

    private

    # Run each declared step in order, skipping any whose guard opts out.
    #
    # @return [void]
    def run_steps
      @instance.class.steps.each do |step|
        next if step.skip?(@instance)

        step.call(@instance)
      end
    end

    # Build and attach the typed output (decision D6). Free-form actions (no
    # output schema) keep whatever output was recorded. With a schema, capture
    # the declared-field ivars overlaid with any +succeed+ kwargs (kwargs win)
    # and coerce them through the schema. A successful run whose output fails
    # validation can't really have succeeded — it becomes a +Failure+ with code
    # +:invalid_output+. Failures are captured best-effort and never validated.
    #
    # @param result [Result]
    # @return [Result]
    def finalize(result)
      schema = @instance.class.output_schema
      return result unless schema

      output = schema.new(**captured_attributes(schema, result))

      if result.failure?
        result.output = output
        return result
      end

      return invalid_output_failure(output) unless output.valid?

      result.output = output
      result
    end

    # Declared-field ivars from the action instance, overlaid with the recorded
    # +succeed+ kwargs (kept on +result.output+ as a Hash until now), kwargs
    # winning on conflict.
    #
    # @param schema [Class<FieldStruct::Base>]
    # @param result [Result]
    # @return [Hash{Symbol=>Object}]
    def captured_attributes(schema, result)
      attrs = {}
      schema.attribute_names.each do |name|
        ivar = :"@#{name}"
        attrs[name] = @instance.instance_variable_get(ivar) if @instance.instance_variable_defined?(ivar)
      end
      overrides = result.output.is_a?(Hash) ? result.output : {}
      attrs.merge(overrides.slice(*schema.attribute_names))
    end

    # @param output [FieldStruct::Base] the invalid output struct
    # @return [Failure] code +:invalid_output+, with the output's validation
    #   errors copied onto the failure and the (invalid) output attached
    def invalid_output_failure(output)
      failure = Failure.new(code: :invalid_output, message: 'output failed validation')
      output.errors.to_h.each { |field, messages| messages.each { |m| failure.errors.add(field, m) } }
      failure.output = output
      failure
    end
  end
end
