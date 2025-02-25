# frozen_string_literal: true

require_relative 'test_helpers'
require 'minitest/autorun'
require 'ruptr/minitest'
require 'ruptr/runner'

module Ruptr
  module Tests
    class TestUnitAutorunTests < Minitest::Test
      include AutoRunHelpers

      def testunit(source, **opts)
        spawn_test_interpreter(['-I', 'lib', '-r', 'ruptr/testunit/override'], source, **opts)
      end

      def test_1
        testunit(<<~'RUBY')
          require 'test/unit/autorun'
          class MyTest < Test::Unit::TestCase
            def test_1 = assert true
            def test_2 = assert false
            def test_3 = assert true
            def test_4 = omit
            def test_5 = assert true
            def test_6 = assert false
          end
        RUBY
        check_summary(passed: 3, skipped: 1, failed: 2, asserts: 5)
      end
    end
  end
end
