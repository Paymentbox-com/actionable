# frozen_string_literal: true

require 'rbs'

# The signature environment a host type-checks against: the gem's sig/,
# field_struct's, and the stdlib libraries field_struct's signatures name
# (::Date, ::Time, ::BigDecimal).
module RbsEnvironment
  STDLIB = %w[date time bigdecimal].freeze

  # @return [RBS::Environment] unresolved, so callers can add generated files
  def self.base
    loader = RBS::EnvironmentLoader.new
    STDLIB.each { |library| loader.add(library: library, version: nil) }
    loader.add(path: Pathname(File.expand_path('../../sig', __dir__)))
    loader.add(path: Pathname(Gem.loaded_specs.fetch('field_struct').full_gem_path).join('sig'))
    RBS::Environment.from_loader(loader)
  end
end
