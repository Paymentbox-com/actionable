# frozen_string_literal: true

require 'active_record'
require 'actionable/rails'
require 'actionable/rspec'
require 'actionable/job'
require_relative '../support/rbs_environment'

# The adapters' public surface must be in sig/ (owner ruling P11): clients get
# types for what they call. Most of it is generated from YARD by sord and kept
# fresh by `rake sigs:check`; this guard catches what that cannot see — a
# runtime mix-in (Action's singleton_class.prepend of Rails::AfterCommit,
# declared by hand in sig/actionable/rails.rbs) with no matching RBS, or an
# adapter file dropped from sord's input. It compares, by reflection, every
# public method each adapter type answers to with the methods its RBS
# definition declares.
RSpec.describe 'adapter signatures' do
  before(:all) do
    env = RbsEnvironment.base.resolve_type_names
    @builder = RBS::DefinitionBuilder.new(env: env)
  end

  # @return [Array<Symbol>] the public methods +type+'s RBS definition
  #   declares; none when sig/ does not declare the type at all
  def rbs_public_methods(type, singleton:)
    name = RBS::TypeName.parse("::#{type.name}")
    return [] unless @builder.env.class_decls.key?(name)

    definition = singleton ? @builder.build_singleton(name) : @builder.build_instance(name)
    definition.methods.select { |_, method| method.accessibility == :public }.keys
  end

  # The public methods Ruby reports for +owner+'s own ancestors (stopping at
  # +stop+), i.e. this type's and its mix-ins', not Object's/Module's.
  def ruby_public_methods(owner, stop:)
    owner.ancestors.take_while { |mod| mod != stop }.flat_map { |mod| mod.public_instance_methods(false) }.uniq
  end

  it 'declares every public class method of Actionable::Action, the adapter macros included' do
    reflected = ruby_public_methods(Actionable::Action.singleton_class, stop: Object.singleton_class)

    expect(reflected).to include(:transactional, :transaction_config, :after_commit, :after_commit_hooks,
      :honor_retry_metadata)
    expect(reflected - rbs_public_methods(Actionable::Action, singleton: true)).to eq([])
  end

  {
    'Actionable::Runner' => Object,
    'Actionable::Rails::Transactions' => nil,
    'Actionable::Rails::AfterCommit' => nil,
    'Actionable::Job::Mixin' => nil,
    'Actionable::Job::RetryMetadata' => nil,
    'Actionable::Job::RetryableFailure' => StandardError,
    'Actionable::RSpec::Matchers' => nil,
    'Actionable::RSpec::Stubs' => nil,
    'Actionable::RSpec::PerformActionable' => Object
  }.each do |const, stop|
    it "declares every public instance method of #{const}" do
      type = Object.const_get(const)
      reflected = stop ? ruby_public_methods(type, stop: stop) : type.public_instance_methods(false)

      expect(reflected).not_to be_empty
      expect(reflected - rbs_public_methods(type, singleton: false)).to eq([])
    end
  end

  %w[Actionable::Job Actionable::RSpec].each do |const|
    it "declares every public module function of #{const}" do
      type = Object.const_get(const)
      reflected = type.singleton_methods(false)

      expect(reflected).not_to be_empty
      expect(reflected - rbs_public_methods(type, singleton: true)).to eq([])
    end
  end
end
