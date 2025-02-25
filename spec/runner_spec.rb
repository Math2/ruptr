# frozen_string_literal: true

require 'tmpdir'
require 'stringio'
require_relative 'spec_helper'
require 'ruptr/runner'
require 'ruptr/report'

module Ruptr
  RSpec.describe Runner do
    shared_examples "a runner" do
      describe "output capture" do
        %i[passed failed skipped].each do |status|
          it "can capture test case #{status} output" do
            ts = TestSuite.new
            tc = TestCase.new do
              puts "test 1"
              $stderr.puts "test 2"
              warn "test 3"
              $stdout.puts "test 4"
              case status
              when :failed then raise StandardError
              when :skipped then raise SkippedException
              end
            end
            ts.add_test_case(tc)
            report = runner.run_report(ts)
            tr = report[tc]
            assert_equal status, tr.status
            assert_equal "test 1\ntest 4\n", tr.captured_stdout
            assert_equal "test 2\ntest 3\n", tr.captured_stderr
          end
        end
      end

      [false, true].each do |unmarshallable|
        it "can report test case exceptions#{unmarshallable ? ' (unmarshallable)' : ''}" do
          ts = TestSuite.new
          tc = TestCase.new do
            fail 'inner'
          ensure
            $!.instance_eval { @x = proc { } } if unmarshallable
            fail 'outer'
          end
          ts.add_test_case(tc)
          report = runner.run_report(ts)
          tr = report[tc]
          assert_predicate tr, :failed?
          ex = tr.exception
          refute_nil ex
          assert_equal 'outer', ex.message
          refute_nil ex.cause
          assert_equal 'inner', ex.cause.message
          assert_nil ex.cause.cause
        end
      end

      it "blocks nested tests when test group wrapper fails" do
        ts = TestSuite.new
        tg1 = TestGroup.new { fail }
        tg2 = TestGroup.new { |&wrap| wrap.call }
        tc1 = TestCase.new { }
        tc2 = TestCase.new { }
        tc3 = TestCase.new { }
        tc4 = TestCase.new { }
        ts.add_test_case(tc1)
        ts.add_test_subgroup(tg1)
        tg1.add_test_case(tc2)
        tg1.add_test_subgroup(tg2)
        tg2.add_test_case(tc3)
        ts.add_test_case(tc4)
        report = runner.run_report(ts)
        assert_predicate report, :failed?
        assert_predicate report[ts], :passed?
        assert_predicate report[tc1], :passed?
        assert_predicate report[tg1], :failed?
        assert_predicate report[tc2], :blocked?
        assert_predicate report[tg2], :blocked?
        assert_predicate report[tc3], :blocked?
        assert_predicate report[tc4], :passed?
        assert_equal 4, report.total_test_cases
        assert_equal 3, report.total_test_groups
        assert_equal 2, report.total_passed_test_cases
        assert_equal 0, report.total_failed_test_cases
        assert_equal 2, report.total_blocked_test_cases
        assert_equal 1, report.total_passed_test_groups
        assert_equal 1, report.total_failed_test_groups
        assert_equal 1, report.total_blocked_test_groups
      end

      it "skips nested tests when test group wrapper does not yield" do
        ts = TestSuite.new
        tg1 = TestGroup.new { } # does not yield
        tg2 = TestGroup.new { |&wrap| wrap.call }
        tc1 = TestCase.new { }
        tc2 = TestCase.new { }
        tc3 = TestCase.new { }
        tc4 = TestCase.new { }
        ts.add_test_case(tc1)
        ts.add_test_subgroup(tg1)
        tg1.add_test_case(tc2)
        tg1.add_test_subgroup(tg2)
        tg2.add_test_case(tc3)
        ts.add_test_case(tc4)
        report = runner.run_report(ts)
        assert_predicate report, :passed?
        assert_predicate report[ts], :passed?
        assert_predicate report[tc1], :passed?
        assert_predicate report[tg1], :passed?
        assert_predicate report[tc2], :skipped?
        assert_predicate report[tg2], :skipped?
        assert_predicate report[tc3], :skipped?
        assert_predicate report[tc4], :passed?
        assert_equal 4, report.total_test_cases
        assert_equal 3, report.total_test_groups
        assert_equal 2, report.total_passed_test_cases
        assert_equal 2, report.total_skipped_test_cases
        assert_equal 0, report.total_failed_test_cases
        assert_equal 2, report.total_passed_test_groups
        assert_equal 1, report.total_skipped_test_groups
        assert_equal 0, report.total_failed_test_groups
      end

      context "with a simple dummy test suite" do
        passing_test_cases_count = 90
        failing_test_cases_count = 7
        skipping_test_cases_count = 3
        test_cases_count = passing_test_cases_count + failing_test_cases_count + skipping_test_cases_count
        let(:test_suite) do
          ran_count = 0
          passing_test_case = TestCase.new do
            ran_count += 1
          end
          skipping_test_case = TestCase.new do
            ran_count += 1
            raise SkippedException
          end
          failing_test_case = TestCase.new do
            ran_count += 1
            fail 'failed dummy test case'
          end
          TestSuite.new.tap do |ts|
            ts.define_singleton_method(:dummy_ran_count) { ran_count }
            passing_test_cases_count.times { ts.add_test_case(passing_test_case.dup) }
            skipping_test_cases_count.times { ts.add_test_case(skipping_test_case.dup) }
            failing_test_cases_count.times { ts.add_test_case(failing_test_case.dup) }
          end
        end

        it "runs the test cases" do
          report = runner.run_report(test_suite)

          assert_equal failing_test_cases_count.zero?, report.passed?
          assert_equal !failing_test_cases_count.zero?, report.failed?

          assert_equal test_cases_count, report.total_test_cases
          assert_equal passing_test_cases_count, report.total_passed_test_cases
          assert_equal skipping_test_cases_count, report.total_skipped_test_cases
          assert_equal failing_test_cases_count, report.total_failed_test_cases

          assert_equal test_cases_count, test_suite.dummy_ran_count unless runner.is_a?(Runner::Forking)

          report.each_test_case_result do |_tc, tr|
            assert_equal 'failed dummy test case', tr.exception.message if tr.failed?
          end
        end
      end
    end

    [Runner, Runner::Threaded, Runner::Forking].each do |runner_class|
      describe runner_class do
        let(:runner) { described_class.new }

        it_behaves_like "a runner"
      end
    end
  end
end
