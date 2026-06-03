# frozen_string_literal: true

module Actionable
  module Steps
    # A step that runs another action as part of this one (decision D3,
    # triggered by an action +Class+ step argument).
    #
    # +:input+ threads named parent instance variables into the child's +.run+;
    # +:expose+ limits which of the child's outputs are absorbed back as parent
    # instance variables (default: all). A child failure fails the parent with
    # the child's code/message/errors and halts the remaining steps.
    class Action < Base
      # Run the nested action, threading input in and absorbing output back.
      #
      # @param instance [Actionable::Action] the parent action instance
      # @return [void]
      def call(instance)
        child = name.run(**input_kwargs(instance))

        # Attach the child's history to the open step record (no-op unless the
        # parent run is measuring), before any failure propagation unwinds.
        Measurement.open_step&.nested = child.history if child.history.is_a?(History)

        if child.failure?
          # Propagate the child's failure onto the parent and halt — reusing the
          # parent's own control-flow verb keeps the record-and-halt semantics.
          instance.__send__(:fail!, child.code, child.message, **child.errors.to_h)
        else
          absorb(instance, child)
        end
      end

      # @return [Symbol]
      def kind
        :action
      end

      private

      # @param instance [Actionable::Action]
      # @return [Hash{Symbol=>Object}] +{ name => @name }+ for each +:input+ name
      def input_kwargs(instance)
        Array(options[:input]).to_h { |name| [name, instance.instance_variable_get(:"@#{name}")] }
      end

      # Copy the child's exposed output fields onto the parent as instance
      # variables, so the parent's later steps and output capture see them.
      #
      # @param instance [Actionable::Action]
      # @param child [Result]
      # @return [void]
      def absorb(instance, child)
        data = output_hash(child.output)
        exposed = options.key?(:expose) ? data.slice(*Array(options[:expose])) : data
        exposed.each { |field, value| instance.instance_variable_set(:"@#{field}", value) }
      end

      # @param output [FieldStruct::Base, Hash, Object]
      # @return [Hash{Symbol=>Object}] the child output as a plain hash
      def output_hash(output)
        case output
        when FieldStruct::Base then output.attributes
        when Hash then output
        else {}
        end
      end
    end
  end
end
