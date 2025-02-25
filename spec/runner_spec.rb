# frozen_string_literal: true

require 'tmpdir'
require 'stringio'
require_relative 'spec_helper'
require_relative 'runner_helpers'
require 'ruptr/runner'
require 'ruptr/report'
require 'tempfile'

module Ruptr
  RSpec.describe Runner do
    shared_examples "a runner" do
      include Tests::TestSuiteTestingDSL

      # This will check that all results have the expected status.
      after { check_report }

      it "can run empty test suite" do
        test_suite { }
      end

      it "can run test suite with a single passing test case" do
        test_suite { test_case { } }
      end

      it "can run test suite with a single skipping test case" do
        test_suite { expect_skipped test_case { raise SkippedException } }
      end

      it "can run test suite with a single failing test case" do
        test_suite { expect_failed test_case { fail } }
      end

      it "considers test case without a block to be skipped" do
        test_suite { expect_skipped test_case }
      end

      describe "context object" do
        it "can increase test case assertions count" do
          tc1 = tc2 = nil
          test_suite do
            tc1 = test_case { |ctx| ctx.assertions_count += 123 }
            tc2 = test_case { |ctx| ctx.assertions_count += 456 }
          end
          assert_equal 123, report[tc1].assertions
          assert_equal 456, report[tc2].assertions
        end

        it "can increase wrapping test group assertions count" do
          tg = tc = nil
          test_suite do
            tg = test_group do
              group_wrap do |ctx, &wrap|
                ctx.assertions_count += 120
                wrap.call
                ctx.assertions_count += 3
              end
              tc = test_case { |ctx| ctx.assertions_count += 456 }
            end
          end
          assert_equal 123, report[tg].assertions
          assert_equal 456, report[tc].assertions
        end
      end

      it "invokes the test case's block only once" do
        Tempfile.create do |io|
          test_suite { test_case { io.puts("ran") } }
          report # run test suite
          io.rewind
          assert_equal "ran\n", io.read
        end
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

      it "blocks nested tests when test group wrapper fails before yielding" do
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

      it "does not block nested tests when test group wrapper fails after yielding" do
        test_suite do
          expect_passed
          test_case { }
          expect_failed
          test_group do
            group_wrap { |&wrap| wrap.call; fail }
            expect_passed
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

      it "can run a test suite with deeply nested wrapping test groups" do
        depth = 100
        check1 = check2 = 0
        test_suite do
          rec = lambda do |n|
            if n.zero?
              test_case do
                assert_equal [depth, (depth * (depth + 1)) / 2], [check1, check2]
              end
            else
              test_group do
                group_wrap do |&wrap|
                  # NOTE: Group wrapper blocks always run in the same process.
                  check1 += 1
                  check2 += n
                  wrap.call
                  check2 -= n
                end
                rec.call(n - 1)
              end
            end
          end
          rec.call(depth)
        end
        report # run test suite before the below checks
        assert_equal [depth, 0], [check1, check2]
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
