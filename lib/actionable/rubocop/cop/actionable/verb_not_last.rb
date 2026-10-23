# frozen_string_literal: true

module RuboCop
  module Cop
    module Actionable
      # A plain recording verb (+fail+ / +fail_with+ / +skip+ / +succeed+) must
      # be the last expression of its step or hook method: it records the
      # outcome and keeps running, so code after it still runs (owner rulings
      # R5, R10). The
      # same rules as the gem's first-run check, from the same analyzer
      # (+Actionable::VerbPosition+); USAGE (Control flow) has the table.
      #
      # It sees one file: a class whose superclass is an action base (see
      # +ActionBaseClasses+) and that declares +step+ / +case_step+, and the
      # methods that class names in a step, case-step branch or hook
      # declaration. A class with another +step+ DSL (dry-transaction) is
      # left alone.
      #
      # +ActionBaseClasses+ (default +Actionable::Action+, +ApplicationAction+)
      # lists the base classes by full name; a class defined in the same file
      # whose superclass chain reaches one counts too. A superclass name
      # resolves lexically, as Ruby looks it up, so two same-named classes
      # in different modules are told apart.
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

          base_classes = Array(cop_config.fetch('ActionBaseClasses', ::Actionable::VerbPosition::ACTION_BASE_CLASSES))
          ::Actionable::VerbPosition.declared_step_offenses(result.value, base_classes: base_classes).each do |offense|
            range = Parser::Source::Range.new(processed_source.buffer, offense.start_character, offense.end_character)
            add_offense(range, message: format(MSG, verb: offense.verb))
          end
        end
      end
    end
  end
end
