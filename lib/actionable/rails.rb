# frozen_string_literal: true

# Optional Rails adapter (decisions D8/D9). This file is NEVER required by the
# core entry point — load it explicitly with `require 'actionable/rails'` (in a
# Rails app, the Railtie does so during boot). It is the only place that pulls
# in active_*.
require_relative '../actionable' # ensure the core is loaded (self-contained entry)
require 'active_model'
require 'active_support/core_ext/string/inflections' # camelize/constantize

require_relative 'rails/transactions'
require_relative 'rails/proxy_validator'
require_relative 'rails/after_commit'

# Wire the adapter into the core: the transactional and after_commit macros
# onto Action, and their behavior onto the Runner. RunnerAfterCommit is
# prepended last so it wraps RunnerTransaction: a run registers its
# after_commit hooks only once its own transaction is over.
Actionable::Action.extend(Actionable::Rails::Transactions)
Actionable::Action.singleton_class.prepend(Actionable::Rails::AfterCommit)
Actionable::Runner.prepend(Actionable::Rails::RunnerTransaction)
Actionable::Runner.prepend(Actionable::Rails::RunnerAfterCommit)

require_relative 'railtie' if defined?(Rails::Railtie)
