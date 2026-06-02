# frozen_string_literal: true

module Actionable
  # Integrates the optional Rails adapter with the host application's boot
  # process (decision D8). Loaded by +actionable/rails+ only when running inside
  # a Rails application; it is the hook point for future Rails-specific wiring
  # (generators, initializers). The core gem never references Rails.
  class Railtie < ::Rails::Railtie
  end
end
