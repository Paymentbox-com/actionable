# frozen_string_literal: true

require 'pathname'

module Actionable
  # The lint_roller plugin RuboCop >= 1.72 loads for
  # +plugins: [{actionable: {require_path: actionable/rubocop}}]+ (the gemspec
  # names it in +default_lint_roller_plugin+). It enables
  # +Actionable/VerbNotLast+ through +config.yml+ beside this file.
  class RubocopPlugin < LintRoller::Plugin
    # @return [LintRoller::About]
    def about
      LintRoller::About.new(
        name: 'actionable', version: VERSION, homepage: 'https://github.com/Paymentbox-com/actionable',
        description: 'Actionable/VerbNotLast: a plain fail/fail_with/skip/succeed must end its step or hook method.'
      )
    end

    # @param context [LintRoller::Context]
    # @return [Boolean]
    def supported?(context)
      context.engine == :rubocop
    end

    # @param _context [LintRoller::Context]
    # @return [LintRoller::Rules]
    def rules(_context)
      LintRoller::Rules.new(type: :path, config_format: :rubocop, value: Pathname.new(__dir__).join('config.yml'))
    end
  end
end
