# frozen_string_literal: true

RSpec.describe 'the packaged gem' do
  let(:files) { Gem::Specification.load(File.expand_path('../actionable.gemspec', __dir__)).files }

  it 'ships the library, signatures and user-facing docs' do
    expect(files).to include('lib/actionable.rb', 'sig/actionable.rbs', 'README.md', 'USAGE.md',
      'CHANGELOG.md', 'AGENTS.md', 'docs/getting_started.md',
      'skills/actionable/SKILL.md')
  end

  it 'leaves out contributor-only files' do
    expect(files.grep(%r{\A(\.claude/|CLAUDE\.md|docs/origin/|Rakefile|Steepfile|gemfiles/|benchmarks/|\.rubocop|\.yardopts|rbs_collection)}))
      .to be_empty
  end
end
