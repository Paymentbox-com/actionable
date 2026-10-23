# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require 'actionable/rubocop'
require_relative '../../support/verb_position_rules'
require 'open3'
require 'rbconfig'
require 'yaml'

RSpec.describe RuboCop::Cop::Actionable::VerbNotLast, :config do
  let(:ruby_version) { 3.2 } # the gem's floor; endless defs need >= 3.0

  it 'flags a plain verb with more code after it in a step method' do
    expect_offense(<<~RUBY)
      class Charge < Actionable::Action
        step :charge

        def charge
          fail :card_expired if card.expired?
          ^^^^^^^^^^^^^^^^^^ `fail` records the outcome and keeps running, and more code runs after it: use `fail!` to stop here, or make it the method's last expression.
          notify
        end
      end
    RUBY
  end

  # Every row of the shared rule table, as a step method of an action.
  VerbPositionRules::ALL.each do |label, source, expected|
    it "#{expected.empty? ? "allows" : "flags"} a verb in: #{label}" do
      body = source.gsub(/^/, '  ')
      offenses = inspect_source("class A < Actionable::Action\n  step :a\n#{body}end\n")

      expect(offenses.map { |offense| [offense.message[/\A`(\w+)`/, 1].to_sym, offense.line - 2] }).to eq(expected)
    end
  end

  it 'checks hook methods, case_step branch targets and private defs, not case values or helpers' do
    expect_offense(<<~RUBY)
      Class.new(Actionable::Action) do
        case_step :status do
          on :bad, :handle_bad
          default :handle_other
        end
        always :audit

        private def handle_bad
          fail :bad
          ^^^^^^^^^ `fail` records [...]
          nil
        end

        def handle_other = succeed

        def audit
          skip :quiet
          ^^^^^^^^^^^ `skip` records [...]
          nil
        end

        def status
          skip :never
          :bad
        end

        def helper
          fail :x
          nil
        end
      end
    RUBY
  end

  it 'ignores a class that declares no steps (an ActiveRecord after_commit is not an action)' do
    expect_no_offenses(<<~RUBY)
      class Order < ApplicationRecord
        after_commit :sync

        def sync
          fail 'not synced' unless synced?
          log
        end
      end
    RUBY
  end

  it 'honours an inline disable' do
    expect_no_offenses(<<~RUBY)
      class A < Actionable::Action
        step :a

        def a
          fail :x # rubocop:disable Actionable/VerbNotLast
          more
        end
      end
    RUBY
  end
end

RSpec.describe Actionable::RubocopPlugin do
  let(:plugin) { described_class.new({}) }

  it 'serves the config that enables the cop' do
    rules = plugin.rules(LintRoller::Context.new(engine: :rubocop))

    expect(YAML.safe_load_file(rules.value)).to include('Actionable/VerbNotLast' => include('Enabled' => true))
  end

  it 'supports RuboCop only' do
    expect([plugin.supported?(LintRoller::Context.new(engine: :rubocop)),
            plugin.supported?(LintRoller::Context.new(engine: :standard))]).to eq([true, false])
  end
end

RSpec.describe 'require "actionable"' do
  it 'does not load RuboCop or the cop' do
    out, status = Open3.capture2e(RbConfig.ruby, '-Ilib', '-e',
      'require "actionable"; print [defined?(RuboCop), defined?(Actionable::RubocopPlugin)].inspect',
      chdir: File.expand_path('../../..', __dir__))

    expect([status.success?, out]).to eq([true, '[nil, nil]'])
  end
end
