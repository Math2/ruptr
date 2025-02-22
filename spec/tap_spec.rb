# frozen_string_literal: true

require 'stringio'
require_relative 'spec_helper'
require 'ruptr/tap'
require 'ruptr/result'

module Ruptr
  RSpec.describe Formatter::TAP do
    def format_tap(h, n: h.size)
      io = StringIO.new
      sink = described_class.new(io)
      sink.submit_plan({ planned_test_case_count: n }) do
        h.each_pair do |tc, tr|
          sink.begin_case(tc)
          sink.finish_case(tc, tr)
        end
      end
      io.string
    end

    it "can emit passed test" do
      assert_equal <<~TAP, format_tap({ TestCase.new("Test") => TestResult.new(:passed) })
        1..1
        ok 1 - Test
      TAP
    end

    it "can emit skipped test" do
      assert_equal <<~TAP, format_tap({ TestCase.new("Test") => TestResult.new(:skipped) })
        1..1
        ok 1 - Test # SKIP
      TAP
    end

    it "can emit pending test" do
      exception = PendingSkippedException.new('!')
      assert_equal <<~TAP, format_tap({ TestCase.new("Test") => TestResult.new(:skipped, exception:) })
        1..1
        not ok 1 - Test # TODO !
      TAP
    end

    it "can emit failed test" do
      assert_equal <<~TAP, format_tap({ TestCase.new("Test") => TestResult.new(:failed) })
        1..1
        not ok 1 - Test
      TAP
    end

    it "can emit multiple results" do
      h = {
        TestCase.new("Test 1") => TestResult.new(:passed),
        TestCase.new("Test 2") => TestResult.new(:skipped),
        TestCase.new("Test 3") => TestResult.new(:passed),
      }
      assert_equal <<~TAP, format_tap(h)
        1..3
        ok 1 - Test 1
        ok 2 - Test 2 # SKIP
        ok 3 - Test 3
      TAP
    end

    it "can emit multiple results with plan at the end" do
      h = {
        TestCase.new("Test 1") => TestResult.new(:passed),
        TestCase.new("Test 2") => TestResult.new(:skipped),
        TestCase.new("Test 3") => TestResult.new(:passed),
      }
      assert_equal <<~TAP, format_tap(h, n: nil)
        ok 1 - Test 1
        ok 2 - Test 2 # SKIP
        ok 3 - Test 3
        1..3
      TAP
    end
  end
end
