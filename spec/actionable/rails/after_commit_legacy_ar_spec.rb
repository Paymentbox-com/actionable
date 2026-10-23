# frozen_string_literal: true

require 'active_record'
require 'actionable/rails'

# A real ActiveRecord older than 7.2 (the activerecord-7.1 CI lane, run with
# gemfiles/activerecord_7_1.gemfile): +after_commit+ must refuse to declare,
# naming the version it needs, while +transactional+ keeps working (the
# transactions specs run on the same lane). Skipped on 7.2+, where
# after_commit_ar_spec covers the hook.
RSpec.describe 'Actionable::Rails after_commit on an ActiveRecord older than 7.2',
  skip: (ActiveRecord.respond_to?(:after_all_transactions_commit) ? 'needs ActiveRecord < 7.2' : false) do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define { create_table(:legacy_widgets) { |t| t.string :name } }
    Object.const_set(:LegacyWidget, Class.new(ActiveRecord::Base) { self.table_name = 'legacy_widgets' })
  end

  after(:all) do
    Object.send(:remove_const, :LegacyWidget)
    ActiveRecord::Base.remove_connection
  end

  before { LegacyWidget.delete_all }

  it 'is really running on an ActiveRecord below the after_commit minimum' do
    expect(ActiveRecord.gem_version).to be < Gem::Version.new(Actionable::Rails::AfterCommit::MINIMUM_ACTIVE_RECORD)
  end

  it 'raises a DefinitionError naming 7.2 when after_commit is declared' do
    expect { Class.new(Actionable::Action) { after_commit :notify } }
      .to raise_error(Actionable::DefinitionError, /ActiveRecord >= 7\.2/)
  end

  it 'leaves a transactional action without after_commit working' do
    klass = Class.new(Actionable::Action) do
      transactional model: LegacyWidget
      define_method(:write) { LegacyWidget.create!(name: 'kept') }
      step :write
    end

    expect(klass.run).to be_success
    expect(LegacyWidget.pluck(:name)).to eq(%w[kept])
  end
end
