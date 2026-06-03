# frozen_string_literal: true

module Actionable
  # The value object returned by {Action.run_each}: an ordered, +Enumerable+
  # collection of the per-item {Result}s, plus aggregate predicates over them
  # (decision D19). Each item ran independently — one {Result} per element, in
  # input order — so a failure in one never affects another.
  #
  #   batch = ImportRow.run_each(rows) { |row| {row: row} }
  #   batch.all_ok?            # => false
  #   batch.failures.size      # => 2
  #   batch.to_api_h           # => [{index: 0, status: :success, ...}, ...]
  class BatchResult
    include Enumerable

    # @return [Array<Result>] the per-item results, in input order
    attr_reader :results

    # @param results [Array<Result>]
    def initialize(results)
      @results = results.to_a
    end

    # @yieldparam result [Result]
    # @return [Enumerator, self]
    def each(&block)
      return to_enum(:each) unless block

      @results.each(&block)
      self
    end

    # @param index [Integer]
    # @return [Result, nil] the result at +index+
    def [](index)
      @results[index]
    end

    # @return [Integer] the number of results
    def size
      @results.size
    end
    alias length size

    # @return [Boolean] whether the batch ran no items
    def empty?
      @results.empty?
    end

    # @return [Boolean] whether every result is +ok?+ (success or skip);
    #   vacuously true for an empty batch
    def all_ok?
      @results.all?(&:ok?)
    end

    # @return [Boolean] whether any result is a failure
    def any_failure?
      @results.any?(&:failure?)
    end

    # @return [Boolean] whether the batch is mixed — at least one failure and at
    #   least one +ok?+ result
    def partial?
      any_failure? && @results.any?(&:ok?)
    end

    # @return [Array<Result>] the successful results
    def successes
      @results.select(&:success?)
    end

    # @return [Array<Result>] the failed results
    def failures
      @results.select(&:failure?)
    end

    # @return [Array<Result>] the skipped results
    def skips
      @results.select(&:skipped?)
    end

    # The batch as an array of API elements, each tagged with its position
    # (see {Result#to_api_h}). Ready to render as a JSON array of per-item
    # statuses.
    #
    # @param id_field [Symbol] the output field to surface as +:id+
    # @return [Array<Hash{Symbol=>Object}>]
    def to_api_h(id_field: :id)
      @results.each_with_index.map { |result, index| result.to_api_h(index: index, id_field: id_field) }
    end
  end
end
