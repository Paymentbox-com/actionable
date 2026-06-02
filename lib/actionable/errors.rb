# frozen_string_literal: true

module Actionable
  # Base class for every error this gem raises. Rescue +Actionable::Error+ to
  # catch the whole family. Genuine errors are never caught by the runner for
  # control flow — they propagate to the caller (decision D4).
  class Error < StandardError; end

  # The throw/catch tag used to unwind an action's step pipeline early.
  # Halting (+fail!+ / +succeed!+ / +halt!+) throws this symbol; the runner
  # catches it via {Actionable.catch_halt}. This is control flow, NOT an
  # exception (decision D4).
  HALT = :actionable_halt

  module_function

  # Run +block+ inside the halt catch point.
  #
  # Returns the block's value when nothing is thrown, or the value passed with
  # +throw Actionable::HALT, value+ when the pipeline halts (+nil+ for a bare
  # +throw Actionable::HALT+). A raised StandardError is deliberately NOT
  # caught — it propagates to the caller (decision D4).
  #
  # @return [Object] the block's value, or the thrown halt value
  def catch_halt(&block)
    catch(HALT, &block)
  end
end
