# frozen_string_literal: true

require_relative 'test_helpers'
require 'minitest/autorun'
require 'ruptr/testunit'
require 'ruptr/runner'

module Ruptr
  module Tests
    class TestUnitAdapterTestsBase < Minitest::Test
      def setup
        @suite = nil
        @testunit_compat = Compat::TestUnit.new
        @adapter = @testunit_compat.adapter_module
        @test_classes = []
        super
      end

      def adapter = @adapter

      def testunit(&)
        c = Class.new(adapter::TestCase, &)
        # Prevent the class from being GC'd.  The adapter finds the test classes using
        # Class#subclasses, which will not prevent anonymous classes from being GC'd and removed.
        @test_classes << c
        c
      end

      def suite
        @suite ||= @testunit_compat.adapted_test_suite
      end

      include ReportHelpers
    end

    class TestUnitAdapterTests < TestUnitAdapterTestsBase
      def test_basic
        testunit do
          def test_1 = assert true
          def test_2 = assert true
          def test_3 = assert_raise { fail }
          def test_4 = omit "skipped"
          def test_5 = assert false
          def test_6 = fail
        end
        check_summary(passed: 3, skipped: 1, failed: 2, asserts: 4)
      end
    end

    class TestUnitAutorunTestsBase < Minitest::Test
      include AutoRunHelpers

      def testunit(source, **opts)
        spawn_test_interpreter(['-I', 'lib', '-r', 'ruptr/testunit/override'], source, **opts)
      end
    end

    class TestUnitAutorunMiscTests < TestUnitAutorunTestsBase
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

    class TestUnitAutorunCoreAssertionsTests < TestUnitAutorunTestsBase
      def test_assert_valid_syntax
        testunit(<<~'RUBY')
          require 'test/unit/autorun'
          require 'core_assertions'
          class MyTest < Test::Unit::TestCase
            include Test::Unit::CoreAssertions
            def test_syntax_check
              assert_valid_syntax "1 + 2 + 3"
            end
          end
        RUBY
        check_summary(passed: 1)
      end

      if defined?(::Ractor)
        def test_assert_ractor
          testunit(<<~'RUBY')
            require 'test/unit/autorun'
            require 'core_assertions'
            class MyTest < Test::Unit::TestCase
              include Test::Unit::CoreAssertions
              def test_assert_ractor
                assert_ractor <<~END
                  assert true
                  assert !false
                  assert_equal 6, 1 + 2 + 3
                END
              end
            end
          RUBY
          check_summary(passed: 1)
        end
      end

      def test_assert_warning
        testunit(<<~'RUBY')
          require 'test/unit/autorun'
          require 'core_assertions'
          class MyTest < Test::Unit::TestCase
            include Test::Unit::CoreAssertions
            def test_assert_warning
              assert_warning("test warning\n") { warn "test warning" }
            end
          end
        RUBY
        check_summary(passed: 1, asserts: 1)
      end
    end
  end
end
