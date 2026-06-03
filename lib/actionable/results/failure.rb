# frozen_string_literal: true

module Actionable
  # A failed run's result. Its +code+ is the error symbol describing why the
  # run failed (e.g. +:not_found+, +:invalid_input+), defaulting to +:error+.
  class Failure < Result
    # @return [Symbol] the error code; defaults to +:error+
    required :code, :symbol, default: :error

    # @return [true]
    def failure?
      true
    end
  end
end
