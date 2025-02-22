# frozen_string_literal: true

require 'ruptr/runner'
require 'ruptr/report'

module Ruptr
  module Tests
    module ReportHelpers
      def runner = @runner ||= Runner.new(randomize: true)
      def report = @report ||= runner.run_report(suite)

      def reset = @runner = @report = nil

      def check_summary(passed: 0, skipped: 0, failed: 0, asserts: nil)
        assert_equal passed + skipped + failed, report.total_test_cases, "total test cases"
        assert_equal passed, report.total_passed_test_cases, "passed test cases"
        assert_equal skipped, report.total_skipped_test_cases, "skipped test cases"
        assert_equal failed, report.total_failed_test_cases, "failed test cases"
        assert_equal failed.zero?, report.passed?
        assert_equal !failed.zero?, report.failed?
        assert_equal asserts, report.total_assertions, "total assertions" if asserts
      rescue
        dump_report
        raise
      end

      def dump_report
        require 'ruptr/plain'
        report.emit(Formatter::Plain.new($stdout))
      end
    end

    module AutoRunHelpers
      def spawn_test_interpreter(extra_args, source)
        cmd = [RbConfig.ruby, *extra_args]
        out = IO.popen({ 'RUPTR_VERBOSE' => '-2' }, cmd, 'r+') do |io|
          io.write(source)
          io.close_write
          io.read
        end
        fail "subprocess exited with #{$?}" unless $?.success?
        @test_output = out
      end

      def dump_report = puts @test_output

      def check_summary(passed: 0, skipped: 0, failed: 0, asserts: nil)
        m = assert_match %r{\ARan (\d+)(?:/(\d+))? test cases(?: with (\d+) assertions)?: (\d+) passed(?:, (\d+) skipped)?(?:, (\d+) failed)?\.\Z},
                         @test_output
        actual_total_test_cases_ran = m[1].to_i
        actual_total_test_cases_in_suite = (m[2] || m[1]).to_i
        actual_total_asserts = m[3].to_i
        actual_total_passed = m[4].to_i
        actual_total_skipped = m[5].to_i
        actual_total_failed = m[6].to_i
        assert_equal passed + skipped + failed, actual_total_test_cases_ran, "total test cases ran"
        assert_equal passed + skipped + failed, actual_total_test_cases_in_suite, "total test cases in suite"
        assert_equal passed, actual_total_passed, "passed test cases"
        assert_equal skipped, actual_total_skipped, "skipped test cases"
        assert_equal failed, actual_total_failed, "failed test cases"
        assert_equal asserts, actual_total_asserts, "total assertions" if asserts
      rescue
        puts @test_output
        raise
      end
    end
  end
end
