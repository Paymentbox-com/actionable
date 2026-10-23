# frozen_string_literal: true

# The opt-in RuboCop integration: the +Actionable/VerbNotLast+ cop (owner
# ruling R5). Never loaded by +require 'actionable'+; RuboCop loads it from
# a project's +.rubocop.yml+:
#
#   plugins:
#     - actionable:
#         require_path: actionable/rubocop
#
# or, on RuboCop < 1.72, +require: [actionable/rubocop]+. RuboCop depends on
# Prism, so the cop always has it. Loads only the rule analyzer, not the gem.
require 'rubocop'
require 'prism'
require_relative 'version'
require_relative 'verb_position'
require_relative 'rubocop/cop/actionable/verb_not_last'

begin
  require 'lint_roller' # RuboCop >= 1.72's plugin API
rescue LoadError
  nil
else
  require_relative 'rubocop/plugin'
end
