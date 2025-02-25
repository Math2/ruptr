# frozen_string_literal: true

require_relative 'test_helpers'
require 'minitest/autorun'
require 'ruptr/rspec'
require 'ruptr/runner'
require 'ruptr/golden_master'

# NOTE: New RSpec tests are added to spec/rspec_spec.rb instead!!!

module Ruptr
  module Tests
    class RSpecAdapterTestsBase < Minitest::Test
      def setup
        reset
      end

      def reset
        @suite = nil
        @rspec_compat = Compat::RSpec.new
        @adapter = @rspec_compat.adapter_module
        configure do |config|
          config.expect_with(:minitest)
        end
        super
      end

      def adapter = @adapter
      def configure(&) = @adapter.configure(&)
      def rspec(&) = block_given? ? @adapter.module_eval(&) : @adapter

      def suite
        @suite ||= @rspec_compat.adapted_test_suite
      end

      include ReportHelpers
    end

    class RSpecAdapterTests < RSpecAdapterTestsBase
      def test_simple
        rspec.describe "something" do
          it("can pass") { assert true }
          it("can skip") { skip }
          it("can fail") { assert false }
        end
        check_summary(passed: 1, failed: 1, skipped: 1)
      end

      def test_unnamed_example
        ran = 0
        rspec.example_group do
          example { ran += 1; assert true }
        end
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_subgroup
        ran = 0
        rspec.describe "example group" do
          describe "example subgroup" do
            it("can run example") { ran += 1 }
          end
        end
        assert_equal "[RSpec] example group example subgroup can run example",
                     suite.each_test_case_recursive.first.description
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_let
        ran = 0
        rspec.example_group do
          let(:test) { ran += 1; 123 }
          it("can read the variable") { assert_equal 123, test }
          it("can read the variable twice") { assert_equal 123, test; assert_equal 123, test }
          describe "with a subgroup" do
            it("can also read the variable") { assert_equal 123, test }
          end
        end
        check_summary(passed: 3)
        assert_equal 3, ran
      end

      def test_let_invalid_iv_names
        rspec.example_group do
          let(:test?) { 123 }
          let(:test!) { 456 }
          it("test?") { assert_equal 123, test? }
          it("test!") { assert_equal 456, test! }
        end
        check_summary(passed: 2)
      end

      def test_let_nil
        ran = 0
        rspec.example_group do
          let(:test) { ran += 1; nil }
          it("can read the variable twice") { 2.times { assert_nil test } }
        end
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_let_bang
        ran = []
        rspec.example_group do
          let!(:test) { ran << :let; 123 }
          example("example") { ran << :enter_example; 2.times { assert_equal 123, test }; ran << :leave_example }
        end
        check_summary(passed: 1)
        assert_equal %i[let enter_example leave_example], ran
      end

      def test_explicit_subject
        rspec.describe "test" do
          subject { 123 }
          example { assert_equal 123, subject }
          describe do
            example { assert_equal 123, subject }
          end
          describe "something" do
            example { assert_equal 123, subject }
          end
          describe Array do
            example { assert_kind_of Array, subject }
          end
        end
        check_summary(passed: 4)
      end

      def test_named_subject
        rspec.describe "test" do
          subject(:test) { 123 }
          example { assert_equal 123, test }
          example { assert_equal 123, subject }
          describe do
            example { assert_equal 123, test }
            example { assert_equal 123, subject }
          end
          describe "something" do
            example { assert_equal 123, test }
            example { assert_equal 123, subject }
          end
          describe Array do
            example { assert_equal 123, test }
            example { assert_kind_of Array, subject }
          end
        end
        check_summary(passed: 8)
      end

      def test_before
        ran = 0
        rspec.example_group do
          before { ran += 1; @test = 123 }
          it("can read the variable") { assert_equal 123, @test }
          it("can read the variable again") { assert_equal 123, @test }
          describe "with a subgroup" do
            it("can also read the variable") { assert_equal 123, @test }
          end
        end
        check_summary(passed: 3)
        assert_equal 3, ran
      end

      def test_prepend_before
        ran = []
        rspec.example_group do
          before { ran << :before1 }
          before { ran << :before2 }
          prepend_before { ran << :before3 }
          before { ran << :before4 }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[before3 before1 before2 before4 example], ran
      end

      def test_after
        ran = 0
        rspec.example_group do
          after { ran += 1; @test = 123 }
          it("cannot read the variable") { assert_nil @test }
          describe "with a subgroup" do
            it("still cannot read the variable") { assert_nil @test }
          end
        end
        check_summary(passed: 2)
        assert_equal 2, ran
      end

      def test_append_after
        ran = []
        rspec.example_group do
          after { ran << :after1 }
          after { ran << :after2 }
          append_after { ran << :after3 }
          after { ran << :after4 }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[example after4 after2 after1 after3], ran
      end

      def test_before_after_sibling
        ran1 = ran2 = ran3 = ran4 = 0
        rspec.example_group do
          before { ran1 += 1; @test1 = 123 }
          before { ran2 += 1; @test2 = 456 }
          after { ran3 += 1 }
          after { ran4 += 1 }
          example { assert_equal [123, 456], [@test1, @test2] }
        end
        check_summary(passed: 1)
        assert_equal [1, 1, 1, 1], [ran1, ran2, ran3, ran4]
      end

      def test_before_after_nested
        ran1 = ran2 = ran3 = ran4 = 0
        rspec.example_group do
          before { ran1 += 1; @test1 = 123 }
          after { ran2 += 1 }
          describe "with a subgroup" do
            before { ran3 += 1; @test2 = 456 }
            after { ran4 += 1 }
            it("does something nested") { assert_equal [123, 456], [@test1, @test2] }
          end
          it("does something") { assert_equal [123, nil], [@test1, @test2] }
        end
        check_summary(passed: 2)
        assert_equal [2, 2, 1, 1], [ran1, ran2, ran3, ran4]
      end

      def test_before_after_ordering
        ran = []
        rspec.example_group do
          before { ran << :outer_before_1 }
          before { ran << :outer_before_2 }
          after { ran << :outer_after_1 }
          after { ran << :outer_after_2 }
          describe "with a subgroup" do
            before { ran << :inner_before_1 }
            before { ran << :inner_before_2 }
            after { ran << :inner_after_1 }
            after { ran << :inner_after_2 }
            it("does something nested") { ran << :nested_example }
          end
        end
        check_summary(passed: 1)
        assert_equal %i[outer_before_1 outer_before_2 inner_before_1 inner_before_2
                        nested_example
                        inner_after_2 inner_after_1 outer_after_2 outer_after_1],
                     ran
      end

      def test_before_after_ordering_exception
        ran = []
        rspec.example_group do
          before { ran << :outer_before }
          after { ran << :outer_after }
          example_group do
            before { ran << :inner_before_1 }
            before { ran << :inner_before_2; fail }
            before { ran << :inner_before_3 }
            after { ran << :inner_after_1 }
            after { ran << :inner_after_2 }
            after { ran << :inner_after_3 }
            example { ran << :example }
          end
        end
        check_summary(failed: 1)
        assert_equal %i[outer_before inner_before_1 inner_before_2
                        inner_after_3 inner_after_2 inner_after_1 outer_after],
                     ran
      end

      def test_around_layer_single
        ran = []
        rspec.example_group do
          around_layer { |ex| ran << :wrap_pre; ex.run; ran << :wrap_post }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[wrap_pre example wrap_post], ran
      end

      def test_around_layer_to_proc_yield
        ran = []
        rspec.example_group do
          def call_it = yield
          around_layer { |ex| ran << :wrap_pre; call_it(&ex); ran << :wrap_post }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[wrap_pre example wrap_post], ran
      end

      def test_around_layer_multi
        ran = []
        rspec.example_group do
          around_layer { |ex| ran << :wrap1_pre; ex.run; ran << :wrap1_post }
          around_layer { |ex| ran << :wrap2_pre; ex.run; ran << :wrap2_post }
          around_layer { |ex| ran << :wrap3_pre; ex.run; ran << :wrap3_post }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[wrap1_pre wrap2_pre wrap3_pre example wrap3_post wrap2_post wrap1_post], ran
      end

      def test_around_layer_with_before_and_after
        ran = []
        rspec.example_group do
          around_layer { |ex| ran << :wrap1_pre; ex.run; ran << :wrap1_post }
          around_layer { |ex| ran << :wrap2_pre; ex.run; ran << :wrap2_post }
          around_layer { |ex| ran << :wrap3_pre; ex.run; ran << :wrap3_post }
          before { ran << :before }
          example { ran << :example }
          after { ran << :after }
        end
        check_summary(passed: 1)
        assert_equal %i[wrap1_pre wrap2_pre wrap3_pre before example after wrap3_post wrap2_post wrap1_post], ran
      end

      def test_around_layer_nested_with_before_and_after
        ran = []
        rspec.example_group do
          around_layer { |ex| ran << :wrap1_pre; ex.run; ran << :wrap1_post }
          around_layer { |ex| ran << :wrap2_pre; ex.run; ran << :wrap2_post }
          before { ran << :before1 }
          example_group do
            before { ran << :before2 }
            around_layer { |ex| ran << :wrap3_pre; ex.run; ran << :wrap3_post }
            around_layer { |ex| ran << :wrap4_pre; ex.run; ran << :wrap4_post }
            example { ran << :example }
            after { ran << :after2 }
          end
          after { ran << :after1 }
        end
        check_summary(passed: 1)
        assert_equal %i[wrap1_pre wrap2_pre before1 wrap3_pre wrap4_pre before2
                        example
                        after2 wrap4_post wrap3_post after1 wrap2_post wrap1_post],
                     ran
      end

      def test_around_single
        ran = []
        rspec.example_group do
          around { |ex| ran << :around_pre; ex.run; ran << :around_post }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[around_pre example around_post], ran
      end

      def test_around_multi
        ran = []
        rspec.example_group do
          around { |ex| ran << :around1_pre; ex.run; ran << :around1_post }
          around { |ex| ran << :around2_pre; ex.run; ran << :around2_post }
          around { |ex| ran << :around3_pre; ex.run; ran << :around3_post }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[around1_pre around2_pre around3_pre
                        example
                        around3_post around2_post around1_post], ran
      end

      def test_around_and_around_layer
        ran = []
        rspec.example_group do
          around { |ex| ran << :around1_pre; ex.run; ran << :around1_post }
          around_layer { |ex| ran << :around_layer_pre; ex.run; ran << :around_layer_post }
          around { |ex| ran << :around2_pre; ex.run; ran << :around2_post }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[around1_pre around2_pre around_layer_pre
                        example
                        around_layer_post around2_post around1_post], ran
      end

      def test_around_nested_with_before_and_after
        ran = []
        rspec.example_group do
          around { |ex| ran << :around1_pre; ex.run; ran << :around1_post }
          around { |ex| ran << :around2_pre; ex.run; ran << :around2_post }
          before { ran << :before1 }
          example_group do
            before { ran << :before2 }
            around { |ex| ran << :around3_pre; ex.run; ran << :around3_post }
            around { |ex| ran << :around4_pre; ex.run; ran << :around4_post }
            example_group do
              before { ran << :before3 }
              example_group do
                example_group do
                  around { |ex| ran << :around5_pre; ex.run; ran << :around5_post }
                  example { ran << :example }
                end
                after { ran << :after3 }
              end
            end
            after { ran << :after2 }
          end
          after { ran << :after1 }
        end
        check_summary(passed: 1)
        assert_equal %i[around1_pre around2_pre around3_pre around4_pre around5_pre
                        before1 before2 before3
                        example
                        after3 after2 after1
                        around5_post around4_post around3_post around2_post around1_post],
                     ran
      end

      def test_context_before_run_once
        ran = 0
        rspec.example_group do
          before(:context) { ran += 1 }
          example { }
          example { }
        end
        check_summary(passed: 2)
        assert_equal 1, ran
      end

      def test_context_after_run_once
        ran = 0
        rspec.example_group do
          after(:context) { ran += 1 }
          example { }
          example { }
        end
        check_summary(passed: 2)
        assert_equal 1, ran
      end

      def test_context_around_run_once
        ran = 0
        rspec.example_group do
          around_layer(:context) { |h| ran += 1; h.run }
          example { }
          example { }
        end
        check_summary(passed: 2)
        assert_equal 1, ran
      end

      def test_context_before_after
        ran = []
        rspec.example_group do
          before(:context) { ran << :before }
          after(:context) { ran << :after }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[before example after], ran
      end

      def test_context_before_after_nested
        ran = []
        rspec.example_group do
          before(:context) { ran << :context1_before }
          after(:context) { ran << :context1_after }
          example { ran << :example1 }
          example_group do
            before(:context) { ran << :context2_before }
            after(:context) { ran << :context2_after }
            example_group do
              example { ran << :example2 }
              example_group do
                before(:context) { ran << :context4_before }
                after(:context) { ran << :context4_after }
                example { ran << :example3 }
              end
            end
            before(:context) { ran << :context3_before }
            after(:context) { ran << :context3_after }
          end
        end
        check_summary(passed: 3)
        assert_equal %i[context1_before
                        example1
                        context2_before
                        context3_before
                        example2
                        context4_before
                        example3
                        context4_after
                        context3_after
                        context2_after
                        context1_after],
                     ran
      end

      def test_context_around_nested
        ran = []
        rspec.example_group do
          around_layer(:context) { |h| ran << :context1_pre; h.run; ran << :context1_post }
          around_layer(:context) { |h| ran << :context2_pre; h.run; ran << :context2_post }
          example_group do
            around_layer(:context) { |h| ran << :context3_pre; h.run; ran << :context3_post }
            example { ran << :example }
          end
        end
        check_summary(passed: 1)
        assert_equal %i[context1_pre context2_pre context3_pre
                        example
                        context3_post context2_post context1_post],
                     ran
      end

      def test_context_before_after_ivars_carryover
        rspec.example_group do
          before(:context) { assert_nil @test; @test = 123 }
          after(:context) { assert_equal 123, @test }
          example { assert_equal 123, @test }
        end
        check_summary(passed: 1)
      end

      def test_context_before_after_nested_ivars_carryover
        rspec.example_group do
          before(:context) { assert_nil @test1; @test1 = 123 }
          after(:context) { assert_equal 123, @test1 }
          example { assert_equal 123, @test1; assert_nil @test2 }
          example_group do
            example { assert_equal 123, @test1; assert_nil @test2 }
            example_group do
              before(:context) { assert_equal 123, @test1; assert_nil @test2; @test2 = 456 }
              after(:context) { assert_equal [123, 456], [@test1, @test2] }
              example { assert_equal [123, 456], [@test1, @test2] }
            end
          end
        end
        check_summary(passed: 3)
      end

      def test_def_helper
        rspec.example_group do
          def helper_1 = 123
          before { assert_equal 123, helper_1 }
          after { assert_equal 123, helper_1 }
          around_layer { |h| assert_equal 123, helper_1; h.run }
          example_group do
            def helper_2 = 456
            before { assert_equal 123, helper_1 }
            before { assert_equal 456, helper_2 }
            after { assert_equal 123, helper_1 }
            after { assert_equal 456, helper_2 }
            around_layer { |h| assert_equal 123, helper_1; h.run }
            around_layer { |h| assert_equal 456, helper_2; h.run }
            example { assert_equal 123, helper_1; assert_equal 456, helper_2 }
          end
        end
        check_summary(passed: 1, asserts: 11)
      end

      def test_shared_examples_1
        ran = 0
        rspec.example_group do
          shared_examples "test" do
            it("can read variable") { ran += 1; assert_equal 123, test }
          end
          let(:test) { 123 }
          include_examples "test"
        end
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_shared_examples_2
        ran = 0
        rspec.example_group do
          shared_examples "test" do
            it("can read variable") { ran += 1; assert_equal 123, test }
          end
          let(:test) { 123 }
          context "sibling" do
            include_examples "test"
          end
        end
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_shared_examples_3
        ran = 0
        rspec.example_group do
          shared_examples "test" do
            it("can read variable") { ran += 1; assert_equal 123, test }
          end
          context "sibling" do
            let(:test) { 123 }
            include_examples "test"
          end
        end
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_shared_examples_global
        ran = 0
        rspec.shared_examples "test" do
          let(:test) { 123 }
        end
        rspec.describe "group 1" do
          describe "group 2" do
            include_examples "test"
            it("can read variable") { ran += 1; assert_equal 123, test }
          end
        end
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_shared_context
        ran = 0
        rspec.example_group do
          shared_context "test" do
            let(:test) { 123 }
          end
          context "sibling" do
            include_context "test"
            it("can read variable") { ran += 1; assert_equal 123, test }
          end
        end
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_shared_context_hooks
        ran = []
        rspec.example_group do
          shared_context "test" do
            around { |h| ran << :around_pre; h.run; ran << :around_post }
            before { ran << :before }
            after { ran << :after }
          end
          example_group do
            include_context "test"
            example { ran << :example }
          end
        end
        check_summary(passed: 1)
        assert_equal %i[around_pre before example after around_post], ran
      end

      def test_it_behaves_like
        ran1 = ran2 = ran3 = ran4 = 0
        rspec.example_group do
          shared_examples "test" do
            let(:test2) { 456 }
            it("can read test1") { ran1 += 1; assert_equal 123, test1 }
            it("can read test2") { ran2 += 1; assert_equal 456, test2 }
          end
          let(:test1) { 123 }
          let(:test2) { 789 }
          it_behaves_like "test"
          it("can read test1") { ran3 += 1; assert_equal 123, test1 }
          it("can read test2") { ran4 += 1; assert_equal 789, test2 }
        end
        check_summary(passed: 4)
        assert_equal [1, 1, 1, 1], [ran1, ran2, ran3, ran4]
      end

      def test_skip
        ran = 0
        rspec.example_group do
          skip("not yet") { ran += 1 }
        end
        check_summary(skipped: 1)
        assert_equal 0, ran
      end

      def test_example_without_block
        rspec.example_group do
          it("not yet")
        end
        check_summary(skipped: 1)
      end

      def test_skip_metadata
        rspec.example_group do
          describe "context", skip: true do
            example("not yet") { flunk }
            example("do it", skip: false) { pass }
          end
        end
        check_summary(passed: 1, skipped: 1)
      end

      def test_pending
        ran = 0
        rspec.example_group do
          pending("not yet") { ran += 1; flunk }
        end
        check_summary(skipped: 1)
        assert_equal 1, ran
      end

      def test_pending_must_fail
        ran = 0
        rspec.example_group do
          pending("not yet") { ran += 1 }
        end
        check_summary(failed: 1)
        assert_equal 1, ran
      end

      def test_pending_metadata
        rspec.example_group do
          describe "context", pending: true do
            example("not yet") { flunk }
            example("do it", pending: false) { pass }
          end
        end
        check_summary(passed: 1, skipped: 1)
      end

      def test_pending_instance_method
        ran = 0
        rspec.example_group do
          describe "context" do
            example("not yet") { pending; ran += 1; flunk }
          end
        end
        check_summary(skipped: 1)
        assert_equal 1, ran
      end

      def test_pending_instance_method_must_fail
        ran = 0
        rspec.example_group do
          describe "context" do
            example("not yet") { pending; ran += 1 }
          end
        end
        check_summary(failed: 1)
        assert_equal 1, ran
      end

      def test_can_check_metadata_explicitly
        ran = []
        rspec.example_group do
          before { |ex| ran << :before; assert_equal 123, ex.metadata[:test] }
          example("example", test: 123) { |ex| ran << :example; assert_equal 123, ex.metadata[:test] }
          after { |ex| ran << :after; assert_equal 123, ex.metadata[:test] }
        end
        check_summary(passed: 1)
        assert_equal %i[before example after], ran
      end

      def test_example_default_unique_names
        rspec.example_group do
          example { pass }
          example { pass }
          example { pass }
        end
        check_summary(passed: 3)
        descriptions = suite.each_test_case_recursive.map(&:description)
        assert_equal 3, descriptions.size
        assert_equal descriptions.uniq.size, descriptions.size
      end

      def test_shared_context_module_with_example
        this = self
        ran = 0
        m = Module.new do
          extend this.rspec::SharedContext
          example { ran += 1 }
        end
        rspec.example_group do
          include m
        end
        check_summary(passed: 1)
        assert_equal 1, ran
      end

      def test_shared_context_module_with_before_after
        this = self
        ran = []
        m = Module.new do
          extend this.rspec::SharedContext
          before { ran << :before }
          after { ran << :after }
        end
        rspec.example_group do
          include m
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[before example after], ran
      end

      def test_shared_context_module_with_before_after_1
        this = self
        ran = []
        m = Module.new do
          extend this.rspec::SharedContext
          before { ran << :shared_before }
          after { ran << :shared_after }
        end
        rspec.example_group do
          include m
          before { ran << :main_before }
          example { ran << :example }
          after { ran << :main_after }
        end
        check_summary(passed: 1)
        assert_equal %i[shared_before main_before example main_after shared_after], ran
      end

      def test_shared_context_module_with_before_after_2
        this = self
        ran = []
        m = Module.new do
          extend this.rspec::SharedContext
          before { ran << :shared_before }
          after { ran << :shared_after }
        end
        rspec.example_group do
          before { ran << :main_before }
          example { ran << :example }
          after { ran << :main_after }
          include m
        end
        check_summary(passed: 1)
        assert_equal %i[main_before shared_before example shared_after main_after], ran
      end

      def test_shared_context_module_with_around_1
        this = self
        ran = []
        m = Module.new do
          extend this.rspec::SharedContext
          around { |h| ran << :shared_around_pre; h.run; ran << :shared_around_post }
        end
        rspec.example_group do
          include m
          around { |h| ran << :main_around_pre; h.run; ran << :main_around_post }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[shared_around_pre main_around_pre example main_around_post shared_around_post], ran
      end

      def test_shared_context_module_with_around_2
        this = self
        ran = []
        m = Module.new do
          extend this.rspec::SharedContext
          around { |h| ran << :shared_around_pre; h.run; ran << :shared_around_post }
        end
        rspec.example_group do
          around { |h| ran << :main_around_pre; h.run; ran << :main_around_post }
          include m
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[main_around_pre shared_around_pre example shared_around_post main_around_post], ran
      end

      def test_filter_before_after
        rspec.example_group do
          before(abc: true) { @test1 = 123 }
          describe "context 1", :abc do
            before(def: true) { @test2 = 456 }
            example("example 1") { assert_equal [123, nil], [@test1, @test2] }
            example("example 2", :def, abc: false) { assert_equal [nil, 456], [@test1, @test2] }
            describe "context 2", :def do
              example("example 3") { assert_equal [123, 456], [@test1, @test2] }
              example("example 4", abc: false, def: false) { assert_equal [nil, nil], [@test1, @test2] }
            end
          end
          example("example 5") { assert_equal [nil, nil], [@test1, @test2] }
        end
        check_summary(passed: 5)
      end

      def test_configuration_before_after
        ran = []
        configure do |config|
          config.before { ran << :global_before }
          config.after { ran << :global_after }
        end
        rspec.example_group do
          before { ran << :before }
          after { ran << :after }
          example { ran << :example }
        end
        check_summary(passed: 1)
        assert_equal %i[global_before before example after global_after], ran
      end

      def test_configuration_before_after_suite
        ran = []
        configure do |config|
          config.before(:suite) { ran << :global_before }
          config.after(:suite) { ran << :global_after }
        end
        rspec.example_group do
          before { ran << :before }
          after { ran << :after }
          example { ran << :example }
          example { ran << :example }
          example { ran << :example }
        end
        check_summary(passed: 3)
        assert_equal %i[global_before
                        before example after
                        before example after
                        before example after
                        global_after],
                     ran
      end

      def test_configuration_around_suite
        ran = []
        configure do |config|
          config.around(:suite) { |h| ran << :global_pre; h.run; ran << :global_post }
        end
        rspec.example_group do
          before { ran << :before }
          after { ran << :after }
          example { ran << :example }
          example { ran << :example }
          example { ran << :example }
        end
        check_summary(passed: 3)
        assert_equal %i[global_pre
                        before example after
                        before example after
                        before example after
                        global_post],
                     ran
      end
    end

    class RSpecAdapterTestsGoldenStore < RSpecAdapterTestsBase
      def golden_store = @golden_store ||= GoldenMaster::Store.new
      def runner = @runner ||= Runner.new(golden_store:)

      def test_assert_golden_pass
        rspec.example_group do
          example("example 1") { assert_golden 123 }
          example("example 2") { assert_golden 'abc' }
        end
        check_summary(passed: 2, asserts: 0)
        golden_store.accept_trial
        reset
        rspec.example_group do
          example("example 1") { assert_golden 123 }
          example("example 2") { assert_golden 'abc' }
        end
        check_summary(passed: 2, asserts: 2)
      end

      def test_assert_golden_fail
        rspec.example_group do
          example("example 1") { assert_golden 123 }
          example("example 2") { assert_golden 'abc' }
        end
        check_summary(passed: 2, asserts: 0)
        golden_store.accept_trial
        reset
        rspec.example_group do
          example("example 1") { assert_golden 'abc' }
          example("example 2") { assert_golden 123 }
        end
        check_summary(failed: 2, asserts: 2)
      end
    end

    class RSpecAutorunTests < Minitest::Test
      include AutoRunHelpers

      def rspec(source, **opts)
        spawn_test_interpreter(['-I', 'lib', '-r', 'ruptr/rspec/override'], source, **opts)
      end

      def test_assertions
        rspec(<<~RUBY)
          require 'rspec/autorun'
          RSpec.configure do |config|
            config.expect_with(:minitest)
          end
          RSpec.describe "something" do
            example("can pass") { assert true }
            example("can skip") { skip }
            example("can fail") { assert false }
          end
        RUBY
        check_summary(passed: 1, skipped: 1, failed: 1, asserts: 2)
      end

      def test_global_shared_context
        rspec(<<~RUBY)
          require 'rspec/autorun'
          RSpec.shared_context "test" do
            let(:hello) { :world }
          end
          RSpec.describe "something" do
            include_context "test"
            example { hello == :world or fail }
          end
        RUBY
        check_summary(passed: 1)
      end

      def test_matchers
        rspec(<<~RUBY)
          require 'rspec/autorun'
          RSpec.configure do |config|
            config.expect_with :rspec
          end
          RSpec.describe "something" do
            example("can pass") { expect(123).to eq(123) }
            skip("can skip") { expect(456).to eq(123) }
            example("can fail") { expect(456).to eq(789) }
          end
        RUBY
        check_summary(passed: 1, skipped: 1, failed: 1, asserts: 2)
      end

      def test_capybara
        rspec(<<~RUBY)
          require 'rspec/autorun'
          require 'capybara/rspec'
          app = ->(_env) { [200, { 'content_type' => 'text/html' }, ["<p>Hello, world!</p>\n"]] }
          RSpec.configure do |config|
            config.expect_with :rspec
          end
          Capybara.threadsafe = true
          RSpec.feature "rack app" do
            before { Capybara.app = app }
            scenario "it renders page without errors" do
              visit '/'
              expect(status_code).to eq(200)
            end
            scenario "it says hello" do
              visit '/'
              expect(page).to have_content(/hello/i)
            end
            feature "sub-page" do
              background { visit "/test" }
              scenario "it still says hello" do
                expect(page).to have_content(/hello/i)
              end
            end
          end
        RUBY
        check_summary(passed: 3)
      end
    end
  end
end
