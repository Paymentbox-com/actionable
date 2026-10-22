# frozen_string_literal: true

require 'active_record'
require 'actionable/rails'

# Real ActiveRecord on in-memory SQLite: savepoints inside an outer
# transaction are behaviour a stub model cannot show (decision D9).
RSpec.describe 'Actionable::Rails transactional macro on ActiveRecord' do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define { create_table(:ar_widgets) { |t| t.string :name } }
    stub_const_class = Class.new(ActiveRecord::Base) { self.table_name = 'ar_widgets' }
    Object.const_set(:ArWidget, stub_const_class)
  end

  after(:all) do
    Object.send(:remove_const, :ArWidget)
    ActiveRecord::Base.remove_connection
  end

  before { ArWidget.delete_all }

  def failing_child(**options)
    Class.new(Actionable::Action) do
      transactional model: ArWidget, **options
      define_method(:write) { ArWidget.create!(name: 'child') }
      define_method(:boom) { fail!(:nope) }
      step :write
      step :boom
    end
  end

  def names = ArWidget.order(:id).pluck(:name)

  it 'rolls back a failed run at the top level' do
    expect(failing_child.run.code).to eq(:nope)
    expect(names).to eq([])
  end

  it "rolls back a failed run's writes inside an outer transaction" do
    result = nil
    ArWidget.transaction do
      ArWidget.create!(name: 'outer')
      result = failing_child.run
    end

    expect(result.code).to eq(:nope)
    expect(names).to eq(%w[outer])
  end

  it 'commits a successful run inside an outer transaction with the outer one' do
    child = Class.new(Actionable::Action) do
      transactional model: ArWidget
      define_method(:write) { ArWidget.create!(name: 'child') }
      step :write
    end

    ArWidget.transaction do
      ArWidget.create!(name: 'outer')
      child.run
    end

    expect(names).to eq(%w[outer child])
  end

  it 'rolls back, always-hook writes included, when an on_success hook fails! and always runs after' do
    klass = Class.new(Actionable::Action) do
      transactional model: ArWidget
      define_method(:write) { ArWidget.create!(name: 'main') }
      define_method(:verify) { fail!(:verification_failed) }
      define_method(:audit) { ArWidget.create!(name: 'audit') }
      step :write
      on_success :verify
      always :audit
    end

    result = klass.run

    expect(result.code).to eq(:verification_failed)
    expect(names).to eq([])
  end

  it 'commits, always-hook writes included, when an on_failure hook succeed!s and always runs after' do
    klass = Class.new(Actionable::Action) do
      transactional model: ArWidget
      define_method(:write) { ArWidget.create!(name: 'main') }
      define_method(:boom) { fail(:nope) }
      define_method(:recover) { succeed!('recovered') }
      define_method(:audit) { ArWidget.create!(name: 'audit') }
      step :write
      step :boom
      on_failure :recover
      always :audit
    end

    result = klass.run

    expect(result).to be_success
    expect(names).to eq(%w[main audit])
  end

  it 'joins the outer transaction when requires_new: false is explicit' do
    ArWidget.transaction do
      ArWidget.create!(name: 'outer')
      failing_child(requires_new: false).run
    end

    expect(names).to eq(%w[outer child])
  end
end
