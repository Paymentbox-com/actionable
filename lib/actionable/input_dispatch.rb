# frozen_string_literal: true

module Actionable
  # Runtime selection of an input schema from a discriminator value (decision
  # D19, declared with +input_for+). Each branch maps a match value to a
  # FieldStruct schema; an optional +default+ catches the rest. Lets a
  # polymorphic payload (e.g. +event_type+ → shape) use typed, validated input.
  #
  #   input_for :event_type do
  #     on 'sale',   SaleShape
  #     on 'refund', RefundShape
  #     default      UnknownShape
  #   end
  class InputDispatch
    # Collects +on+/+default+ branch declarations inside an +input_for+ block.
    class Builder
      # @return [Array<Array(Object, Class<FieldStruct::Base>)>] ordered [match, schema] pairs
      attr_reader :branches
      # @return [Class<FieldStruct::Base>, nil] the fallback schema, if declared
      attr_reader :default_schema

      def initialize
        @branches = []
        @default_schema = nil
      end

      # Register a branch. +value+ matches the discriminator by +==+, by
      # Array membership, or by +Regexp#match?+ (see {ValueMatch}).
      #
      # @param value [Object, Array, Regexp]
      # @param schema [Class<FieldStruct::Base>]
      # @return [void]
      def on(value, schema)
        @branches << [value, schema]
      end

      # Register the fallback schema, used when no +on+ branch matches.
      #
      # @param schema [Class<FieldStruct::Base>]
      # @return [void]
      def default(schema)
        @default_schema = schema
      end
    end

    # @return [Symbol] the discriminator field read from +.run+'s kwargs
    attr_reader :discriminator
    # @return [Array<Array(Object, Class<FieldStruct::Base>)>] ordered [match, schema] pairs
    attr_reader :branches
    # @return [Class<FieldStruct::Base>, nil] the fallback schema
    attr_reader :default_schema

    # Build a dispatch from an +input_for+ declaration.
    #
    # @param discriminator [Symbol, String] the kwarg whose value selects the schema
    # @yield the branch declarations (+on+ / +default+)
    # @return [InputDispatch]
    def self.define(discriminator, &block)
      builder = Builder.new
      builder.instance_eval(&block)
      new(discriminator.to_sym, builder.branches, builder.default_schema)
    end

    # @param discriminator [Symbol]
    # @param branches [Array<Array(Object, Class<FieldStruct::Base>)>]
    # @param default_schema [Class<FieldStruct::Base>, nil]
    def initialize(discriminator, branches, default_schema)
      @discriminator = discriminator
      @branches = branches
      @default_schema = default_schema
    end

    # The schema for a discriminator value: the first matching branch, else the
    # default, else +nil+ (no match and no default).
    #
    # @param value [Object] the discriminator value
    # @return [Class<FieldStruct::Base>, nil]
    def schema_for(value)
      @branches.each { |branch_value, schema| return schema if ValueMatch.matches?(branch_value, value) }
      @default_schema
    end

    # @return [Array<Class<FieldStruct::Base>>] every distinct schema reachable
    #   through this dispatch (branches plus default)
    def schemas
      (@branches.map(&:last) + [@default_schema]).compact.uniq
    end

    # @return [Array<Object>] the branch match values, in declaration order
    def variants
      @branches.map(&:first)
    end
  end
end
