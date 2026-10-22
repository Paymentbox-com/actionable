# frozen_string_literal: true

require_relative '../support/rbs_environment'

class RbsIoAddress < FieldStruct::Base
  required :city, :string
end

class RbsIoAction < Actionable::Action
  input do
    required :amount, :integer
    optional :note, :string
    required :tags, :array, of: :string
    optional :address, RbsIoAddress
    required :stops, :array, of: RbsIoAddress
    optional :meta, :value
  end
  output do
    required :total, :integer
    optional :lines, :array, of: :string
  end
end

class RbsIoTyped < Actionable::Action
  typed_outcomes
  input { required :id, :integer }
  output { optional :name, :string }
  fails(:invalid) { optional :form_record, :value }
end

# An action under a member-less intermediate base (the A-6 chain).
class RbsIoApplicationAction < Actionable::Action
end

class RbsIoLeaf < RbsIoApplicationAction
  input { required :id, :integer }
  output { required :name, :string }
end

# A subclass inherits its parent's schemas, so both declare the same ivars.
class RbsIoChild < RbsIoAction
end

class RbsIoOutputOnly < Actionable::Action
  output { required :total, :integer }
end

class RbsIoCollision < Actionable::Action
  InputSchema = Class.new
  input { required :id, :integer }
end

class RbsIoCollisionBase < Actionable::Action
  InputSchema = Class.new
end

class RbsIoInheritedCollision < RbsIoCollisionBase
  input { required :id, :integer }
end

module RbsIoCollisionMixin
  InputSchema = Class.new
end

class RbsIoMixedInCollision < Actionable::Action
  include RbsIoCollisionMixin

  input { required :id, :integer }
end

# Without an input schema there is no InputSchema to collide with.
class RbsIoNoInputCollision < Actionable::Action
  InputSchema = Class.new
  output { required :total, :integer }
end

