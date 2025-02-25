# frozen_string_literal: true

require_relative 'test_helpers'
require 'minitest/autorun'
require 'ruptr/runner'

module Ruptr
  module Tests
    TEST_RUNNERS = [Runner, Runner::Threaded, Runner::Forking].freeze

    class RunnerBaseTests < Minitest::Test
      def runner_class = TEST_RUNNERS.first
      def runner = @runner ||= runner_class.new

      # Automatically create test subclasses to test other runners.
      def self.inherited(from_class)
        from_class.define_singleton_method(:inherited) { |_| }
        TEST_RUNNERS.drop(1).each do |runner_class|
          sub_class = Class.new(from_class) do
            define_method(:runner_class) { runner_class }
          end
          m = /\A(.+)::(.+?)Tests\z/.match(from_class.name) or fail
          m[1] == Tests.name or fail
          sub_name = :"#{m[2]}#{runner_class.name.sub(/\A.*::/, '')}Tests"
          Tests.const_set(sub_name, sub_class)
        end
      end
    end

    class RunnerMiscTests < RunnerBaseTests
      def test_ruptr_no_fork_overlap_tag
        Dir.mktmpdir("test.") do |tmpdir|
          check = lambda do |**h|
            h.each_pair { |i, v| assert_equal v, File.exist?("#{tmpdir}/#{i}") }
          end
          span = lambda do |i, &blk|
            File.write("#{tmpdir}/#{i}", '')
            blk.call
          ensure
            File.unlink("#{tmpdir}/#{i}")
          end
          ts = TestSuite.new
          ts.add_test_subgroup(
            TestGroup.new(tags: { ruptr_no_fork_overlap: true }) do |&blk|
              check.call(1 => false, 2 => false, 3 => false)
              span.call(1, &blk)
              check.call(1 => false, 2 => false, 3 => false)
            end.tap do |tg|
              [0, 0.1].each do |s|
                tg.add_test_case(
                  TestCase.new do
                    check.call(1 => true, 2 => false, 3 => false)
                    sleep(s)
                    check.call(1 => true, 2 => false, 3 => false)
                  end
                )
              end
            end
          )
          ts.add_test_subgroup(
            TestGroup.new do |&blk|
              check.call(1 => false, 2 => false, 3 => false)
              span.call(2, &blk)
              check.call(1 => false, 2 => false, 3 => false)
            end.tap do |tg|
              [0, 0.1].each do |s|
                tg.add_test_case(
                  TestCase.new do
                    check.call(1 => false)
                    sleep(s)
                    check.call(1 => false)
                  end
                )
              end
            end
          )
          ts.add_test_subgroup(
            TestGroup.new(tags: { ruptr_no_fork_overlap: true }) do |&blk|
              check.call(1 => false, 2 => false, 3 => false)
              span.call(3, &blk)
              check.call(1 => false, 2 => false, 3 => false)
            end.tap do |tg|
              [0, 0.1].each do |s|
                tg.add_test_case(
                  TestCase.new do
                    check.call(1 => false, 2 => false, 3 => true)
                    sleep(s)
                    check.call(1 => false, 2 => false, 3 => true)
                  end
                )
              end
            end
          )
          report = runner.run_report(ts)
          assert_predicate report, :passed?
          assert_equal 6, report.total_test_cases
          assert_equal 6, report.total_passed_test_cases
        end
      end
    end

    class RunnerGroupWrappingTests < RunnerBaseTests
      def setup
        @test_cases_count = @remaining_test_cases = 1000
        @test_groups_count = @remaining_test_groups = 500

        @total_states = 0
        @active_bitmap = 0
      end

      def check_active_bitmap(expected_bitmap)
        assert_equal expected_bitmap, @active_bitmap
      end

      def make_test_case(expected_bitmap)
        @remaining_test_cases -= 1
        ran = false
        TestCase.new do
          refute ran
          ran = true # ineffective with forking runners...
          check_active_bitmap(expected_bitmap)
        end
      end

      def make_test_group(expected_bitmap, state_index)
        @remaining_test_groups -= 1
        ran = false
        TestGroup.new do |&wrap|
          refute ran
          ran = true
          check_active_bitmap(expected_bitmap)
          begin
            @active_bitmap ^= 1 << state_index if state_index
            wrap.call
          ensure
            @active_bitmap ^= 1 << state_index if state_index
          end
          check_active_bitmap(expected_bitmap)
        end
      end

      def make_filled_test_group(expected_bitmap, root: false)
        unless rand(3).zero?
          state_index = @total_states
          @total_states += 1
        end
        tg = make_test_group(expected_bitmap, state_index)
        expected_bitmap |= 1 << state_index if state_index
        if @remaining_test_groups > 0
          [rand(@test_cases_count * 2 / @test_groups_count), @remaining_test_cases].min
        else
          @remaining_test_cases
        end.times do
          tg.add_test_case(make_test_case(expected_bitmap))
        end
        while @remaining_test_groups > 0 && (root || rand(2).zero?)
          tg.add_test_subgroup(make_filled_test_group(expected_bitmap))
        end
        tg
      end

      def make_test_suite
        tg = make_filled_test_group(0, root: true)
        assert_equal @test_cases_count, tg.count_test_cases
        assert_equal @test_groups_count, tg.count_test_groups
        assert @remaining_test_groups.zero? && @remaining_test_cases.zero?
        tg
      end

      def test_group_state_wrapping
        ts = make_test_suite
        report = runner.run_report(ts)
        assert_equal @test_cases_count, report.total_test_cases
        assert_equal @test_cases_count, report.total_passed_test_cases
        assert_equal 0, report.total_skipped_test_cases
        assert_equal 0, report.total_failed_test_cases
        assert_equal 0, report.total_blocked_test_cases
      end
    end
  end
end
