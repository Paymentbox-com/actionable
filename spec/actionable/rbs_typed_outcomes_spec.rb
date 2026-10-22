# frozen_string_literal: true

require_relative '../support/rbs_environment'

class RbsTypedAction < Actionable::Action
  typed_outcomes
  input { required :id, :integer }
  output { required :name, :string }
  fails(:invalid) { optional :form_record, :value }
  fails :not_found
  skips(:already_active) { required :name, :string }
  skips :not_ready
end

class RbsTypedChild < RbsTypedAction
end

class RbsTypedBare < Actionable::Action
  typed_outcomes
end

class RbsTypedClash < Actionable::Action
  typed_outcomes
  skips(:counted) { required :id, :integer }
  skips(:named) { optional :id, :string }
end

RSpec.describe Actionable::RBS, 'under typed outcomes (decision D23)' do
  def add_signature(env, source)
    buffer, directives, decls = RBS::Parser.parse_signature(source)
    env.add_signature(buffer: buffer, directives: directives, decls: decls)
  end

  it 'types each outcome as the action’s own result class, its output per code' do
    expect(described_class.generate(RbsTypedAction)).to eq(<<~RBS)
      class RbsTypedAction < ::Actionable::Action
        type failure_code = :invalid | :not_found | :invalid_input | :invalid_output
        type skip_code = :already_active | :not_ready

        def self.run: (id: ::Integer) -> (Success | Skipped | Failure)
                    | (InputSchema input) -> (Success | Skipped | Failure)

        def input: () -> InputSchema

        @name: ::String?

        class InputSchema < ::FieldStruct::Base
          attr_reader id: ::Integer
          def id=: (::Integer? value) -> ::Integer?
        end

        class Output < ::FieldStruct::Base
          attr_reader name: ::String
          def name=: (::String? value) -> ::String?
        end

        class AlreadyActiveSkipOutput < ::FieldStruct::Base
          attr_reader name: ::String
          def name=: (::String? value) -> ::String?
        end

        class InvalidFailureOutput < ::FieldStruct::Base
          attr_reader form_record: untyped
          def form_record=: (untyped value) -> untyped
        end

        class Success < ::Actionable::Success
          def code: () -> :success
          def output: () -> Output
          def name: () -> ::String
        end

        class Skipped < ::Actionable::Skipped
          def code: () -> skip_code
          def output: () -> (AlreadyActiveSkipOutput | ::Hash[::Symbol, untyped])
          def name: () -> ::String
        end

        class Failure < ::Actionable::Failure
          def code: () -> failure_code
          def output: () -> (InvalidFailureOutput | AlreadyActiveSkipOutput | Output | ::Hash[::Symbol, untyped])
          def form_record: () -> untyped
          def name: () -> ::String?
        end
      end
    RBS
  end

  it 'types a field several schemas declare as the union of their types, nullable if any is optional' do
    expect(described_class.generate(RbsTypedClash)).to include("def id: () -> (::Integer | ::String)?\n  end\n\n  class Failure")
  end

  it 'produces syntactically valid RBS' do
    expect { RBS::Parser.parse_signature(described_class.generate(RbsTypedAction)) }.not_to raise_error
  end

  it 'resolves a subclass’s result classes without the parent being generated too' do
    env = RbsEnvironment.base
    add_signature(env, described_class.generate(RbsTypedChild))
    builder = RBS::DefinitionBuilder.new(env: env.resolve_type_names)

    %w[Success Skipped Failure].each do |name|
      expect { builder.build_instance(RBS::TypeName.parse("::RbsTypedChild::#{name}")) }.not_to raise_error
    end
  end

  it 'declares a parent’s result classes empty, so they merge with the parent’s own signature' do
    env = RBS::Environment.new
    [RbsTypedAction, RbsTypedChild].each do |klass|
      add_signature(env, described_class.generate(klass))
    end

    expect(env.class_decls[RBS::TypeName.parse('::RbsTypedAction::Success')].decls.size).to eq(2)
  end

  it 'makes a subclass’s result classes kinds of its parent’s' do
    child = described_class.generate(RbsTypedChild)

    expect(child).to include('class Success < ::RbsTypedAction::Success', 'class Failure < ::RbsTypedAction::Failure')
  end

  it 'types an action that declares nothing with plain symbols and hashes' do
    expect(described_class.generate(RbsTypedBare)).to eq(<<~RBS)
      class RbsTypedBare < ::Actionable::Action
        def self.run: (*untyped) -> (Success | Skipped | Failure)

        class Success < ::Actionable::Success
          def code: () -> :success
          def output: () -> ::Hash[::Symbol, untyped]
        end

        class Skipped < ::Actionable::Skipped
          def code: () -> ::Symbol
          def output: () -> ::Hash[::Symbol, untyped]
        end

        class Failure < ::Actionable::Failure
          def code: () -> ::Symbol
          def output: () -> ::Hash[::Symbol, untyped]
        end
      end
    RBS
  end
end
