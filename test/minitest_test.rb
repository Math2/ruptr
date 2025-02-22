# frozen_string_literal: true

require_relative 'test_helpers'
require 'minitest/autorun'
require 'ruptr/minitest'
require 'ruptr/runner'

module Ruptr
  module Tests
    class MinitestAdapterTestsBase < Minitest::Test
      def setup
        reset
      end

      def reset
        @suite = nil
        @minitest_compat = Compat::Minitest.new
        @adapter = @minitest_compat.adapter_module
        @test_classes = []
        super
      end

      def adapter = @adapter

      def minitest(&)
        c = Class.new(adapter::Test, &)
        # Prevent the class from being GC'd.  The adapter finds the test classes using
        # Class#subclasses, which will not prevent anonymous classes from being GC'd and removed.
        @test_classes << c
        c
      end

      def suite
        @suite ||= @minitest_compat.adapted_test_suite
      end

      include ReportHelpers
    end

    class MinitestAdapterTests < MinitestAdapterTestsBase
      def test_count_test_cases
        minitest do
          def test_1 = nil
          def test_2 = nil
          private def test_3 = nil
          def helper = nil
        end
        assert_equal 2, suite.count_test_cases
      end

      def test_call_test_methods
        called = {}
        minitest do
          %i[setup teardown test_1 test_2 test_3].each do |name|
            define_method(name) do
              h = called[name] ||= {}.tap(&:compare_by_identity)
              fail "#{name} called multiple times on the same instance!" if h[self]
              h[self] = true
            end
          end
        end
        assert_equal 3, suite.count_test_cases
        check_summary(passed: 3)
        assert_equal 3, called[:setup]&.size
        assert_equal 3, called[:teardown]&.size
        assert_equal called[:setup], called[:teardown]
        %i[test_1 test_2 test_3].each do |name|
          assert_equal 1, called[name]&.size
          assert_includes called[:setup], called[name].keys.first
          assert_includes called[:teardown], called[name].keys.first
        end
      end

      def test_count_assertions
        minitest do
          def test_1 = 1.times { pass }
          def test_2 = 3.times { pass }
          def test_3 = 5.times { pass }
        end
        check_summary(passed: 3, asserts: 9)
      end

      def test_count_assertions_in_setup_and_teardown
        minitest do
          def test_1 = pass
          def test_2 = pass
          def test_3 = pass
          def setup = pass
          def teardown = pass
        end
        check_summary(passed: 3, asserts: 9)
      end

      def test_fail
        minitest do
          def test_1 = 1.times { pass }
          def test_2 = 3.times { flunk }
          def test_3 = 5.times { pass }
        end
        check_summary(passed: 2, failed: 1, asserts: 7)
      end

      def test_skip
        minitest do
          def test_1 = 1.times { pass }
          def test_2 = 3.times { skip }
          def test_3 = 5.times { pass }
        end
        check_summary(passed: 2, skipped: 1, asserts: 6)
      end

      def test_inherit
        c1 = minitest do
          def test_1 = nil
          def test_2 = nil
          def test_3 = nil
          def helper = nil
        end
        c2 = Class.new(c1) do
          def test_3 = nil
          def test_4 = nil
        end
        c3 = Class.new(c2) do
          def test_1 = nil
          def test_4 = nil
        end
        c4 = Class.new(c1) do
          private def test_3 = nil
          def test_4 = nil
          def test_5 = nil
        end
        c5 = Class.new(c4) do
          def test_3 = nil
        end
        n = [c1, c2, c3, c4, c5].sum { |c| c.public_instance_methods.count { |s| s.start_with?('test_') } }
        check_summary(passed: n)
      end

      def test_fail_with_non_standarderror_exception
        minitest do
          def test_fail = raise Exception
        end
        check_summary(failed: 1)
      end

      def test_call_order
        ran = []
        minitest do
          define_method(:setup) { ran << :setup }
          define_method(:test_1) { ran << :test_1 }
          define_method(:teardown) { ran << :teardown }
        end
        check_summary(passed: 1)
        assert_equal %i[setup test_1 teardown], ran
      end

      def test_call_order_with_setup_error
        ran = []
        minitest do
          define_method(:setup) { ran << :setup; flunk }
          define_method(:test_1) { ran << :test_1 }
          define_method(:teardown) { ran << :teardown }
        end
        check_summary(failed: 1, asserts: 1)
        assert_equal %i[setup teardown], ran
      end

      def test_call_order_with_test_error
        ran = []
        minitest do
          define_method(:setup) { ran << :setup }
          define_method(:test_1) { ran << :test_1; flunk }
          define_method(:teardown) { ran << :teardown }
        end
        check_summary(failed: 1, asserts: 1)
        assert_equal %i[setup test_1 teardown], ran
      end

      def test_call_order_with_teardown_error
        ran = []
        minitest do
          define_method(:setup) { ran << :setup }
          define_method(:test_1) { ran << :test_1 }
          define_method(:teardown) { ran << :teardown; flunk }
        end
        check_summary(failed: 1, asserts: 1)
        assert_equal %i[setup test_1 teardown], ran
      end
    end

    class MinitestAdapterTestsProveIt < MinitestAdapterTestsBase
      def test_prove_it_pass
        minitest do
          prove_it!
          def test_1 = pass
        end
        check_summary(passed: 1)
      end

      def test_prove_it_fail
        minitest do
          prove_it!
          def test_1 = true
        end
        check_summary(failed: 1)
      end
    end

    class MinitestAdapterTestsAround < MinitestAdapterTestsBase
      def minitest(&)
        a = adapter
        super do
          include a::Hooks
          module_eval(&)
        end
      end

      def test_without_around
        minitest do
          def test_1 = nil
        end
        check_summary(passed: 1)
      end

      def test_around_simple
        ran = []
        minitest do
          define_method(:around) do |&wrap|
            ran << :around_pre
            wrap.call
            ran << :around_post
          end
          define_method(:test_1) { ran << :test_1 }
        end
        check_summary(passed: 1)
        assert_equal %i[around_pre test_1 around_post], ran
      end

      def test_around_setup_teardown
        ran = []
        minitest do
          define_method(:around) do |&wrap|
            ran << :around_pre
            wrap.call
            ran << :around_post
          end
          define_method(:setup) { ran << :setup }
          define_method(:test_1) { ran << :test_1 }
          define_method(:teardown) { ran << :teardown }
        end
        check_summary(passed: 1)
        assert_equal %i[around_pre setup test_1 teardown around_post], ran
      end

      def test_around_inherit
        ran = []
        c1 = minitest do
          define_method(:around) do |&wrap|
            ran << :around1_pre
            super(&wrap)
            ran << :around1_post
          end
        end
        c2 = Class.new(c1)
        c3 = Class.new(c2) do
          define_method(:around) do |&wrap|
            super() do
              ran << :around3_pre
              wrap.call
              ran << :around3_post
            end
          end
        end
        c4 = Class.new(c3) do
          define_method(:around) do |&wrap|
            ran << :around4_pre
            super(&wrap)
            ran << :around4_post
          end
          define_method(:setup) { ran << :setup }
          define_method(:teardown) { ran << :teardown }
          define_method(:test_1) { ran << :test_1 }
        end
        check_summary(passed: 1)
        assert_equal %i[around4_pre around1_pre around3_pre
                        setup test_1 teardown
                        around3_post around1_post around4_post],
                     ran
      end

      def test_around_skip
        minitest do
          def around = nil
          def test_1 = fail
        end
        check_summary(skipped: 1)
      end
    end

    class MinitestAdapterTestsGoldenStore < MinitestAdapterTestsBase
      require 'ruptr/golden_master'

      def golden_store = @golden_store ||= GoldenMaster::Store.new
      def runner = @runner ||= Runner.new(golden_store:)

      def test_assert_golden_pass
        minitest do
          def test_1 = assert_golden 123
          def test_2 = assert_golden 'abc'
        end
        check_summary(passed: 2, asserts: 0)
        golden_store.accept_trial
        reset
        minitest do
          def test_1 = assert_golden 123
          def test_2 = assert_golden 'abc'
        end
        check_summary(passed: 2, asserts: 2)
      end

      def test_assert_golden_fail
        minitest do
          def test_1 = assert_golden 123
          def test_2 = assert_golden 'abc'
        end
        check_summary(passed: 2, asserts: 0)
        golden_store.accept_trial
        reset
        minitest do
          def test_1 = assert_golden 'abc'
          def test_2 = assert_golden 123
        end
        check_summary(failed: 2, asserts: 2)
      end
    end

    class MinitestAdapterTestsRSpecAssertions < MinitestAdapterTestsBase
      require 'ruptr/adapters/rspec_expect'
      require 'ruptr/adapters/rspec_mocks'

      def test_rspec_expect
        minitest do
          include Ruptr::Adapters::RSpecExpect
          def test_pass = expect(123).to(eq(123))
          def test_fail = expect(456).to(eq(789))
        end
        check_summary(passed: 1, failed: 1, asserts: 2)
      end

      def test_rspec_mocks
        minitest do
          include Ruptr::Adapters::RSpecMocks
          def test_pass = begin o = double; expect(o).to(receive(:test)); o.test; end
          def test_fail = begin o = double; expect(o).to(receive(:test)); end
        end
        check_summary(passed: 1, failed: 1, asserts: 2)
      end
    end

    class MinitestAdapterTestsRRMocks < MinitestAdapterTestsBase
      require 'ruptr/adapters/rr'

      def minitest(&)
        super do
          include Ruptr::Adapters::RR
          include RR::DSL
          module_eval(&)
        end
      end

      def test_stub_pass
        minitest do
          def test_1 = assert_equal 123, Object.new.tap { |o| stub(o).foo { 123 } }.foo
        end
        check_summary(passed: 1, asserts: 1)
      end

      def test_stub_fail
        minitest do
          def test_1 = assert_equal 123, Object.new.tap { |o| stub(o).foo { 456 } }.foo
        end
        check_summary(failed: 1, asserts: 1)
      end

      def test_mock_pass
        minitest do
          def test_1 = Object.new.tap { |o| mock(o).foo }.foo
          def test_2 = Object.new.tap { |o| mock(o).foo(123) }.foo(123)
          def test_3 = assert_equal 123, Object.new.tap { |o| mock(o).foo { 123 } }.foo
        end
        check_summary(passed: 3)
      end

      def test_mock_fail
        minitest do
          def test_1 = Object.new.tap { |o| mock(o).foo }
          def test_2 = Object.new.tap { |o| mock(o).foo(123) }.foo(456)
          def test_3 = assert_equal 123, Object.new.tap { |o| mock(o).foo { 456 } }.foo
        end
        check_summary(failed: 3)
      end
    end

    class MinitestAutorunTests < Minitest::Test
      include AutoRunHelpers

      def minitest(source, **opts)
        spawn_test_interpreter(['-I', 'lib', '-r', 'ruptr/minitest/override'], source, **opts)
      end

      def test_1
        minitest(<<~RUBY)
          require 'minitest/autorun'
          class Test < Minitest::Test
            def test_1 = pass
            def test_2 = flunk
            def test_3 = pass
            def test_4 = skip
            def test_5 = pass
            def test_6 = flunk
          end
        RUBY
        check_summary(passed: 3, skipped: 1, failed: 2, asserts: 5)
      end
    end
  end
end
