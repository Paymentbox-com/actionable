# frozen_string_literal: true

module Actionable
  module Rails
    # The +after_commit+ hook kind. Prepended onto {Actionable::Action}'s
    # singleton class by +actionable/rails+, so the core never knows about it
    # (decision D8).
    #
    # An +after_commit+ hook runs once, after the database work of a
    # successful run has really committed: it is registered with
    # +ActiveRecord.after_all_transactions_commit+ when the run ends, so it
    # waits for the outermost open transaction (not the action's own
    # savepoint), runs immediately when none is open, and never runs if any
    # enclosing transaction rolls back.
    module AfterCommit
      # The first ActiveRecord version with +after_all_transactions_commit+.
      MINIMUM_ACTIVE_RECORD = '7.2'

      # Declare a hook that runs after the outermost database transaction
      # commits, iff the run's final result is a {Success}.
      #
      #   after_commit :send_receipt
      #   after_commit NotifyWarehouse, input: %i[order]
      #
      # The run is over by then: the result has been returned (or is about to
      # be, when no transaction is open), so the hook cannot change it, a
      # halting verb only stops the remaining +after_commit+ hooks, and the
      # hook is not recorded in the history. An exception it raises propagates
      # from wherever the commit happens: the outer +transaction+ call, or
      # +.run+ itself when no transaction was open.
      #
      # @param target [Symbol, String, Class<Actionable::Action>] the instance
      #   method or nested action to run
      # @param options [Object] step options (+:if+, +:unless+, and for a
      #   nested action +:input+)
      # @raise [DefinitionError] when ActiveRecord is not loaded or predates
      #   +after_all_transactions_commit+
      # @return [Set<Steps::Base>]
      def after_commit(target, **options)
        ensure_after_commit_supported!
        declare(after_commit_hooks, Steps.build(target, **options))
      end

      # Hooks that run after the outermost transaction commits a successful run.
      # @return [Set<Steps::Base>]
      def after_commit_hooks
        @after_commit_hooks ||= Set.new
      end

      # Give each subclass its own copy of the inherited +after_commit+ hooks.
      #
      # @param subclass [Class]
      # @return [void]
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@after_commit_hooks, after_commit_hooks.dup)
      end

      private

      # Extend the run-start guard (decision D18) to the +after_commit+ hooks.
      #
      # @param instance [Action]
      # @return [void]
      def ensure_steps_implemented!(instance)
        super
        missing = after_commit_hooks.flat_map(&:required_methods).uniq.reject { |method| implements?(instance, method) }
        return if missing.empty?

        raise DefinitionError,
          "#{name || "action"} declares after_commit hook(s) calling #{missing.map(&:inspect).join(", ")} " \
          'but does not implement them'
      end

      # @raise [DefinitionError] when +after_all_transactions_commit+ is unavailable
      # @return [void]
      def ensure_after_commit_supported!
        return if defined?(::ActiveRecord) && ::ActiveRecord.respond_to?(:after_all_transactions_commit)

        raise DefinitionError,
          "after_commit needs ActiveRecord >= #{MINIMUM_ACTIVE_RECORD} " \
          '(ActiveRecord.after_all_transactions_commit); load a supported ActiveRecord before declaring it'
      end
    end

    # Prepended onto {Actionable::Runner} (outside {RunnerTransaction}) to
    # register a successful run's +after_commit+ hooks once the run, and its
    # own transaction, are over.
    module RunnerAfterCommit
      # @return [Result]
      def run
        result = super
        schedule_after_commit if result.success?
        result
      end

      private

      # @return [void]
      def schedule_after_commit
        klass = @instance.class
        return unless klass.respond_to?(:after_commit_hooks)

        hooks = klass.after_commit_hooks.to_a
        return if hooks.empty?

        ::ActiveRecord.after_all_transactions_commit { run_after_commit_hooks(hooks) }
      end

      # Run the hooks in order. A halt stops the remaining ones; nothing they
      # record reaches the already-returned result.
      #
      # @param hooks [Array<Steps::Base>]
      # @return [void]
      def run_after_commit_hooks(hooks)
        Actionable.catch_halt do
          hooks.each { |hook| hook.call(@instance) unless hook.skip?(@instance) }
        end
      end
    end
  end
end
