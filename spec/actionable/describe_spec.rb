# frozen_string_literal: true

# A named action so describe reports a real name.
class DescribeSample < Actionable::Action
  measure :all
  input { required :amount, :integer }
  output { required :invoice, :string }

  step :validate
  on_success :notify
  always :log

  def validate
  end

  def notify
  end

  def log
  end
end

RSpec.describe 'Actionable::Action.describe' do
  subject(:described) { DescribeSample.describe }

  it 'reports the action name' do
    expect(described[:name]).to eq('DescribeSample')
  end

  it 'reports input and output field metadata' do
    expect(described[:input]).to include(:amount)
    expect(described[:input][:amount]).to include(required: true)
    expect(described[:output]).to include(:invoice)
  end

  it 'lists main steps with type and name' do
    expect(described[:steps]).to include(a_hash_including(type: :method, name: :validate))
  end

  it 'lists hooks by section' do
    expect(described[:hooks][:on_success]).to eq(%i[notify])
    expect(described[:hooks][:always]).to eq(%i[log])
    expect(described[:hooks][:on_failure]).to eq([])
  end

  it 'reports the measure mode' do
    expect(described[:measure]).to eq(:all)
  end

  it 'reports transactional as nil without the Rails adapter' do
    expect(described[:transactional]).to be_nil
  end

  it 'reports nil input/output for a free-form action' do
    klass = Class.new(Actionable::Action) do
      def go
      end
      step :go
    end

    expect(klass.describe[:input]).to be_nil
    expect(klass.describe[:output]).to be_nil
  end

  it 'tags nested-action and case steps by type' do
    child = Class.new(Actionable::Action) do
      def build
      end
      step :build
    end
    parent = Class.new(Actionable::Action) do
      def status
      end

      def handle
      end
      step child
      case_step :status do
        on 'a', :handle
      end
    end

    expect(parent.describe[:steps].map { |s| s[:type] }).to eq(%i[action case])
  end

  it 'reports declared failures with their message and metadata' do
    klass = Class.new(Actionable::Action) do
      fails :refused, 'the card was refused', kind: :rejected
      fails :not_found, kind: :not_found
    end

    expect(klass.describe[:failures]).to eq(
      refused: {message: 'the card was refused', metadata: {kind: :rejected}},
      not_found: {message: nil, metadata: {kind: :not_found}}
    )
  end

  it 'reports no failures for an action that declares none' do
    expect(described[:failures]).to eq({})
  end

  it 'reports declared skips with their message and metadata' do
    klass = Class.new(Actionable::Action) do
      skips :not_ready, 'the field is not created yet', retry: true
      skips :already_synced
    end

    expect(klass.describe[:skips]).to eq(
      not_ready: {message: 'the field is not created yet', metadata: {retry: true}},
      already_synced: {message: nil, metadata: {}}
    )
  end

  it 'reports no skips for an action that declares none' do
    expect(described[:skips]).to eq({})
  end
end

RSpec.describe 'Actionable::Action.describe_text' do
  subject(:text) { DescribeSample.describe_text }

  it 'returns a String headed by the action name and measure mode' do
    expect(text).to be_a(String)
    expect(text.lines.first).to include('DescribeSample').and include('measure: all')
  end

  it 'renders input and output fields in FieldStruct human-readable form' do
    expect(text).to include('amount (Integer, required)')
    expect(text).to include('invoice (String, required)')
  end

  it 'lists steps with their type' do
    expect(text).to include('validate (method)')
  end

  it 'lists only the hook sections that have hooks' do
    expect(text).to match(/on_success: notify/)
    expect(text).to match(/always: log/)
    expect(text).not_to include('on_failure')
  end

  it 'marks a free-form action input and output as free-form' do
    klass = Class.new(Actionable::Action) do
      def go
      end
      step :go
    end

    summary = klass.describe_text
    expect(summary).to include('Input: (free-form)')
    expect(summary).to include('Output: (free-form)')
  end

  it 'lists declared failures with their metadata and message' do
    klass = Class.new(Actionable::Action) do
      fails :refused, 'the card was refused', kind: :rejected
      fails :gone
    end

    expect(klass.describe_text).to include(
      "  Failures:\n    - refused (kind: :rejected): the card was refused\n    - gone"
    )
  end

  it 'omits the failures section when none are declared' do
    expect(text).not_to include('Failures:')
  end

  it 'lists declared skips with their metadata and message, after the failures' do
    klass = Class.new(Actionable::Action) do
      fails :refused
      skips :not_ready, 'the field is not created yet', retry: true
      skips :already_synced
    end

    expect(klass.describe_text).to include(
      "  Failures:\n    - refused\n  Skips:\n    - not_ready (retry: true): the field is not created yet\n    " \
      '- already_synced'
    )
  end

  it 'omits the skips section when none are declared' do
    expect(text).not_to include('Skips:')
  end
end
