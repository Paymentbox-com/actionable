# frozen_string_literal: true

# Optional Rails adapter (decisions D8/D9). This file is NEVER required by the
# core entry point — load it explicitly with `require 'actionable/rails'` (in a
# Rails app, the Railtie does so during boot). It is the only place that pulls
# in active_*.
require 'active_model'
require 'active_support/core_ext/string/inflections' # camelize/constantize

require_relative 'rails/transactions'
require_relative 'rails/proxy_validator'

# Wire the adapter into the core: the transactional macro onto Action, and the
# transaction-wrapping behavior onto the Runner.
Actionable::Action.extend(Actionable::Rails::Transactions)
Actionable::Runner.prepend(Actionable::Rails::RunnerTransaction)

require_relative 'railtie' if defined?(Rails::Railtie)
