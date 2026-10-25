# frozen_string_literal: true

# Every ```ruby block in the user-facing docs must at least parse, doctest or
# not. docs_examples_spec runs only the `<!-- doctest -->` blocks, so a plain
# block could rot into invalid Ruby unseen (matches field_struct's guard).
RSpec.describe 'Ruby code blocks in the docs' do
  root = File.expand_path('..', __dir__)
  docs = %w[README.md USAGE.md UPGRADING.md AGENTS.md skills/actionable/SKILL.md].map { |f| File.join(root, f) } + Dir[File.join(root, 'docs/*.md')]

  # [[path, first code line, source], ...] for every ```ruby fence.
  blocks = docs.flat_map do |path|
    lines = File.readlines(path)
    found = []
    lines.each_with_index do |line, index|
      next unless line.match?(/\A\s*```ruby\b/)

      body = lines[(index + 1)..].take_while { |l| !l.match?(/\A\s*```\s*\z/) }
      found << [path, index + 2, body.join]
    end
    found
  end

  it 'finds blocks to check' do
    expect(blocks.size).to be > 40
  end

  blocks.each do |path, line, source|
    it "parses #{File.basename(path)}:#{line}" do
      expect { RubyVM::InstructionSequence.compile(source, path, path, line) }.not_to raise_error
    end
  end
end
