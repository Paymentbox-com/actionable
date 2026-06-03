# frozen_string_literal: true

# Executable documentation (decision D16): every ```ruby block in README.md /
# USAGE.md / docs/getting_started.md preceded by an invisible `<!-- doctest -->`
# HTML comment is run here, so the published examples can't silently rot.
#
# Each marked block is evaluated in its own throwaway module — mark only
# self-contained blocks. Lines of the form `expr # => expected` are asserted by
# evaluating BOTH sides and comparing with `==`, which is robust to
# inspect-format / Ruby-version differences. Lines whose expected value isn't
# valid Ruby to eval (e.g. `#<Actionable::Success ...>` inspect output) are
# executed but not asserted. Adapter examples (Rails/RSpec) are intentionally
# left unmarked so the core suite stays dependency-free.

# Raises with a precise location when a documented `# =>` expectation is wrong.
# Defined at top level so module_eval'd block code can call it.
def __doctest_eq(actual, expected, label)
  return if actual == expected

  raise "#{label}: documented #{expected.inspect}, but evaluated to #{actual.inspect}"
end

module DocExamples
  Block = Struct.new(:first_code_line, :source)

  module_function

  # Extract ```ruby blocks immediately preceded by a `<!-- doctest -->` line.
  def blocks(path)
    lines = File.readlines(path)
    found = []
    index = 0
    while index < lines.length
      unless lines[index].strip == '<!-- doctest -->'
        index += 1
        next
      end

      fence = index + 1
      fence += 1 while fence < lines.length && lines[fence].strip.empty?
      unless fence < lines.length && lines[fence].strip.start_with?('```ruby')
        index += 1
        next
      end

      close = fence + 1
      close += 1 until close >= lines.length || lines[close].strip == '```'
      found << Block.new(fence + 2, lines[(fence + 1)...close].join)
      index = close + 1
    end
    found
  end

  # Can the documented expected-value be evaluated as Ruby for comparison?
  def assertable?(expected)
    return false if expected.start_with?('#<') # inspect form, not eval-able

    RubyVM::InstructionSequence.compile("(#{expected}\n)")
    true
  rescue SyntaxError, StandardError
    false
  end

  # Rewrite `expr # => expected` lines into assertions; leave the rest verbatim.
  def to_runnable(block, label_prefix)
    block.source.each_line.with_index.map do |line, offset|
      match = line.match(/\A(\s*)(\S.*?)\s*#\s*=>\s*(.+?)\s*\R?\z/)
      next line unless match && assertable?(match[3])

      label = "#{label_prefix}:#{block.first_code_line + offset}"
      %(#{match[1]}__doctest_eq((#{match[2]}), (#{match[3]}), #{label.inspect})\n)
    end.join
  end
end

RSpec.describe 'Documentation examples' do
  %w[README.md USAGE.md docs/getting_started.md].each do |doc|
    path = File.expand_path("../#{doc}", __dir__)
    blocks = DocExamples.blocks(path)

    it "#{doc} has at least one doctest block" do
      expect(blocks).not_to be_empty
    end

    blocks.each_with_index do |block, position|
      it "#{doc} doctest block ##{position + 1} (line #{block.first_code_line})" do
        sandbox = Module.new
        const = "DocExample_#{doc.gsub(/[^a-zA-Z0-9]/, "_")}_#{position}"
        Object.const_set(const, sandbox)
        begin
          sandbox.module_eval(DocExamples.to_runnable(block, doc), path, block.first_code_line)
        ensure
          Object.send(:remove_const, const)
        end
      end
    end
  end
end
