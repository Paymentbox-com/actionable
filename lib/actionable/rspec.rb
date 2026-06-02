# frozen_string_literal: true

# Optional RSpec integration (decision D12). Load it explicitly with
# `require 'actionable/rspec'` (typically in spec_helper, after rspec). Never
# loaded by the core entry point.
require_relative '../actionable' # ensure the core is loaded (self-contained entry)
require_relative 'rspec/matchers'

RSpec.configure { |config| config.include Actionable::RSpec::Matchers } if defined?(RSpec)
