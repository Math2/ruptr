# frozen_string_literal: true

require 'ruptr/runner'
require 'ruptr/suite'
require 'ruptr/result'

module Ruptr
  module Tests
    # Helper mixin to build a test suite and check that all results are present and have the
    # expected status after running it.  Expects #runner to be defined.
    module TestSuiteTestingDSL
      def test_suite(&)
        fail if @test_group
        @test_suite ||= TestSuite.new.tap { |ts| expect_default_status(ts) }
        @test_group = @test_suite
        begin
          with_saved_default_expected_status(&) if block_given?
          @test_suite
        ensure
          @test_group = nil
        end
      end

      def test_group(*args, **opts, &)
        parent = @test_group or fail
        @test_group = TestGroup.new(*args, **opts).tap { |tg| expect_default_status(tg) }
        begin
          with_saved_default_expected_status(&) if block_given?
          parent.add_test_subgroup(@test_group)
          @test_group
        ensure
          @test_group = parent
        end
      end

      def group_wrap(&block)
        @test_group.block = block
      end

      def test_case(...)
        tc = TestCase.new(...)
        expect_default_status(tc)
        @test_group.add_test_case(tc)
        tc
      end

      def with_saved_default_expected_status
        saved = @default_expected_status
        yield
      ensure
        @default_expected_status = saved
      end

      def expected_statuses = @expected_statuses ||= {}

      def expect_status(status, te = nil)
        if te
          expected_statuses[te] = status
        else
          @default_expected_status = status
        end
      end

      def expect_default_status(te) = expect_status(@default_expected_status || :passed, te)

      TestResult::VALID_STATUSES.each do |status|
        define_method(:"expect_#{status}") { |*args| expect_status(status, *args) }
      end

      def report
        @report ||= runner.run_report(test_suite)
      end

      def check_report
        assert_equal expected_statuses.keys.count(&:test_case?), report.total_test_cases
        assert_equal expected_statuses.keys.count(&:test_group?), report.total_test_groups

        expected_statuses.each { |te, expected| assert_equal expected, report[te].status }

        TestResult::VALID_STATUSES.each do |status|
          assert_equal expected_statuses.count { |te, expected| te.test_case? && expected == status },
                       report.total_test_cases_by_status(status)
          assert_equal expected_statuses.count { |te, expected| te.test_group? && expected == status },
                       report.total_test_groups_by_status(status)
        end

        assert_equal expected_statuses.values.none?(:failed), report.passed?
        assert_equal expected_statuses.values.any?(:failed), report.failed?
      end
    end
  end
end
