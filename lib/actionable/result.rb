# frozen_string_literal: true

module Actionable
  # The single value object a run returns. {Success} and {Failure} are the
  # concrete subclasses; +Result+ itself is abstract and defines the shared,
  # FieldStruct-backed shape (decision D5).
  #
  # @abstract Instantiate {Success} or {Failure}, not +Result+ directly.
  class Result < FieldStruct::Base
    # @return [Symbol] +:success+ for a {Success}; the error symbol for a {Failure}
    required :code, :symbol

    # @return [String, nil] human-readable description of the outcome
    optional :message, :string

    # NOTE: +errors+ is intentionally NOT a declared field. It is FieldStruct's
    # own per-instance, Hash-like {FieldStruct::Errors} collection (decision D5,
    # "integrates with FieldStruct"); declaring a field of the same name would
    # shadow the framework's validation machinery.

    # @return [Object] the run's declared, typed output payload (empty by default).
    #   Firms up into an output FieldStruct once output schemas land (D6).
    optional :output, :value, default: -> { {} }

    # @return [Object] the run's execution history (empty by default).
    #   Firms up into a +History+ once measurement lands (D10).
    optional :history, :value, default: -> { [] }

    # @return [Boolean] whether the run succeeded. Abstract here; each
    #   subclass flips the predicate that applies to it.
    def success?
      false
    end

    # @return [Boolean] whether the run failed.
    def failure?
      false
    end

    # @return [Boolean] alias of {#success?}
    def successful?
      success?
    end

    # @return [Boolean] alias of {#failure?}
    def failed?
      failure?
    end

    # @return [String] a compact, field-sorted, deterministic representation —
    #   the declared attributes plus the +errors+ collection, sorted by name,
    #   so equal results always render identically.
    def inspect
      pairs = attributes.merge(errors: errors.to_h)
        .sort_by { |name, _| name.to_s }
        .map { |name, value| "#{name}=#{value.inspect}" }
      "#<#{self.class.name} #{pairs.join(" ")}>"
    end

    # @return [String] same deterministic representation as {#inspect}
    def to_s
      inspect
    end
  end
end
