# frozen_string_literal: true

module Actionable
  # A skipped run's result (decision D17): the action had nothing to do — not a
  # success (no real work), but not a failure either. Its +code+ is the skip
  # reason (e.g. +:not_ready+), defaulting to +:skipped+.
  class Skipped < Result
    # @return [Symbol] the skip reason; defaults to +:skipped+
    required :code, :symbol, default: :skipped

    # @return [true]
    def skipped?
      true
    end
  end
end
