# frozen_string_literal: true

require_relative 'suite'
require_relative 'result'
require_relative 'sink'

module Ruptr
  class Report
    def initialize
      @results = {}
      @failed = false
      @total_assertions = 0
      @total_test_cases = 0
      @total_test_cases_by_status = Hash.new(0)
      @total_test_groups = 0
      @total_test_groups_by_status = Hash.new(0)
    end

    attr_reader :total_assertions,
                :total_test_cases,
                :total_test_groups

    def failed? = @failed
    def passed? = !failed?

    def total_test_cases_by_status(status) = @total_test_cases_by_status[status]
    def total_test_groups_by_status(status) = @total_test_groups_by_status[status]

    TestResult::VALID_STATUSES.each do |status|
      define_method(:"total_#{status}_test_cases") { total_test_cases_by_status(status) }
      define_method(:"total_#{status}_test_groups") { total_test_groups_by_status(status) }
    end

    def each_test_element_result(klass = TestElement, &)
      return to_enum __method__, klass unless block_given?
      @results.each { |te, tr| yield te, tr if te.is_a?(klass) }
    end

    def each_test_case_result(&) = each_test_element_result(TestCase, &)
    def each_test_group_result(&) = each_test_element_result(TestGroup, &)

    def [](k) = @results[k]

    def []=(k, v)
      raise ArgumentError unless k.is_a?(Symbol)
      @results[k] = v
    end

    def bump(k, n = 1)
      raise ArgumentError unless k.is_a?(Symbol)
      @results[k] = (v = @results[k]).nil? ? n : v + n
    end

    def record_result(te, tr)
      raise ArgumentError, "result already recorded" if @results[te]
      case
      when te.test_case?
        @total_test_cases += 1
        @total_test_cases_by_status[tr.status] += 1
      when te.test_group?
        @total_test_groups += 1
        @total_test_groups_by_status[tr.status] += 1
      else
        raise ArgumentError
      end
      @total_assertions += tr.assertions || 0
      @failed ||= tr.failed?
      @results[te] = tr
    end

    def freeze
      @results.freeze
      @total_test_cases_by_status.freeze
      @total_test_groups_by_status.freeze
      super
    end

    def emit(sink)
      sink.begin_plan({ planned_test_case_count: @total_test_cases })
      each_test_group_result { |tg, tr| sink.submit_group(tg, tr) }
      each_test_case_result { |tc, tr| sink.submit_case(tc, tr) }
      sink.finish_plan(@results.filter { |k, _v| k.is_a?(Symbol) })
    end

    class Builder
      include Sink

      def initialize(report = Report.new)
        @report = report
      end

      attr_accessor :report

      def begin_plan(fields)
        fields.each { |k, v| report[k] = v }
      end

      def finish_plan(fields)
        fields.each { |k, v| report[k] = v }
      end

      def finish_element(te, tr)
        report.record_result(te, tr)
      end
    end
  end
end
