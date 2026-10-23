# frozen_string_literal: true

# Drift guard for UPGRADING.md, matching field_struct's convention (see
# CLAUDE.md "Documentation checklist"):
#
# - Every CHANGELOG entry carrying an "**Upgrade note:**" (or "**Upgrading:**")
#   in [Unreleased] and every version >= 1.5.2 holds an invisible
#   `<!-- upgrading: some-slug -->` marker in the same bullet or paragraph.
#   Any other entry a caller can observe may opt in with a marker.
# - UPGRADING.md carries the same marker under the entry that explains it, in
#   the "## X → Y" section of the version that shipped it ([Unreleased] ships
#   as the range's TO). Every guide marker exists in the CHANGELOG.
# - UPGRADING.md declares `<!-- upgrading-range: FROM..TO -->`. TO must reach
#   the gem's VERSION and the newest dated CHANGELOG version, and pass it while
#   [Unreleased] has marked entries: the guide is written for the next release
#   before version.rb is bumped.
#
# The slug is the key, not the wording, so either file can be reworded freely.
module UpgradingGuide
  MARKER = /<!--\s*upgrading:\s*([a-z0-9][a-z0-9-]*)\s*-->/
  RANGE = /<!--\s*upgrading-range:\s*(\d+\.\d+\.\d+)\.\.(\d+\.\d+\.\d+)\s*-->/
  NOTE = /\*\*Upgrad(?:e note|ing):\*\*/
  FIRST_GUARDED = Gem::Version.new('1.5.2')

  module_function

  # CHANGELOG sections as { "Unreleased" => text, "1.7.0" => text, ... }, in
  # file order (newest first).
  def sections(changelog)
    changelog.split(/^## \[([^\]]+)\][^\n]*\n/).drop(1).each_slice(2).to_h { |name, body| [name, body.to_s] }
  end

  def guarded?(name)
    name == 'Unreleased' || Gem::Version.new(name) >= FIRST_GUARDED
  end

  # Bullets (with their continuation lines) and paragraphs: a block starts at
  # a top-level "- ", a heading, or after a blank line.
  def blocks(text)
    text.each_line.slice_before { |line| line.start_with?('- ', '#') }
      .flat_map { |chunk| chunk.join.split(/\n\s*\n/) }
  end

  # UPGRADING.md "## A → B" sections as { "B" => text }.
  def guide_versions(upgrading)
    upgrading.split(/^## /).drop(1).each_with_object({}) do |section, found|
      to = section.lines.first[/→\s*(\d+\.\d+\.\d+)/, 1]
      found[to] = section if to
    end
  end

  # Human-readable problems; empty when the guide is in sync.
  def problems(changelog:, upgrading:, version:)
    found = []
    range = upgrading.match(RANGE)
    return ['UPGRADING.md has no `<!-- upgrading-range: FROM..TO -->` marker'] unless range

    target = Gem::Version.new(range[2])
    guarded = sections(changelog).select { |name, _| guarded?(name) }
    dated = guarded.keys.grep_v('Unreleased').map { |v| Gem::Version.new(v) }
    newest = dated.max
    floor = [Gem::Version.new(version), newest].compact.max
    if target < floor
      found << "UPGRADING.md covers up to #{target} but the gem is at #{floor}: add a section and raise the range"
    end
    if guarded['Unreleased'].to_s.match?(MARKER) && newest && target <= newest
      found << "CHANGELOG [Unreleased] has upgrade entries but UPGRADING.md stops at #{target}: " \
               'add the next version\'s section and raise the range'
    end

    by_version = guide_versions(upgrading)
    (dated.select { |v| v <= target }.map(&:to_s) | [target.to_s]).each do |v|
      found << "UPGRADING.md has no `## … → #{v}` section" unless by_version.key?(v)
    end

    changelog_slugs = []
    guarded.each do |name, text|
      blocks(text).each do |block|
        next unless block.match?(NOTE) && !block.match?(MARKER)

        found << "CHANGELOG [#{name}] upgrade note has no `<!-- upgrading: slug -->` marker: " \
                 "#{block.strip.lines.first.strip[0, 90]}"
      end
      shipped_in = name == 'Unreleased' ? target.to_s : name
      text.scan(MARKER).flatten.each do |slug|
        changelog_slugs << slug
        if !upgrading.match?(/<!--\s*upgrading:\s*#{slug}\s*-->/)
          found << "CHANGELOG [#{name}] marks `#{slug}` but UPGRADING.md has no `<!-- upgrading: #{slug} -->` entry"
        elsif !by_version[shipped_in].to_s.include?("upgrading: #{slug} ")
          found << "UPGRADING.md has `#{slug}` outside its `## … → #{shipped_in}` section"
        end
      end
    end

    guide_slugs = upgrading.scan(MARKER).flatten
    (guide_slugs - changelog_slugs).each do |slug|
      found << "UPGRADING.md marks `#{slug}` but no CHANGELOG entry since #{FIRST_GUARDED} does"
    end
    guide_slugs.tally.select { |_, n| n > 1 }.each_key { |slug| found << "UPGRADING.md marks `#{slug}` more than once" }
    found
  end

  # GitHub's heading anchor: lowercase, drop punctuation except - and _,
  # spaces to hyphens.
  def slug(heading)
    heading.strip.downcase.gsub(/[^\p{Word}\- ]/, '').tr(' ', '-')
  end

  # Anchors of every Markdown heading outside fenced code.
  def anchors(markdown)
    fenced = false
    markdown.each_line.filter_map do |line|
      fenced = !fenced if line.lstrip.start_with?('```')
      next if fenced

      (m = line.match(/\A#+ (.+)/)) && slug(m[1])
    end
  end
end

RSpec.describe 'UPGRADING.md' do
  def read(path) = File.read(File.expand_path("../#{path}", __dir__))

  let(:upgrading) { read('UPGRADING.md') }

  # The one check of the live files: whatever the release state, they agree.
  it 'has an entry for every CHANGELOG upgrade note since 1.5.2 and covers the target version' do
    expect(UpgradingGuide.problems(changelog: read('CHANGELOG.md'), upgrading: upgrading, version: Actionable::VERSION))
      .to eq([])
  end

  it 'links only to anchors that exist in itself, USAGE.md and AGENTS.md' do
    broken = {'' => upgrading, 'USAGE.md' => read('USAGE.md'), 'AGENTS.md' => read('AGENTS.md')}
      .flat_map do |file, markdown|
        anchors = UpgradingGuide.anchors(markdown)
        upgrading.scan(/\]\(#{Regexp.escape(file)}#([^)]+)\)/).flatten.reject { |a| anchors.include?(a) }
          .map { |a| "#{file}##{a}" }
      end
    expect(broken).to eq([])
  end

  # Fixtures, not the live files: the rules must bite in any release state
  # (right after a release [Unreleased] is empty and the version sits at the
  # top of the range). Each example breaks one thing in an in-sync pair.
  describe 'the guard itself' do
    let(:changelog) do
      <<~MD
        # Changelog

        ## [Unreleased]

        ## [2.1.0] - 2026-02-01

        ### Changed

        - **Beta.** Details. **Upgrade note:** act. <!-- upgrading: beta -->

        ## [2.0.0] - 2026-01-01

        ### Changed

        - **Alpha.** **Upgrade note:** act. <!-- upgrading: alpha -->

        ## [1.0.0] - 2025-01-01

        - **Unguarded.** **Upgrade note:** history before 1.5.2 is not checked.
      MD
    end
    let(:upgrading) do
      <<~MD
        <!-- upgrading-range: 1.9.0..2.1.0 -->

        ## 1.9.0 → 2.0.0

        ### Alpha
        <!-- upgrading: alpha -->

        ## 2.0.0 → 2.1.0

        ### Beta
        <!-- upgrading: beta -->
      MD
    end
    # [Unreleased] holding a marked entry, with the guide already written for
    # the next release (2.2.0) before version.rb is bumped.
    let(:pending_changelog) do
      changelog.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Changed\n\n" \
                                         "- **Probe.** **Upgrade note:** act. <!-- upgrading: probe -->\n")
    end
    let(:pending_upgrading) do
      upgrading.sub('1.9.0..2.1.0', '1.9.0..2.2.0') + "\n## 2.1.0 → 2.2.0\n\n### Probe\n<!-- upgrading: probe -->\n"
    end

    def problems(changelog: self.changelog, upgrading: self.upgrading, version: '2.1.0')
      UpgradingGuide.problems(changelog: changelog, upgrading: upgrading, version: version)
    end

    it 'passes an in-sync pair' do
      expect(problems).to eq([])
    end

    it 'fails when an UPGRADING.md entry is deleted' do
      expect(problems(upgrading: upgrading.sub('<!-- upgrading: beta -->', '')))
        .to include(a_string_including('`beta` but UPGRADING.md has no'))
    end

    it 'fails when an UPGRADING.md entry has no CHANGELOG entry' do
      expect(problems(upgrading: "#{upgrading}<!-- upgrading: ghost -->\n"))
        .to include(a_string_including('marks `ghost` but no CHANGELOG entry'))
    end

    it 'fails when an upgrade note has no marker' do
      note = "## [Unreleased]\n\n### Added\n\n- **Something.** Details. **Upgrade note:** act.\n"
      expect(problems(changelog: changelog.sub("## [Unreleased]\n", note)))
        .to include(a_string_including('[Unreleased] upgrade note has no'))
    end

    it 'fails when an entry sits under the wrong version' do
      moved = upgrading.sub("<!-- upgrading: beta -->\n", '').sub("### Alpha\n", "### Alpha\n<!-- upgrading: beta -->\n")
      expect(problems(upgrading: moved)).to include(a_string_including('`beta` outside its `## … → 2.1.0` section'))
    end

    it 'fails when the range marker is removed' do
      expect(problems(upgrading: upgrading.sub(UpgradingGuide::RANGE, '')))
        .to eq(['UPGRADING.md has no `<!-- upgrading-range: FROM..TO -->` marker'])
    end

    it 'fails when the version moves past the covered range' do
      expect(problems(version: '2.2.0')).to include(a_string_including('covers up to 2.1.0 but the gem is at 2.2.0'))
    end

    it 'fails when a dated version in the range has no section' do
      expect(problems(upgrading: upgrading.sub('## 1.9.0 → 2.0.0', '## Alpha notes')))
        .to include('UPGRADING.md has no `## … → 2.0.0` section')
    end

    it 'fails when [Unreleased] has upgrade entries the range does not reach' do
      expect(problems(changelog: pending_changelog)).to include(a_string_including('[Unreleased] has upgrade entries'))
    end

    it 'passes before and after the release bumps the version and dates [Unreleased]' do
      released = pending_changelog.sub("## [Unreleased]\n", "## [Unreleased]\n\n## [2.2.0] - 2026-03-01\n")

      expect(problems(changelog: pending_changelog, upgrading: pending_upgrading)).to eq([])
      expect(problems(changelog: released, upgrading: pending_upgrading, version: '2.2.0')).to eq([])
    end
  end
end
