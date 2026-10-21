# frozen_string_literal: true

module Actionable
  # A failed run's result. Its +code+ is the error symbol describing why the
  # run failed (e.g. +:not_found+, +:invalid_input+), defaulting to +:error+.
  class Failure < Result
    # @return [Symbol] the error code; defaults to +:error+
    required :code, :symbol, default: :error

    # @return [Hash{Symbol=>Object}] the metadata the action declared for this
    #   code with {Action.fails} (decision D20), so an adapter can read it off the
    #   result without the action class. Empty when the code isn't declared.
    #   The gem stores and passes it through but never interprets it.
    optional :metadata, :value, default: -> { {} }

    # @return [true]
    def failure?
      true
    end

    # A plain-Hash view of the failure: {Result#to_h} plus its declared
    # +metadata+ (decision D20).
    #
    # @return [Hash{Symbol=>Object}]
    def to_h
      super.merge(metadata: metadata)
    end

    # Copy another object's FieldStruct-style errors onto this failure's own
    # errors collection. The shared mechanism behind +Failure(:invalid_input)+,
    # +Failure(:invalid_output)+, and the {Action#fail_with} verb (decision D19).
    #
    # @param source [#errors] any object whose +errors+ responds to +to_h+
    #   (a +FieldStruct::Base+ instance, or another result)
    # @return [self] so callers can build-and-absorb in one expression
    def absorb_errors_from(source)
      source.errors.to_h.each do |field, messages|
        Array(messages).each { |message| errors.add(field, message) }
      end
      self
    end
  end
end