RSpec.describe Actionable::RBS, 'typed input and output ivars' do
  # The gem's signatures, field_struct's, the named nested struct's, and each
  # action's RBS in a file of its own, as a host has them.
  def environment_for(*klasses)
    env = RbsEnvironment.base
    sources = {'RbsIoAddress' => FieldStruct::RBS.generate(RbsIoAddress)}
    klasses.each { |klass| sources[klass.name] = described_class.generate(klass) }
    sources.each do |name, source|
      buffer = RBS::Buffer.new(name: Pathname("generated/#{name}.rbs"), content: source)
      _, directives, decls = RBS::Parser.parse_signature(buffer)
      env.add_signature(buffer: buffer, directives: directives, decls: decls)
    end
    env.resolve_type_names
  end

  # Build and validate every generated class's instance and singleton
  # definitions, as `rbs validate` does.
  def builder_for(*klasses)
    env = environment_for(*klasses)
    builder = RBS::DefinitionBuilder.new(env: env)
    validator = RBS::Validator.new(env: env)
    generated = env.class_decls.select do |_, entry|
      entry.decls.any? { |d| d.decl.location&.buffer&.name.to_s.start_with?('generated/') }
    end
    generated.each_key do |name|
      builder.build_instance(name).each_type { |type| validator.validate_type(type, context: nil) }
      builder.build_singleton(name).each_type { |type| validator.validate_type(type, context: nil) }
    end
    builder
  end

  def instance(builder, name)
    builder.build_instance(RBS::TypeName.parse(name))
  end

  def method_types(definition, name)
    definition.methods.fetch(name).method_types.map(&:to_s)
  end

  def ivar_types(definition)
    own = definition.instance_variables.reject { |_, ivar| ivar.declared_in.to_s == '::Actionable::Action' }
    own.transform_values { |ivar| ivar.type.to_s }
  end

  it 'emits InputSchema, the typed .run overloads, #input and the output ivars' do
    expect(described_class.generate(RbsIoAction)).to eq(<<~RBS)
      class RbsIoAction < ::Actionable::Action
        def self.run: (amount: ::Integer, ?note: ::String?, tags: ::Array[::String?], ?address: ::RbsIoAddress?, stops: ::Array[::RbsIoAddress], ?meta: untyped) -> Result
                    | (InputSchema input) -> Result

        def input: () -> InputSchema

        @total: ::Integer?
        @lines: ::Array[::String?]?

        class InputSchema < ::FieldStruct::Base
          attr_reader amount: ::Integer
          def amount=: (::Integer? value) -> ::Integer?
          attr_reader note: ::String?
          def note=: (::String? value) -> ::String?
          attr_reader tags: ::Array[::String?]
          def tags=: (::Array[::String?]? value) -> ::Array[::String?]?
          attr_reader address: ::RbsIoAddress?
          def address=: (::RbsIoAddress? value) -> ::RbsIoAddress?
          attr_reader stops: ::Array[::RbsIoAddress]
          def stops=: (::Array[::RbsIoAddress]? value) -> ::Array[::RbsIoAddress]?
          attr_reader meta: untyped
          def meta=: (untyped value) -> untyped
        end

        class Output < ::FieldStruct::Base
          attr_reader total: ::Integer
          def total=: (::Integer? value) -> ::Integer?
          attr_reader lines: ::Array[::String?]?
          def lines=: (::Array[::String?]? value) -> ::Array[::String?]?
        end

        class Result < ::Actionable::Result
          def output: () -> Output
          def total: () -> ::Integer
          def lines: () -> ::Array[::String?]?
        end
      end
    RBS
  end

  it 'builds the action, its InputSchema and its Result with typed members' do
    builder = builder_for(RbsIoAction)
    action = instance(builder, '::RbsIoAction')
    schema = instance(builder, '::RbsIoAction::InputSchema')

    expect(method_types(action, :input)).to eq(['() -> ::RbsIoAction::InputSchema'])
    expect(ivar_types(action)).to eq(:@total => '::Integer?', :@lines => '::Array[::String?]?')
    expect(method_types(schema, :stops)).to eq(['() -> ::Array[::RbsIoAddress]'])
    expect(method_types(schema, :address=)).to eq(['(::RbsIoAddress? value) -> ::RbsIoAddress?'])
    expect(method_types(schema, :meta)).to eq(['() -> untyped'])
    expect(method_types(instance(builder, '::RbsIoAction::Result'), :total)).to eq(['() -> ::Integer'])
    expect(method_types(builder.build_singleton(RBS::TypeName.parse('::RbsIoAction')), :run))
      .to include('(::RbsIoAction::InputSchema input) -> ::RbsIoAction::Result')
  end

  it 'types input and output ivars under typed outcomes' do
    builder = builder_for(RbsIoTyped)
    action = instance(builder, '::RbsIoTyped')

    expect(method_types(action, :input)).to eq(['() -> ::RbsIoTyped::InputSchema'])
    expect(ivar_types(action)).to eq(:@name => '::String?')
    expect(method_types(instance(builder, '::RbsIoTyped::InputSchema'), :id)).to eq(['() -> ::Integer'])
    expect(method_types(instance(builder, '::RbsIoTyped::Failure'), :form_record)).to eq(['() -> untyped'])
    expect(method_types(builder.build_singleton(RBS::TypeName.parse('::RbsIoTyped')), :run))
      .to include('(::RbsIoTyped::InputSchema input) -> (::RbsIoTyped::Success | ::RbsIoTyped::Skipped | ::RbsIoTyped::Failure)')
  end

  it 'builds an action under an intermediate base' do
    builder = builder_for(RbsIoLeaf)
    leaf = instance(builder, '::RbsIoLeaf')

    expect(leaf.ancestors.ancestors.map { |a| a.name.to_s }).to include('::RbsIoApplicationAction')
    expect(method_types(leaf, :input)).to eq(['() -> ::RbsIoLeaf::InputSchema'])
    expect(ivar_types(leaf)).to eq(:@name => '::String?')
  end

  it 'builds a subclass that inherits its parent’s schemas, each generated into its own file' do
    builder = builder_for(RbsIoAction, RbsIoChild)

    expect(method_types(instance(builder, '::RbsIoChild'), :input)).to eq(['() -> ::RbsIoChild::InputSchema'])
    expect(ivar_types(instance(builder, '::RbsIoChild'))).to include(:@total => '::Integer?')
  end

  it 'emits no InputSchema or #input for an action without an input schema' do
    rbs = described_class.generate(RbsIoOutputOnly)

    expect(rbs).not_to include('InputSchema')
    expect(rbs).not_to include('def input')
    expect(rbs).to include("  @total: ::Integer?\n")
  end

  it 'refuses to generate when Ruby already resolves the action’s InputSchema constant' do
    expect { described_class.generate(RbsIoCollision) }
      .to raise_error(ArgumentError, /RbsIoCollision::InputSchema is already defined \(in RbsIoCollision\)/)
    expect { described_class.generate(RbsIoInheritedCollision) }
      .to raise_error(ArgumentError, /RbsIoInheritedCollision::InputSchema is already defined \(in RbsIoCollisionBase\)/)
    expect { described_class.generate(RbsIoMixedInCollision) }
      .to raise_error(ArgumentError, /already defined \(in RbsIoCollisionMixin\)/)
  end

  it 'ignores an InputSchema constant when the action declares no input schema' do
    expect { described_class.generate(RbsIoNoInputCollision) }.not_to raise_error
  end
end
