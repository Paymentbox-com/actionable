# frozen_string_literal: true

require 'rbs'

# A host's hierarchy: an application base with no members, an intermediate base
# under it, and the actions that run.
class RbsChainApplicationAction < Actionable::Action
end

class RbsChainBase < RbsChainApplicationAction
end

class RbsChainLeaf < RbsChainBase
  input { required :id, :integer }
  output { required :name, :string }
end

class RbsChainDirect < Actionable::Action
  output { required :name, :string }
end

module RbsChainCodes
  class BaseAction < RbsChainApplicationAction
  end

  class DecideMapping < BaseAction
    output { required :id, :integer }
  end
end

class RbsChainApplicationAction
  # An action namespaced inside a class (its own base), not a module.
  class Nested < RbsChainApplicationAction
  end
end

class RbsChainTypedBase < RbsChainApplicationAction
  typed_outcomes
  fails :refused
end

class RbsChainTyped < RbsChainTypedBase
  skips :not_ready
end

# A named action under an anonymous intermediate class.
RbsChainPastAnonymous = Class.new(Class.new(RbsChainApplicationAction))

RSpec.describe Actionable::RBS, 'superclass chain' do
  # The gem's own signatures, plus field_struct's, as a host's environment has.
  def base_environment
    loader = RBS::EnvironmentLoader.new
    loader.add(path: Pathname(File.expand_path('../../sig', __dir__)))
    loader.add(path: Pathname(Gem.loaded_specs.fetch('field_struct').full_gem_path).join('sig'))
    RBS::Environment.from_loader(loader)
  end

  # Each action's RBS in a file of its own, as a host writes them.
  def environment_for(*klasses)
    env = base_environment
    klasses.each do |klass|
      buffer = RBS::Buffer.new(name: Pathname("generated/#{klass.name}.rbs"), content: described_class.generate(klass))
      _, directives, decls = RBS::Parser.parse_signature(buffer)
      env.add_signature(buffer: buffer, directives: directives, decls: decls)
    end
    env.resolve_type_names
  end

  # What `rbs validate` does per class: build both definitions and validate
  # every type they mention. Only the generated declarations are checked.
  def validate_generated(env)
    builder = RBS::DefinitionBuilder.new(env: env)
    validator = RBS::Validator.new(env: env)
    generated = env.class_decls.select do |_, entry|
      entry.decls.any? { |d| d.decl.location&.buffer&.name.to_s.start_with?('generated/') }
    end
    expect(generated).not_to be_empty
    generated.each_key do |name|
      builder.build_instance(name).each_type { |type| validator.validate_type(type, context: nil) }
      builder.build_singleton(name).each_type { |type| validator.validate_type(type, context: nil) }
    end
    builder
  end

  # The Ruby superclasses from +klass+ up to Actionable::Action, as RBS names.
  def ruby_chain(klass)
    klass.ancestors.grep(Class).take_while { |c| c != Actionable::Action }.map { |c| "::#{c.name}" } +
      ['::Actionable::Action']
  end

  def rbs_chain(builder, klass)
    expected = ruby_chain(klass)
    names = builder.build_instance(RBS::TypeName.parse("::#{klass.name}")).ancestors.ancestors.map { |a| a.name.to_s }
    names.select { |name| expected.include?(name) }
  end

  [
    ['a direct subclass', RbsChainDirect],
    ['a two-level chain through member-less bases', RbsChainLeaf],
    ['a namespaced action under a namespaced base', RbsChainCodes::DecideMapping],
    ['an action namespaced inside its base class', RbsChainApplicationAction::Nested],
    ['a typed action under a typed base', RbsChainTyped]
  ].each do |label, klass|
    context "for #{label}" do
      it 'builds and validates the action class, with Ruby’s superclass chain' do
        builder = validate_generated(environment_for(klass))

        expect(rbs_chain(builder, klass)).to eq(ruby_chain(klass))
      end
    end
  end

  it 'declares each member-less ancestor, outermost first, before the action' do
    expect(described_class.generate(RbsChainLeaf)).to start_with(<<~RBS)
      class RbsChainApplicationAction < ::Actionable::Action
      end

      class RbsChainBase < ::RbsChainApplicationAction
      end

      class RbsChainLeaf < ::RbsChainBase
    RBS
  end

  it 'declares a namespaced base inside its module, and a class namespace as a class' do
    expect(described_class.generate(RbsChainCodes::DecideMapping)).to start_with(<<~RBS)
      class RbsChainApplicationAction < ::Actionable::Action
      end

      module RbsChainCodes
        class BaseAction < ::RbsChainApplicationAction
        end
      end

      module RbsChainCodes
        class DecideMapping < ::RbsChainCodes::BaseAction
    RBS
    expect(described_class.generate(RbsChainApplicationAction::Nested)).to include(<<~RBS)
      class RbsChainApplicationAction
        class Nested < ::RbsChainApplicationAction
    RBS
  end

  it 'skips an anonymous ancestor, naming the next named one as the superclass' do
    rbs = described_class.generate(RbsChainPastAnonymous)

    expect(rbs).to include("class RbsChainPastAnonymous < ::RbsChainApplicationAction\n")
    expect { validate_generated(environment_for(RbsChainPastAnonymous)) }.not_to raise_error
  end

  it 'validates actions sharing a base, each generated into its own file' do
    env = environment_for(RbsChainLeaf, RbsChainCodes::DecideMapping, RbsChainApplicationAction::Nested, RbsChainTyped)

    expect { validate_generated(env) }.not_to raise_error
    expect(env.class_decls[RBS::TypeName.parse('::RbsChainApplicationAction')].decls.size).to eq(5)
  end
end
