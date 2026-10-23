# frozen_string_literal: true

require 'field_struct'

require_relative 'actionable/version'
require_relative 'actionable/errors'
require_relative 'actionable/value_match'
require_relative 'actionable/measurement'
require_relative 'actionable/history'
require_relative 'actionable/registry'
require_relative 'actionable/result'
require_relative 'actionable/results/success'
require_relative 'actionable/results/failure'
require_relative 'actionable/results/skipped'
require_relative 'actionable/batch_result'
require_relative 'actionable/input_dispatch'
require_relative 'actionable/steps/base'
require_relative 'actionable/steps/method'
require_relative 'actionable/steps/action'
require_relative 'actionable/steps/case'
require_relative 'actionable/steps'
require_relative 'actionable/verb_position'
require_relative 'actionable/runner'
require_relative 'actionable/action'
require_relative 'actionable/rbs'

# Actionable: typed, composable Ruby service objects.
#
# This is the core entry point. Per decision D14, every core file gets an
# explicit +require_relative+ here — no autoload, no Zeitwerk. The optional
# adapters (+actionable/rails+, +actionable/rspec+) are separate requires and
# are deliberately NOT loaded here, keeping the core Rails-free.
module Actionable
  @verb_position_check = true

  # Turn the first-run verb-position check (owner rulings R5, R10) on or
  # off for the whole process. Off, {Action.run} never parses a method's
  # source and never loads Prism; the per-call code check in +fail+ / +skip+
  # stays on. Meant as an escape hatch while upgrading (set it in an
  # initializer), with the +Actionable/VerbNotLast+ cop as the only guard
  # left. A class first run while off is checked on its first run after the
  # check is turned back on.
  #
  #   Actionable.verb_position_check = false
  #
  # @param enabled [Boolean] +false+ to skip the check
  # @return [Boolean] whether the check is now on
  def self.verb_position_check=(enabled)
    @verb_position_check = enabled ? true : false
  end

  # Whether {Action.run} checks where each step and hook method places its
  # plain recording verbs on an action's first run. On by default.
  #
  # @return [Boolean]
  def self.verb_position_check?
    @verb_position_check
  end
end
