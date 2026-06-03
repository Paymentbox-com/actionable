# frozen_string_literal: true

require_relative 'lib/actionable/version'

Gem::Specification.new do |spec|
  spec.name = 'actionable'
  spec.version = Actionable::VERSION
  spec.authors = ['Adrian Madrid']
  spec.email = ['amadrid@pmtbox.com']

  spec.summary = 'Simple, typed, composable Ruby service objects.'
  spec.description = <<~DESC
    Actionable encapsulates business logic as an ordered sequence of steps that
    return a single typed result. Pure-Ruby core (Rails transactions and validators
    are an optional adapter); inputs and outputs are typed via field_struct; full RBS
    signatures via Sord + YARD.
  DESC
  spec.homepage = 'https://github.com/Paymentbox-com/actionable'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.pkg.github.com/Paymentbox-com'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'field_struct'        # typed input/output schemas + result objects
  spec.add_dependency 'oj', '>= 3.0'         # JSON for history/result serialization (D15)
end
