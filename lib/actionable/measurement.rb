# frozen_string_literal: true

module Actionable
  # Thread-local measurement context (decision D10). It lets a measuring run
  # cascade into the nested actions it invokes, and lets an action step attach
  # its child's history to the step record currently open in the parent runner.
  #
  # All state is per-thread and saved/restored around each scope, so concurrent
  # runs on different threads never interfere.
  module Measurement
    class << self
      # @return [Boolean] whether the current thread is inside a measuring run
      def active?
        store[:active]
      end

      # @return [History::Step, nil] the step record nested history attaches to
      def open_step
        store[:open_step]
      end

      # Mark measurement active for the block, so nested runs measure too.
      #
      # @yieldreturn [Object]
      # @return [Object] the block's value
      def measuring(&)
        with({active: true}, &)
      end

      # Make +record+ the open step for the block, so a nested action step can
      # attach its child's history to it.
      #
      # @param record [History::Step]
      # @yieldreturn [Object]
      # @return [Object] the block's value
      def recording(record, &)
        with({open_step: record}, &)
      end

      private

      # This thread's measurement state: +:active+ and +:open_step+.
      #
      # @return [Hash{Symbol=>Object}]
      def store
        Thread.current[:actionable_measurement] ||= {active: false, open_step: nil}
      end

      # Merge +changes+ into the state for the block, restoring it afterwards.
      #
      # @param changes [Hash{Symbol=>Object}] the keys to override
      # @yield the scope the changes apply to
      # @yieldreturn [Object]
      # @return [Object] the block's value
      def with(changes)
        previous = store.dup
        store.merge!(changes)
        yield
      ensure
        Thread.current[:actionable_measurement] = previous
      end
    end
  end
end
