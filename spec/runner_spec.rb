# frozen_string_literal: true

require 'tmpdir'
require 'stringio'
require_relative 'spec_helper'
require_relative 'runner_helpers'
require 'ruptr/runner'
require 'ruptr/report'

module Ruptr
  RSpec.describe Runner do
    shared_examples "a runner" do
      include Tests::TestSuiteTestingDSL

      # This will check that all results have the expected status.
      after { check_report }

      it "can run empty test suite" do
        test_suite { }
      end

      describe "output capture" do
        %i[passed failed skipped].each do |status|
          it "can capture #{status} test case output" do
            tc = nil
            test_suite do
              expect_status status
              tc = test_case do
                puts "test 1"
                $stderr.puts "test 2"
                warn "test 3"
                $stdout.puts "test 4"
                case status
                when :failed then raise StandardError
                when :skipped then raise SkippedException
                end
              end
            end
            tr = report[tc]
            assert_equal status, tr.status
            assert_equal "test 1\ntest 4\n", tr.captured_stdout
            assert_equal "test 2\ntest 3\n", tr.captured_stderr
          end
        end
      end

      [false, true].each do |unmarshallable|
        it "can report test case #{unmarshallable ? 'unmarshallable ' : ''}exceptions" do
          tc = nil
          test_suite do
            expect_failed
            tc = test_case do
              fail 'inner'
            ensure
              $!.instance_eval { @x = proc { } } if unmarshallable
              fail 'outer'
            end
          end
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
        test_suite do
          expect_passed
          test_case { }
          expect_failed
          test_group do
            group_wrap { fail }
            expect_blocked
            test_case { }
            test_group do
              group_wrap { |&wrap| wrap.call }
              test_case { }
            end
          end
          expect_passed
          test_case { }
        end
      end

      it "skips nested tests when test group wrapper does not yield" do
        test_suite do
          test_case { }
          test_group do
            group_wrap { } # does not call passed block
            expect_skipped
            test_case { }
            test_group do
              group_wrap { |&wrap| wrap.call }
              test_case { }
            end
          end
          test_case { }
        end
      end

      it "can run a test suite with a lot of test cases" do
        test_suite do
          900.times { expect_passed test_case { 123 } }
          30.times { expect_skipped test_case { raise SkippedException } }
          70.times { expect_failed test_case { fail 'failed dummy test case' } }
        end
        report.each_test_case_result do |_tc, tr|
          assert_equal 'failed dummy test case', tr.exception.message if tr.failed?
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
