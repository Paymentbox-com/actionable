# frozen_string_literal: true

module Actionable
  # ActiveModel validations applied to a separate delegate object (decision
  # D7). Subclass it, declare rules with the ActiveModel +validates+ DSL, and
  # construct it with any object — a plain PORO or an ActiveRecord model — whose
  # attributes the rules read. This keeps validation rules separate from the
  # data they check.
  #
  #   class InvoiceRules < Actionable::ProxyValidator
  #     validates :amount, presence: true, numericality: { greater_than: 0 }
  #   end
  #
  #   rules = InvoiceRules.new(invoice)
  #   fail(:invalid, **rules.formatted_errors) unless rules.valid?
  #
  # Part of the optional Rails adapter — available only after
  # +require 'actionable/rails'+.
  class ProxyValidator
    include ActiveModel::Validations

    # ActiveModel needs a model name to build i18n error messages; supply a
    # fallback so anonymous subclasses (and the base) still produce messages.
    #
    # @return [ActiveModel::Name]
    def self.model_name
      @model_name ||= ActiveModel::Name.new(self, nil, name || 'ProxyValidator')
    end

    # @return [Object] the object whose attributes the rules validate
    attr_reader :delegate

    # @param delegate [Object] the object to validate
    def initialize(delegate)
      @delegate = delegate
    end

    # @return [Hash{Symbol=>Array<String>}] validation errors keyed by
    #   attribute, after running the rules — ready to splat into +fail+
    def formatted_errors
      valid?
      errors.to_hash
    end

    private

    # Read attribute values from the delegate so the ActiveModel validators see
    # the delegate's data.
    def method_missing(name, *args, &block)
      return @delegate.public_send(name, *args, &block) if @delegate.respond_to?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      @delegate.respond_to?(name, include_private) || super
    end
  end
end
