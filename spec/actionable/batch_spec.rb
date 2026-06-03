# frozen_string_literal: true

RSpec.describe 'Actionable::Action.run_each' do
  let(:klass) do
    Class.new(Actionable::Action) do
      input { required :n, :integer }
      output { required :doubled, :integer }
      step :go
      def go = @doubled = input.n * 2
    end
  end

  it 'runs the action per item and returns a BatchResult of per-item results' do
    batch = klass.run_each([1, 2, 3]) { |n| {n: n} }

    expect(batch).to be_a(Actionable::BatchResult)
    expect(batch.size).to eq(3)
    expect(batch.map { |r| r.output.doubled }).to eq([2, 4, 6])
  end

  it 'is Enumerable and indexable' do
    batch = klass.run_each([1, 2]) { |n| {n: n} }

    expect(batch[0]).to be_success
    expect(batch.to_a.size).to eq(2)
    expect(batch).not_to be_empty
  end

  it 'aggregates all_ok? / any_failure? / partial? on a mixed batch' do
    batch = klass.run_each([1, 'x', 3]) { |n| {n: n} } # 'x' -> :invalid_input

    expect(batch.all_ok?).to be(false)
    expect(batch.any_failure?).to be(true)
    expect(batch.partial?).to be(true)
    expect(batch.failures.size).to eq(1)
    expect(batch.successes.size).to eq(2)
  end

  it 'reports all_ok? (no failure) when every item is a success or skip' do
    batch = klass.run_each([1, 2]) { |n| {n: n} }

    expect(batch.all_ok?).to be(true)
    expect(batch.any_failure?).to be(false)
    expect(batch.partial?).to be(false)
  end

  it 'treats a skip as ok, not a failure' do
    skipper = Class.new(Actionable::Action) do
      step :go
      def go = skip!(:nothing_to_do)
    end

    batch = skipper.run_each([1, 2])

    expect(batch.all_ok?).to be(true)
    expect(batch.any_failure?).to be(false)
  end

  it 'passes each item directly to .run when no block is given' do
    free = Class.new(Actionable::Action) do
      step :go
      def go = succeed('ok')
    end

    batch = free.run_each([1, 2, 3])

    expect(batch.size).to eq(3)
    expect(batch).to be_all_ok
  end

  it 'maps the batch to API elements with positional indexes' do
    batch = klass.run_each([1, 2]) { |n| {n: n} }

    expect(batch.to_api_h).to eq(
      [
        {index: 0, status: :success, id: nil, errors: {}},
        {index: 1, status: :success, id: nil, errors: {}}
      ]
    )
  end

  it 'returns an empty, vacuously-ok BatchResult for an empty enumerable' do
    batch = klass.run_each([])

    expect(batch).to be_empty
    expect(batch.all_ok?).to be(true)
    expect(batch.any_failure?).to be(false)
  end
end
