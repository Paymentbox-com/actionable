# frozen_string_literal: true

module Actionable
  # A skipped run's result (decision D17): the action had nothing to do — not a
  # success (no real work), but not a failure either. Its +code+ is the skip
  # reason (e.g. +:not_ready+), defaulting to +:skipped+.
  class Skipped < Result
    # @return [Symbol] the skip reason; defaults to +:skipped+
    required :code, :symbol, default: :skipped

    # @return [Hash{Symbol=>Object}] the metadata the action declared for this
    #   code with {Action.skips} (decision D21), so an adapter can read it off the
    #   result without the action class. Empty when the code isn't declared.
    #   The gem stores and passes it through but never interprets it.
    optional :metadata, :value, default: -> { {} }

    # @return [true]
    def skipped?
      true
    end

    # A plain-Hash view of the skip: {Result#to_h} plus its declared +metadata+
    # (decision D21).
    #
    # @return [Hash{Symbol=>Object}]
    def to_h
      super.merge(metadata: metadata)
    end
  end
end
