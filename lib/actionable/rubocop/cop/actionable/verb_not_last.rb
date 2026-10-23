# frozen_string_literal: true

module RuboCop
  module Cop
    module Actionable
      # A plain recording verb (+fail+ / +skip+ / +succeed+) must be the last
      # expression of its step or hook method: it records the outcome and
      # keeps running, so code after it still runs (owner ruling R5). The
      # same rules as the gem's first-run check, from the same analyzer
      # (+Actionable::VerbPosition+); USAGE (Control flow) has the table.
      #
      # It sees one file: a class that declares +step+ / +case_step+, and the
      # methods that class names in a step, case-step branch or hook
      # declaration.
      #
      # @example
      #   # bad
      #   def charge
      #     fail :card_expired if card.expired?
      #     notify
      #   end
      #
      #   # good
      #   def charge
      #     fail! :card_expired if card.expired?
      #     notify
      #   end
      #
      #   # good
      #   def charge
      #     notify
      #     fail :card_expired if card.expired?
      #   end
      class VerbNotLast < Base
        # @return [String]
        MSG = '`%<verb>s` records the outcome and keeps running, and more code runs after it: ' \
              "use `%<verb>s!` to stop here, or make it the method's last expression."

        # @return [void]
        def on_new_investigation
          result = ::Prism.parse(processed_source.raw_source)
          return unless result.errors.empty?

          ::Actionable::VerbPosition.declared_step_offenses(result.value).each do |offense|
            range = Parser::Source::Range.new(processed_source.buffer, offense.start_character, offense.end_character)
            add_offense(range, message: format(MSG, verb: offense.verb))
          end
        end
      end
    end
  end
end
