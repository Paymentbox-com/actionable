# frozen_string_literal: true

require 'prism'
require_relative '../support/verb_position_rules'

RSpec.describe Actionable::VerbPosition do
  # @return [Array<Array(Symbol, Integer)>] [verb, line] per offense
  def offenses_in(source)
    def_node = Prism.parse(source).value.statements.body.first
    described_class.offenses(def_node).map { |offense| [offense.verb, offense.line] }
  end

  describe '.offenses' do
    VerbPositionRules::ALL.each do |label, source, expected|
      it "#{expected.empty? ? "allows" : "flags"} a verb in: #{label}" do
        expect(offenses_in(source)).to eq(expected)
      end
    end

    it 'reports the column and the character range of the verb call' do
      source = "def a\n  fail :x if bad?\n  notify\nend\n"
      offense = described_class.offenses(Prism.parse(source).value.statements.body.first).first

      expect([offense.column, source[offense.start_character...offense.end_character]]).to eq([2, 'fail :x'])
    end

    it 'does not look inside a nested def or class' do
      expect(offenses_in(<<~RUBY)).to eq([])
        def a
          def b
            fail :x
            work
          end
          Class.new { def c = (fail(:x); work) }
          done
        end
      RUBY
    end
  end
end
