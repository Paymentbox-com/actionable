# frozen_string_literal: true

module Actionable
  # A successful run's result. Its +code+ defaults to +:success+.
  class Success < Result
    # @return [Symbol] always +:success+ unless explicitly overridden
    required :code, :symbol, default: :success

    # @return [true]
    def success?
      true
    end
  end
end
