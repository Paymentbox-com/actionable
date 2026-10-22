# frozen_string_literal: true

module Actionable
  module Rails
    # Internal signal raised inside a transaction block to trigger a rollback
    # without surfacing as a genuine error. The runner wrapper swallows it; a
    # real ActiveRecord transaction rolls back and re-raises it (as it does for
    # any exception), and the wrapper catches it outside the block.
    class Rollback < StandardError; end

    # The +transactional+ class macro (decision D9). Extended onto
    # {Actionable::Action} by +actionable/rails+.
    module Transactions
      # Wrap this action's run in +model.transaction(**options)+.
      #
      #   transactional model: :invoice
      #   transactional model: Invoice, requires_new: false # join an outer one
      #
      # Run inside a transaction that is already open, the action gets its own
      # savepoint (+requires_new: true+) unless +requires_new:+ is given, so a
      # recorded +Failure+ rolls back its own writes rather than leaving them for
      # the outer transaction to commit.
      #
      # @param model [Symbol, Class] the model whose +transaction+ is used; a
      #   Symbol is resolved to a constant (+:invoice+ → +Invoice+)
      # @param options [Hash{Symbol=>Object}] options forwarded to +transaction+
      # @return [void]
      def transactional(model:, **options)
        @transaction_config = {model: model, options: options}
      end

      # The transaction config for this action, inherited from ancestors when
      # not set locally (decision D9: inherited, overridable).
      #
      # @return [Hash, nil]
      def transaction_config
        return @transaction_config if defined?(@transaction_config) && @transaction_config
        return superclass.transaction_config if superclass.respond_to?(:transaction_config)

        nil
      end
    end

    # Prepended onto {Actionable::Runner} so a +transactional+ action runs its
    # whole pipeline inside a transaction. A raised exception or a recorded
    # +Failure+ rolls everything back; a +Success+ commits (decision D9).
    module RunnerTransaction
      # @return [Result]
      def run
        config = transaction_config
        return super unless config

        result = nil
        model = resolve_model(config[:model])
        model.transaction(**transaction_options(model, config[:options])) do
          result = super
          raise Rollback if result.failure?
        end
        result
      rescue Rollback
        result
      end

      private

      # @return [Hash, nil] the running action's transaction config
      def transaction_config
        klass = @instance.class
        klass.respond_to?(:transaction_config) ? klass.transaction_config : nil
      end

      # The configured options, plus +requires_new: true+ when a transaction is
      # already open and the action did not say otherwise. Joining the outer
      # transaction would swallow this run's rollback, so a recorded failure's
      # writes would commit with it (decision D9).
      #
      # @param model [Class]
      # @param options [Hash{Symbol=>Object}]
      # @return [Hash{Symbol=>Object}]
      def transaction_options(model, options)
        return options if options.key?(:requires_new)
        return options unless model.respond_to?(:connection) && model.connection.transaction_open?

        options.merge(requires_new: true)
      end

      # @param model [Symbol, Class]
      # @return [Class] the resolved model class
      def resolve_model(model)
        model.is_a?(Class) ? model : model.to_s.camelize.constantize
      end
    end
  end
end
