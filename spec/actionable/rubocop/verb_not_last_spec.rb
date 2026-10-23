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

  describe 'which classes it checks (owner ruling R10)' do
    it 'ignores a class with another step DSL (dry-transaction)' do
      expect_no_offenses(<<~RUBY)
        class X
          include Dry::Transaction
          step :a

          def a
            fail :x
            log
          end
        end
      RUBY
    end

    it 'ignores a step-declaring class whose superclass is not an action' do
      expect_no_offenses(<<~RUBY)
        class Pipeline < Workflow::Base
          step :a

          def a
            fail :x
            log
          end
        end

        Class.new(Workflow::Base) do
          step :a

          def a
            fail :x
            log
          end
        end
      RUBY
    end

    it 'checks an ApplicationAction subclass, and a top-level ::Actionable::Action one' do
      expect_offense(<<~RUBY)
        class Charge < ApplicationAction
          step :a

          def a
            fail :x
            ^^^^^^^ `fail` records [...]
            log
          end
        end

        class Refund < ::Actionable::Action
          step :a

          def a
            skip :x
            ^^^^^^^ `skip` records [...]
            log
          end
        end
      RUBY
    end

    it 'follows a superclass chain through classes defined in the same file' do
      expect_offense(<<~RUBY)
        module Billing
          Base = Class.new(Actionable::Action)

          class Charge < Base; end

          class Refund < Billing::Charge
            step :a

            def a
              fail :x
              ^^^^^^^ `fail` records [...]
              log
            end
          end
        end
      RUBY
    end

    it 'survives a superclass cycle' do
      expect_no_offenses(<<~RUBY)
        class A < B; end

        class B < A
          step :a

          def a
            fail :x
            log
          end
        end
      RUBY
    end

    describe 'resolving a superclass by its lexical full name' do
      it 'tells apart same-named classes in different modules' do
        expect_offense(<<~RUBY)
          module A
            class Base < Actionable::Action; end

            class Charge < Base
              step :a

              def a
                fail :x
                ^^^^^^^ `fail` records [...]
                log
              end
            end
          end

          module B
            class Base; end

            class Charge < Base
              step :a

              def a
                fail :x
                log
              end
            end
          end

          class Refund < A::Base
            step :a

            def a
              skip :x
              ^^^^^^^ `skip` records [...]
              log
            end
          end

          class Void < Base
            step :a

            def a
              fail :x
              log
            end
          end
        RUBY
      end

      it 'looks a name up from the class keyword outwards, not through a compact path or past a leading ::' do
        expect_offense(<<~RUBY)
          module A
            class Base < Actionable::Action; end

            module Inner
              class Charge < Base
                step :a

                def a
                  fail :x
                  ^^^^^^^ `fail` records [...]
                  log
                end
              end
            end

            class Refund < ::Base
              step :a

              def a
                fail :x
                log
              end
            end
          end

          class A::Void < Base
            step :a

            def a
              fail :x
              log
            end
          end

          module A::Deep
            class Void < Base
              step :a

              def a
                fail :x
                log
              end
            end
          end
        RUBY
      end

      it 'does not take a file class for a configured base it shadows' do
        expect_offense(<<~RUBY)
          module Legacy
            class ApplicationAction; end

            class Charge < ApplicationAction
              step :a

              def a
                fail :x
                log
              end
            end
          end

          class Refund < ApplicationAction
            step :a

            def a
              fail :x
              ^^^^^^^ `fail` records [...]
              log
            end
          end
        RUBY
      end

      it 'reaches a configured base named relative to the enclosing module' do
        expect_offense(<<~RUBY)
          module Actionable
            class Charge < Action
              step :a

              def a
                fail :x
                ^^^^^^^ `fail` records [...]
                log
              end
            end
          end
        RUBY
      end
    end

    context 'with a multi-segment ActionBaseClasses name' do
      let(:cop_config) { {'ActionBaseClasses' => ['Ops::Billing::BaseAction']} }

      it 'resolves it relative to an enclosing module' do
        expect_offense(<<~RUBY)
          module Ops
            class Charge < Billing::BaseAction
              step :a

              def a
                fail :x
                ^^^^^^^ `fail` records [...]
                log
              end
            end
          end
        RUBY
      end
    end

    context 'with ActionBaseClasses configured' do
      let(:cop_config) { {'ActionBaseClasses' => ['::Ops::BaseAction']} }

      it 'resolves a listed full name from inside its namespace' do
        expect_offense(<<~RUBY)
          module Ops
            class Charge < BaseAction
              step :a

              def a
                fail :x
                ^^^^^^^ `fail` records [...]
                log
              end
            end
          end

          module Billing
            class BaseAction; end

            class Refund < BaseAction
              step :a

              def a
                fail :x
                log
              end
            end
          end
        RUBY
      end

      it 'checks subclasses of the listed classes only (a leading :: is ignored)' do
        expect_offense(<<~RUBY)
          class Charge < Ops::BaseAction
            step :a

            def a
              fail :x
              ^^^^^^^ `fail` records [...]
              log
            end
          end

          class Refund < ApplicationAction
            step :a

            def a
              fail :x
              log
            end
          end
        RUBY
      end
    end
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

  it 'defaults ActionBaseClasses to the list the cop falls back to without it' do
    rules = plugin.rules(LintRoller::Context.new(engine: :rubocop))

    expect(YAML.safe_load_file(rules.value).dig('Actionable/VerbNotLast', 'ActionBaseClasses'))
      .to eq(Actionable::VerbPosition::ACTION_BASE_CLASSES)
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
