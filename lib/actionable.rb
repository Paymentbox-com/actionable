# frozen_string_literal: true

require 'field_struct'

require_relative 'actionable/version'
require_relative 'actionable/errors'
require_relative 'actionable/result'
require_relative 'actionable/results/success'
require_relative 'actionable/results/failure'

# Actionable: typed, composable Ruby service objects.
#
# This is the core entry point. Per decision D14, every core file gets an
# explicit +require_relative+ here — no autoload, no Zeitwerk. The optional
# adapters (+actionable/rails+, +actionable/rspec+) are separate requires and
# are deliberately NOT loaded here, keeping the core Rails-free.
module Actionable
end
