# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in actionable.gemspec
gemspec

# Pull field_struct from GitHub rather than RubyGems (overrides the
# gemspec runtime dependency for development/CI).
gem 'field_struct', git: 'https://github.com/Paymentbox-com/field_struct'

gem 'rake', '~> 13.0'
gem 'rspec', '~> 3.0'
gem 'rubocop', '~> 1.21'
gem 'simplecov', '~> 0.22', require: false

# Exercises the optional Rails adapter (actionable/rails) in adapter specs.
# The core never loads active_*; this is dev/test only (decisions D8/D9).
gem 'activemodel', '~> 8.0', require: false

# Type signatures + docs (decision D13)
gem 'rbs', '~> 3.0', require: false
gem 'sord', '~> 7.0', require: false
gem 'steep', '~> 1.0', require: false
gem 'yard', '~> 0.9', require: false
