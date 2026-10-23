# frozen_string_literal: true

# The rule table for where a non-bang recording verb (fail / fail_with / skip /
# succeed) may sit in a step or hook method (owner rulings R5, R10). One row per rule: a
# label, a method's source, and the verbs it must flag as [verb, line within
# the snippet]. An empty list means the method is fine. The analyzer spec
# (spec/actionable/verb_position_spec.rb) and the RuboCop cop spec both run
# every row, so the runtime check and the cop can't drift apart. USAGE's
# Control flow table mirrors it.
module VerbPositionRules
  OK = [
    ['the last statement', <<~RUBY, []],
      def a
        prepare
        fail :x
      end
    RUBY
    ['an endless method', "def a = fail(:x)\n", []],
    ['a modifier if as the last statement', <<~RUBY, []],
      def a
        fail :x if bad?
      end
    RUBY
    ['the last statement of each if / elsif / else branch', <<~RUBY, []],
      def a
        if bad?
          fail :x
        elsif idle?
          skip :idle
        else
          succeed
        end
      end
    RUBY
    ['an unless / else branch', <<~RUBY, []],
      def a
        unless ready?
          skip :not_ready
        else
          succeed
        end
      end
    RUBY
    ['a ternary branch', "def a = bad? ? fail(:x) : succeed\n", []],
    ['a case / when / else branch', <<~RUBY, []],
      def a
        case status
        when :bad then fail :x
        else succeed
        end
      end
    RUBY
    ['a case / in branch', <<~RUBY, []],
      def a
        case payload
        in {error: String} then fail :x
        in _ then succeed
        end
      end
    RUBY
    ['a rescue branch of the method', <<~RUBY, []],
      def a
        charge
      rescue Timeout::Error
        fail :timeout
      end
    RUBY
    ['a begin body followed only by ensure (cleanup always runs)', <<~RUBY, []],
      def a
        begin
          work
          fail :x if bad?
        ensure
          cleanup
        end
      end
    RUBY
    ['the right side of && / and', "def a = bad? && fail(:x)\n", []],
    ['parenthesized', "def a = (fail :x)\n", []],
    ['return fail(...) anywhere', <<~RUBY, []],
      def a
        return fail(:x) if bad?
        work
      end
    RUBY
    ['followed directly by return', <<~RUBY, []],
      def a
        if bad?
          fail :x
          return
        end
        work
      end
    RUBY
    ['self.fail in tail position', "def a = self.fail(:x)\n", []],
    ['fail_with as the last statement', <<~RUBY, []],
      def a
        shape = Shape.new(payload)
        fail_with(shape, code: :invalid_shape) unless shape.valid?
      end
    RUBY
    ['a bang verb anywhere', <<~RUBY, []],
      def a
        fail! :x if bad?
        skip! :idle if idle?
        work
      end
    RUBY
    ['a call on another receiver', <<~RUBY, []],
      def a
        rows = items.skip(1)
        gateway.fail(:x)
        rows
      end
    RUBY
    ['the end of a block whose call is the last statement', <<~RUBY, []],
      def a
        items.each { |i| fail :bad if i.bad? }
      end
    RUBY
    ['followed by next in a block whose call is the last statement', <<~RUBY, []],
      def a
        items.each do |i|
          if i.bad?
            fail :bad
            next
          end
          process(i)
        end
      end
    RUBY
    ['the end of a loop body whose loop is the last statement', <<~RUBY, []],
      def a
        while (item = queue.pop)
          fail :bad if item.bad?
        end
      end
    RUBY
    ['return fail(...) inside a block', <<~RUBY, []],
      def a
        items.each { |i| return fail(:bad) if i.bad? }
        save
      end
    RUBY
    ['a rescue modifier branch', "def a = charge rescue fail(:timeout)\n", []],
    ['a safe-navigation call (self&.fail is not checked)', <<~RUBY, []],
      def a
        self&.fail(:x)
        work
      end
    RUBY
    ['a local variable named like a verb', <<~RUBY, []]
      def a
        skip = compute
        log(skip)
      end
    RUBY
  ].freeze

  OFFENSES = [
    ['fail_with followed by more code', <<~RUBY, [[:fail_with, 2]]],
      def a
        fail_with(shape, code: :invalid_shape) unless shape.valid?
        save
      end
    RUBY
    ['a modifier if followed by more code', <<~RUBY, [[:fail, 2]]],
      def a
        fail :x if bad?
        notify
      end
    RUBY
    ['skip / succeed followed by more code', <<~RUBY, [[:skip, 2], [:succeed, 3]]],
      def a
        skip :idle unless ready?
        succeed
        work
      end
    RUBY
    ['a bare skip followed by more code', <<~RUBY, [[:skip, 2]]],
      def a
        skip
        work
      end
    RUBY
    ['an if branch followed by more code', <<~RUBY, [[:fail, 3]]],
      def a
        if bad?
          fail :x
        end
        notify
      end
    RUBY
    ['fail(...) and return (fail returns false, so it never returns)', <<~RUBY, [[:fail, 2]]],
      def a
        fail(:x) and return
        work
      end
    RUBY
    ['fail(...) or return (write return fail(...))', <<~RUBY, [[:fail, 2]]],
      def a
        fail(:x) or return
        work
      end
    RUBY
    ['self.fail followed by more code', <<~RUBY, [[:fail, 2]]],
      def a
        self.fail :x
        work
      end
    RUBY
    ['nested in a larger expression', "def a = log(fail(:x))\n", [[:fail, 1]]],
    ['the left side of && (succeed returns true, so the right side runs)', "def a = succeed && notify\n", [[:succeed, 1]]],
    ['a condition', "def a = (work if succeed)\n", [[:succeed, 1]]],
    ['a rescue modifier followed by more code', <<~RUBY, [[:fail, 2]]],
      def a
        charge rescue fail(:timeout)
        notify
      end
    RUBY
    ['a begin body that has an else', <<~RUBY, [[:fail, 3]]],
      def a
        begin
          fail :x
        rescue StandardError
          recover
        else
          work
        end
      end
    RUBY
    ['a rescue branch followed by more code', <<~RUBY, [[:fail, 5]]],
      def a
        begin
          charge
        rescue Timeout::Error
          fail :timeout
        end
        notify
      end
    RUBY
    ['the end of a block followed by more code', <<~RUBY, [[:fail, 2]]],
      def a
        items.each { |i| fail :bad if i.bad? }
        save
      end
    RUBY
    ['mid-block', <<~RUBY, [[:fail, 3]]],
      def a
        items.each do |i|
          fail :bad if i.bad?
          process(i)
        end
      end
    RUBY
    ['followed by next in a block followed by more code', <<~RUBY, [[:fail, 4]]],
      def a
        items.each do |i|
          if i.bad?
            fail :bad
            next
          end
        end
        save
      end
    RUBY
    ['next fail(...) in a block followed by more code', <<~RUBY, [[:fail, 2]]],
      def a
        items.each { |i| next fail(:bad) if i.bad? }
        save
      end
    RUBY
    ['a loop body followed by more code', <<~RUBY, [[:fail, 3]]],
      def a
        while (item = queue.pop)
          fail :bad if item.bad?
        end
        save
      end
    RUBY
    ['followed by a value', <<~RUBY, [[:fail, 2]]]
      def a
        fail :x
        nil
      end
    RUBY
  ].freeze

  ALL = (OK + OFFENSES).freeze
end
