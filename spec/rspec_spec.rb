# frozen_string_literal: true

require_relative 'spec_helper'
require 'ruptr/rspec'
require 'ruptr/runner'
require 'ruptr/golden_master'

module Ruptr
  RSpec.describe Compat::RSpec do
    let(:adapter) { subject.adapter_module }
    let(:suite) { subject.adapted_test_suite }
    let(:runner_class) { Runner }
    let(:runner) { runner_class.new(randomize: true) }
    let(:report) { runner.run_report(suite) }

    def rspec(&) = block_given? ? adapter.module_eval(&) : adapter
    def configure(...) = adapter.configure(...)
    def example_group(...) = rspec.example_group(...)

    def check_report(passed: 0, skipped: 0, failed: 0, asserts: nil, ineffective_asserts: nil)
      assert_equal passed + skipped + failed, report.total_test_cases, "total test cases"
      assert_equal passed, report.total_passed_test_cases, "passed test cases"
      assert_equal skipped, report.total_skipped_test_cases, "skipped test cases"
      assert_equal failed, report.total_failed_test_cases, "failed test cases"
      assert_equal failed.zero?, report.passed?
      assert_equal !failed.zero?, report.failed?
      assert_equal asserts, report.total_assertions, "total assertions" unless asserts.nil?
      assert_equal ineffective_asserts, report.total_ineffective_assertions, "total ineffective assertions" \
        unless ineffective_asserts.nil?
    rescue
      print_report
      raise
    end

    def print_report
      require 'ruptr/plain'
      report.emit(Formatter::Plain.new($stdout))
    end

    describe "empty test group" do
      it "runs" do
        example_group { }
        check_report
      end
    end

    describe "simple test suite without labels" do
      it "runs" do
        ran_pass = ran_skip = ran_fail = 0
        example_group do
          example { ran_pass += 1 }
          example { ran_skip += 1; skip }
          example { ran_fail += 1; fail }
        end
        check_report(passed: 1, failed: 1, skipped: 1)
        assert_equal [1, 1, 1], [ran_pass, ran_skip, ran_fail]
      end
    end

    describe "simple test suite with labels" do
      it "runs" do
        ran_pass = ran_skip = ran_fail = 0
        example_group "something" do
          it("can pass") { ran_pass += 1 }
          it("can skip") { ran_skip += 1; skip }
          it("can fail") { ran_fail += 1; fail }
        end
        check_report(passed: 1, failed: 1, skipped: 1)
        assert_equal [1, 1, 1], [ran_pass, ran_skip, ran_fail]
      end
    end

    describe "example nested in example group" do
      it "runs" do
        ran = 0
        example_group do
          example_group { example { ran += 1 } }
        end
        check_report(passed: 1)
        assert_equal 1, ran
      end
    end

    describe "example in deeply nested example group" do
      it "runs" do
        ran = 0
        example_group do
          example_group { example_group { example_group { example { ran += 1 } } } }
        end
        check_report(passed: 1)
        assert_equal 1, ran
      end
    end

    describe "example groups and example with labels" do
      it "sets example description" do
        ran = 0
        rspec.describe "example group" do
          describe "example subgroup" do
            it("can run example") { ran += 1 }
          end
        end
        assert_equal ["[RSpec] example group example subgroup can run example"],
                     suite.each_test_case_recursive.map(&:description)
        check_report(passed: 1)
        assert_equal 1, ran
      end
    end

    describe "examples without labels" do
      it "gives unique descriptions to examples" do
        example_group do
          example { }
          example { }
          example { }
        end
        check_report(passed: 3)
        descriptions = suite.each_test_case_recursive.map(&:description)
        assert_equal 3, descriptions.size
        assert_equal descriptions.uniq.size, descriptions.size
      end
    end

    describe "skipping" do
      def check_skipped_exceptions(expected_reason = nil)
        report.each_test_element_result do |_, tr|
          next unless tr.skipped?
          assert_kind_of SkippedExceptionMixin, tr.exception
          if expected_reason.nil?
            assert_nil tr.exception.reason
          else
            assert_equal tr.exception.reason, expected_reason
          end
        end
      end

      describe "examples without blocks" do
        it "skips examples" do
          example_group do
            example
            it("works?")
          end
          check_report(skipped: 2)
          check_skipped_exceptions
        end
      end

      describe ".skip" do
        it "skips examples" do
          ran = 0
          example_group do
            skip { ran += 1 }
            skip("works?") { ran += 1 }
          end
          check_report(skipped: 2)
          assert_equal 0, ran
          check_skipped_exceptions
        end
      end

      describe "#skip" do
        it "skips rest of example block" do
          ran = []
          example_group do
            example { ran << :pre; skip; ran << :post }
          end
          check_report(skipped: 1)
          assert_equal [:pre], ran
          check_skipped_exceptions
        end

        it "skips with a reason" do
          example_group do
            example { skip "not yet" }
          end
          check_report(skipped: 1)
          check_skipped_exceptions("not yet")
        end
      end

      describe "skipping with metadata" do
        it "skips example with direct metadata" do
          ran = 0
          example_group do
            example(skip: true) { ran += 1 }
          end
          check_report(skipped: 1)
          assert_equal 0, ran
          check_skipped_exceptions
        end

        it "skips example with inherited metadata" do
          ran1 = ran2 = 0
          example_group do
            example_group skip: true do
              example { ran1 += 1 }
              example(skip: false) { ran2 += 1 }
            end
          end
          check_report(passed: 1, skipped: 1)
          assert_equal [0, 1], [ran1, ran2]
          check_skipped_exceptions
        end

        it "skips example using metadata value as reason" do
          ran = 0
          example_group do
            example(skip: "not yet") { ran += 1 }
          end
          check_report(skipped: 1)
          assert_equal 0, ran
          check_skipped_exceptions("not yet")
        end

        it "does not skip example if metadata value is falsey" do
          ran = 0
          example_group do
            example(skip: nil) { ran += 1 }
            example(skip: false) { ran += 1 }
          end
          check_report(passed: 2)
          assert_equal 2, ran
        end
      end
    end

    describe "pending" do
      def check_pending_exceptions(expected_reason = nil)
        report.each_test_element_result do |_, tr|
          case
          when tr.skipped?
            assert_kind_of PendingSkippedException, tr.exception
            if expected_reason.nil?
              assert_nil tr.exception.reason
            else
              assert_equal tr.exception.reason, expected_reason
            end
          when tr.failed?
            assert_kind_of PendingPassedError, tr.exception
          end
        end
      end

      describe ".pending" do
        it "sets examples as pending" do
          ran = 0
          example_group do
            pending { ran += 1; fail }
            pending("works?") { ran += 1; fail }
          end
          check_report(skipped: 2)
          assert_equal 2, ran
          check_pending_exceptions
        end

        it "must raise exception" do
          ran = 0
          example_group do
            pending { ran += 1 }
          end
          check_report(failed: 1)
          assert_equal 1, ran
          check_pending_exceptions
        end
      end

      describe "#pending" do
        it "sets example as pending" do
          ran = []
          example_group do
            example { ran << :pre_pending; pending; ran << :post_pending; fail; ran << :YIKES }
          end
          check_report(skipped: 1)
          assert_equal %i[pre_pending post_pending], ran
          check_pending_exceptions
        end

        it "sets example as pending with a reason" do
          example_group do
            example { pending "not yet"; fail }
          end
          check_report(skipped: 1)
          check_pending_exceptions("not yet")
        end

        it "must raise exception" do
          ran = 0
          example_group do
            example { pending; ran += 1 }
          end
          check_report(failed: 1)
          assert_equal 1, ran
          check_pending_exceptions
        end
      end

      describe "skipping with metadata" do
        it "example can be set as pending with metadata" do
          ran = 0
          example_group do
            example(pending: true) { ran += 1; fail }
          end
          check_report(skipped: 1)
          assert_equal 1, ran
          check_pending_exceptions
        end

        it "example can be set as pending with inherited metadata" do
          ran1 = ran2 = 0
          example_group do
            example_group pending: true do
              example { ran1 += 1; fail }
              example(pending: false) { ran2 += 1 }
            end
          end
          check_report(passed: 1, skipped: 1)
          assert_equal [1, 1], [ran1, ran2]
          check_pending_exceptions
        end

        it "must raise exception" do
          ran = 0
          example_group do
            example(pending: true) { ran += 1 }
          end
          check_report(failed: 1)
          assert_equal 1, ran
          check_pending_exceptions
        end

        it "uses metadata value as reason" do
          ran = 0
          example_group do
            example(pending: "not yet") { ran += 1; fail }
          end
          check_report(skipped: 1)
          assert_equal 1, ran
          check_pending_exceptions("not yet")
        end

        it "does not set example as pending if metadata value is falsey" do
          ran = 0
          example_group do
            example(pending: nil) { ran += 1 }
            example(pending: false) { ran += 1 }
          end
          check_report(passed: 2)
          assert_equal 2, ran
        end
      end
    end

    describe "example handler" do
      it "allows to inspect example's metadata" do
        seen1 = seen2 = seen3 = nil
        example_group do
          before { |ex| seen1 = ex.metadata[:test] }
          example("example", test: 123) { |ex| seen2 = ex.metadata[:test] }
          after { |ex| seen3 = ex.metadata[:test] }
        end
        check_report(passed: 1)
        assert_equal [123, 123, 123], [seen1, seen2, seen3]
      end
    end

    describe "#let" do
      it "can be accessed from example" do
        ran = 0
        seen = nil
        example_group do
          let(:test) { ran += 1; 123 }
          example { seen = test }
        end
        check_report(passed: 1)
        assert_equal 1, ran
        assert_equal 123, seen
      end

      it "can be accessed from nested example groups" do
        ran = 0
        seen = nil
        example_group do
          let(:test) { ran += 1; 123 }
          example_group do
            example { seen = test }
          end
        end
        check_report(passed: 1)
        assert_equal 1, ran
        assert_equal 123, seen
      end

      context "when it is never accessed" do
        it "does not call the block" do
          ran = 0
          example_group do
            let(:test) { ran += 1 }
            example { }
          end
          check_report(passed: 1)
          assert_equal 0, ran
        end
      end

      context "when accessed multiple times in the same example" do
        it "calls the block only once" do
          ran = 0
          seen = []
          example_group do
            let(:test) { ran += 1; 123 }
            example { 2.times { seen << test } }
          end
          check_report(passed: 1)
          assert_equal 1, ran
          assert_equal [123, 123], seen
        end
      end

      context "when accessed from different examples" do
        it "calls the block multiple times" do
          ran = 0
          seen = []
          example_group do
            let(:test) { ran += 1; 123 }
            example { seen << test }
            example { seen << test }
          end
          check_report(passed: 2)
          assert_equal 2, ran
          assert_equal [123, 123], seen
        end
      end

      it "supports names that end with '?'/'!'" do
        seen1 = seen2 = nil
        example_group do
          let(:test?) { 123 }
          let(:test!) { 456 }
          it("test?") { seen1 = test? }
          it("test!") { seen2 = test! }
        end
        check_report(passed: 2)
        assert_equal [123, 456], [seen1, seen2]
      end

      it "supports nil values" do
        ran = 0
        seen = []
        example_group do
          let(:test) { ran += 1; nil }
          it("can read the variable twice") { 2.times { seen << test } }
        end
        check_report(passed: 1)
        assert_equal 1, ran
        assert_equal [nil, nil], seen
      end

      it "can be accessed from the block of another \"let\"" do
        ran1 = ran2 = 0
        seen = []
        example_group do
          let(:test1) { ran1 += 1; 123 }
          let(:test2) { ran2 += 1; test1 * 2 }
          example { 2.times { seen << test2 << test1 } }
        end
        check_report(passed: 1)
        assert_equal [1, 1], [ran1, ran2]
        assert_equal [246, 123, 246, 123], seen
      end

      it "can set instance variable" do
        seen = nil
        example_group do
          let(:test) { @abc = 123; nil }
          example { test; seen = @abc }
        end
        check_report(passed: 1)
        assert_equal 123, seen
      end

      describe "#let!" do
        it "calls the block before the example runs" do
          ran = []
          example_group do
            let!(:test) { ran << :let; nil }
            example("example") { ran << :enter_example; test; ran << :leave_example }
          end
          check_report(passed: 1)
          assert_equal %i[let enter_example leave_example], ran
        end

        it "calls the block only once per example" do
          ran = 0
          seen = []
          example_group do
            let!(:test) { ran += 1; 123 }
            example("example") { 2.times { seen << test } }
          end
          check_report(passed: 1)
          assert_equal 1, ran
          assert_equal [123, 123], seen
        end

        it "calls the block multiple times when there are multiple examples" do
          ran = 0
          example_group do
            let!(:test) { ran += 1; 123 }
            example { }
            example { }
          end
          check_report(passed: 2)
          assert_equal 2, ran
        end
      end
    end

    describe "#subject" do
      describe "explicitly set" do
        it "can be set explicitly" do
          seen = nil
          example_group do
            subject { 123 }
            example { seen = subject }
          end
          check_report(passed: 1)
          assert_equal 123, seen
        end

        context "when accessed multiple times from the same example" do
          it "calls the block only once" do
            ran = 0
            seen = []
            example_group do
              subject { ran += 1; 123 }
              example { 2.times { seen << subject } }
            end
            check_report(passed: 1)
            assert_equal 1, ran
            assert_equal [123, 123], seen
          end
        end

        context "when never accessed" do
          it "does not call the block" do
            ran = 0
            example_group do
              subject { ran += 1; fail }
              example { }
            end
            check_report(passed: 1)
            assert_equal 0, ran
          end
        end

        context "when accessed from multiple examples" do
          it "calls the block multiple times" do
            ran = 0
            example_group do
              subject { ran += 1; 123 }
              example { subject }
              example { subject }
            end
            check_report(passed: 2)
            assert_equal 2, ran
          end
        end

        it "is not overriden by nested example groups with non-subject labels" do
          ran = 0
          seen1 = seen2 = seen3 = nil
          example_group do
            subject { ran += 1; 123 }
            example { seen1 = subject }
            example_group do
              example { seen2 = subject }
            end
            describe "something" do
              example { seen3 = subject }
            end
          end
          check_report(passed: 3)
          assert_equal 3, ran
          assert_equal [123, 123, 123], [seen1, seen2, seen3]
        end
      end

      describe "implicitly set" do
        context "when label is a module" do
          it "sets subject" do
            m = Module.new
            seen = nil
            rspec.describe m do
              example { seen = subject }
            end
            check_report(passed: 1)
            assert_same m, seen
          end
        end

        context "when label is a class" do
          it "sets subject to new instance of class" do
            c = Class.new
            seen = nil
            rspec.describe c do
              example { seen = subject }
            end
            check_report(passed: 1)
            assert_instance_of c, seen
          end

          it "instantiates class only once per example" do
            c = Class.new
            seen = []
            rspec.describe c do
              example { 2.times { seen << subject } }
            end
            check_report(passed: 1)
            seen.each { |o| assert_instance_of c, o }
            assert_equal 2, seen.size
            assert_same seen[0], seen[1]
          end

          it "each example gets a different instance" do
            seen = []
            c = Class.new
            rspec.describe c do
              example { seen << subject }
              example { seen << subject }
            end
            check_report(passed: 2)
            seen.each { |o| assert_instance_of c, o }
            assert_equal 2, seen.size
            refute_same seen[0], seen[1]
          end
        end

        it "can override explicitly set subject in parent example group" do
          seen1 = seen2 = nil
          example_group do
            subject { 123 }
            example { seen1 = subject }
            describe Array do
              example { seen2 = subject }
            end
          end
          check_report(passed: 2)
          assert_equal 123, seen1
          assert_kind_of Array, seen2
        end
      end

      describe "named" do
        it "can access subject with alternative name" do
          seen = nil
          example_group do
            subject(:test) { 123 }
            example { seen = test }
          end
          check_report(passed: 1)
          assert_equal 123, seen
        end

        it "can still be accessed as \"subject\"" do
          seen = nil
          example_group do
            subject(:test) { 123 }
            example { seen = subject }
          end
          check_report(passed: 1)
          assert_equal 123, seen
        end

        it "nested example group does not override alternative name" do
          seen1 = seen2 = nil
          example_group do
            subject(:test) { 123 }
            example_group do
              subject { 456 }
              example { seen1 = [test, subject] }
            end
            example { seen2 = [test, subject] }
          end
          check_report(passed: 2)
          assert_equal [123, 456], seen1
          assert_equal [123, 123], seen2
        end
      end

      describe "#subject!" do
        it "calls the block before the example runs" do
          ran = []
          seen = nil
          example_group do
            subject! { ran << :subject; 123 }
            example { ran << :enter_example; seen = subject; ran << :leave_example }
          end
          check_report(passed: 1)
          assert_equal 123, seen
          assert_equal %i[subject enter_example leave_example], ran
        end
      end
    end

    describe "hooks" do
      describe "example-level" do
        describe "#before" do
          it "runs before example" do
            ran = []
            example_group do
              before { ran << :before }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[before example], ran
          end

          it "runs before each example" do
            ran = []
            example_group do
              before { ran << :before }
              example { ran << :example }
              example { ran << :example }
              example { ran << :example }
            end
            check_report(passed: 3)
            assert_equal %i[before example before example before example], ran
          end

          it "runs before example in nested example group" do
            ran = []
            example_group do
              before { ran << :before }
              example_group do
                example { ran << :example }
              end
            end
            check_report(passed: 1)
            assert_equal %i[before example], ran
          end

          it "can set instance variable" do
            seen = nil
            example_group do
              before { @test = 123 }
              example { seen = @test }
            end
            check_report(passed: 1)
            assert_equal 123, seen
          end

          it "can set instance variable for nested example group" do
            seen = nil
            example_group do
              before { @test = 123 }
              example_group do
                example { seen = @test }
              end
            end
            check_report(passed: 1)
            assert_equal 123, seen
          end

          (2..5).each do |i|
            it "runs hooks (#{i}) in the order they were added" do
              ran = []
              example_group do
                i.times { before { ran << :"before#{i}" } }
                example_group do
                  example { ran << :example }
                end
              end
              check_report(passed: 1)
              assert_equal [*i.times.map { :"before#{i}" }, :example], ran
            end
          end

          it "merges hooks in nested example groups" do
            ran = []
            example_group do
              before { ran << :outer_before }
              example_group do
                before { ran << :inner_before }
                example { ran << :example }
              end
            end
            check_report(passed: 1)
            assert_equal %i[outer_before inner_before example], ran
          end

          it "merges hooks in deeply nested example groups" do
            ran = []
            example_group do
              before { ran << :outer_before }
              example_group do
                example_group do
                  before { ran << :inner_before }
                  example { ran << :example }
                end
              end
            end
            check_report(passed: 1)
            assert_equal %i[outer_before inner_before example], ran
          end

          it "does not run next hooks or example after an error" do
            ran = []
            example_group do
              before { ran << :before1 }
              before { ran << :before2; fail }
              before { ran << :before3 }
              example { ran << :example }
            end
            check_report(failed: 1)
            assert_equal %i[before1 before2], ran
          end
        end

        describe "#prepend_before" do
          it "runs hook before other #before hooks" do
            ran = []
            example_group do
              before { ran << :before2 }
              before { ran << :before3 }
              before { ran << :before4 }
              prepend_before { ran << :before1 }
              before { ran << :before5 }
              example_group do
                example { ran << :example }
              end
            end
            check_report(passed: 1)
            assert_equal %i[before1 before2 before3 before4 before5 example], ran
          end
        end

        describe "#after" do
          it "runs after example" do
            ran = []
            example_group do
              after { ran << :after }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[example after], ran
          end

          it "runs after each example" do
            ran = []
            example_group do
              after { ran << :after }
              example { ran << :example }
              example { ran << :example }
              example { ran << :example }
            end
            check_report(passed: 3)
            assert_equal %i[example after example after example after], ran
          end

          it "runs after example in nested example group" do
            ran = []
            example_group do
              after { ran << :after }
              example_group do
                example { ran << :example }
              end
            end
            check_report(passed: 1)
            assert_equal %i[example after], ran
          end

          (2..5).each do |i|
            it "runs hooks (#{i}) in the reverse order that they were added" do
              ran = []
              example_group do
                i.times { after { ran << :"after#{i}" } }
                example_group do
                  example { ran << :example }
                end
              end
              check_report(passed: 1)
              assert_equal [:example, *i.times.map { :"after#{i}" }.reverse], ran
            end
          end

          it "merges hooks in nested example groups" do
            ran = []
            example_group do
              after { ran << :outer_after }
              example_group do
                after { ran << :inner_after }
                example { ran << :example }
              end
            end
            check_report(passed: 1)
            assert_equal %i[example inner_after outer_after], ran
          end

          it "merges hooks in deeply nested example groups" do
            ran = []
            example_group do
              after { ran << :outer_after }
              example_group do
                example_group do
                  after { ran << :inner_after }
                  example { ran << :example }
                end
              end
            end
            check_report(passed: 1)
            assert_equal %i[example inner_after outer_after], ran
          end

          it "still runs next #after hooks after an error in hook" do
            ran = []
            example_group do
              after { ran << :after3 }
              after { ran << :after2; fail }
              after { ran << :after1 }
              example { ran << :example }
            end
            check_report(failed: 1)
            assert_equal %i[example after1 after2 after3], ran
          end

          it "still runs #after hooks after an error in example" do
            ran = 0
            example_group do
              after { ran += 1 }
              example { fail }
            end
            check_report(failed: 1)
            assert_equal 1, ran
          end

          it "$! is set in next hooks after an error in hook" do
            seen1 = seen2 = nil
            e = Class.new(StandardError)
            example_group do
              after { seen2 = $! }
              after { raise e }
              after { seen1 = $! }
              example { }
            end
            check_report(failed: 1)
            assert_nil seen1
            refute_nil seen2
            assert_instance_of e, seen2
          end

          it "$! is set in next hooks after an error in example" do
            seen = nil
            e = Class.new(StandardError)
            example_group do
              after { seen = $! }
              example { raise e }
            end
            check_report(failed: 1)
            assert_instance_of e, seen
          end
        end

        describe "#append_after" do
          it "runs hook after other #after hooks" do
            ran = []
            example_group do
              after { ran << :after4 }
              after { ran << :after3 }
              append_after { ran << :after5 }
              after { ran << :after2 }
              after { ran << :after1 }
              example_group do
                example { ran << :example }
              end
            end
            check_report(passed: 1)
            assert_equal %i[example after1 after2 after3 after4 after5], ran
          end
        end

        describe "#around_layer" do
          it "runs around example" do
            ran = []
            example_group do
              around_layer { |ex| ran << :around_pre; ex.run; ran << :around_post }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[around_pre example around_post], ran
          end

          it "runs around each example" do
            ran = []
            example_group do
              around_layer { |ex| ran << :around_pre; ex.run; ran << :around_post }
              example { ran << :example }
              example { ran << :example }
            end
            check_report(passed: 2)
            assert_equal %i[around_pre example around_post around_pre example around_post], ran
          end

          it "supports #to_proc on the handle" do
            ran = []
            example_group do
              around_layer { |ex| ran << :around_pre; ex.to_proc.call; ran << :around_post }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[around_pre example around_post], ran
          end

          it "can call handle with yield" do
            ran = []
            example_group do
              def do_yield = yield
              around_layer { |ex| ran << :around_pre; do_yield(&ex); ran << :around_post }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[around_pre example around_post], ran
          end

          it "supports multiple hooks in the same example group" do
            ran = []
            example_group do
              around_layer { |ex| ran << :around1_pre; ex.run; ran << :around1_post }
              around_layer { |ex| ran << :around2_pre; ex.run; ran << :around2_post }
              around_layer { |ex| ran << :around3_pre; ex.run; ran << :around3_post }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[around1_pre around2_pre around3_pre example around3_post around2_post around1_post], ran
          end
        end

        describe "#around" do
          it "runs around example" do
            ran = []
            example_group do
              around { |ex| ran << :around_pre; ex.run; ran << :around_post }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[around_pre example around_post], ran
          end

          it "runs around each example" do
            ran = []
            example_group do
              around { |ex| ran << :around_pre; ex.run; ran << :around_post }
              example { ran << :example }
              example { ran << :example }
            end
            check_report(passed: 2)
            assert_equal %i[around_pre example around_post around_pre example around_post], ran
          end

          it "supports multiple hooks in the same example group" do
            ran = []
            example_group do
              around { |ex| ran << :around1_pre; ex.run; ran << :around1_post }
              around { |ex| ran << :around2_pre; ex.run; ran << :around2_post }
              around { |ex| ran << :around3_pre; ex.run; ran << :around3_post }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[around1_pre around2_pre around3_pre
                            example
                            around3_post around2_post around1_post], ran
          end

          it "skips examples when the hook skips" do
            ran = []
            example_group do
              around { ran << :around_pre; skip; ran << :around_post }
              example { ran << :example }
            end
            check_report(skipped: 1)
            assert_equal %i[around_pre], ran
          end

          it "skips examples when the handle's #run method is not called" do
            ran = []
            example_group do
              around { ran << :around }
              example { ran << :example }
            end
            check_report(skipped: 1)
            assert_equal %i[around], ran
          end

          it "skips examples when the hook is pending" do
            ran = []
            example_group do
              around { pending; ran << :around_pre; fail; ran << :around_post }
              example { ran << :example }
            end
            check_report(skipped: 1)
            assert_equal %i[around_pre], ran
          end
        end

        describe "combinations of hooks" do
          it "runs #before and #after sibling hooks" do
            ran = []
            example_group do
              before { ran << :before1 }
              before { ran << :before2 }
              after { ran << :after1 }
              after { ran << :after2 }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[before1 before2 example after2 after1], ran
          end

          it "#before/#after hooks and example can set and get instance variables" do
            seen = []
            example_group do
              before { seen << [:before_outer, @test1, @test2, @test3, @test4, @test5]; @test1 = :a }
              after { seen << [:after_outer, @test1, @test2, @test3, @test4, @test5]; @test2 = :b }
              describe "with a subgroup" do
                before { seen << [:before_inner, @test1, @test2, @test3, @test4, @test5]; @test3 = :c }
                after { seen << [:after_inner, @test1, @test2, @test3, @test4, @test5]; @test4 = :d }
                example { seen << [:example, @test1, @test2, @test3, @test4, @test5]; @test5 = :e }
              end
            end
            check_report(passed: 1)
            assert_equal [[:before_outer, nil, nil, nil, nil, nil],
                          [:before_inner, :a, nil, nil, nil, nil],
                          [:example, :a, nil, :c, nil, nil],
                          [:after_inner, :a, nil, :c, nil, :e],
                          [:after_outer, :a, nil, :c, :d, :e]],
                         seen
          end

          it "runs #before and #after nested hooks in the right order" do
            ran = []
            example_group do
              before { ran << :outer_before_1 }
              before { ran << :outer_before_2 }
              after { ran << :outer_after_1 }
              after { ran << :outer_after_2 }
              example_group do
                before { ran << :middle_before_1 }
                before { ran << :middle_before_2 }
                after { ran << :middle_after_1 }
                after { ran << :middle_after_2 }
                example_group do
                  example_group do
                    before { ran << :inner_before_1 }
                    example { ran << :nested_example }
                    after { ran << :inner_after_1 }
                  end
                end
              end
            end
            check_report(passed: 1)
            assert_equal %i[outer_before_1 outer_before_2
                            middle_before_1 middle_before_2
                            inner_before_1
                            nested_example
                            inner_after_1
                            middle_after_2 middle_after_1
                            outer_after_2 outer_after_1],
                         ran
          end

          it "still runs #after hook after an error in #before hook" do
            ran = []
            example_group do
              before { ran << :before; fail }
              after { ran << :after }
              example { ran << :example }
            end
            check_report(failed: 1)
            assert_equal %i[before after], ran
          end

          it "still runs #after hook after an error in #before hook with nested example groups" do
            ran = []
            example_group do
              before { ran << :outer_before }
              after { ran << :outer_after }
              example_group do
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
            end
            check_report(failed: 1)
            assert_equal %i[outer_before inner_before_1 inner_before_2
                            inner_after_3 inner_after_2 inner_after_1 outer_after],
                         ran
          end

          it "supports #around_layer with #before and #around hooks" do
            ran = []
            example_group do
              around_layer { |ex| ran << :around1_pre; ex.run; ran << :around1_post }
              around_layer { |ex| ran << :around2_pre; ex.run; ran << :around2_post }
              around_layer { |ex| ran << :around3_pre; ex.run; ran << :around3_post }
              before { ran << :before }
              example { ran << :example }
              after { ran << :after }
            end
            check_report(passed: 1)
            assert_equal %i[around1_pre around2_pre around3_pre before
                            example
                            after around3_post around2_post around1_post], ran
          end

          it "supports #around_layer with #before and #around hooks with nested example groups" do
            ran = []
            example_group do
              around_layer { |ex| ran << :around1_pre; ex.run; ran << :around1_post }
              around_layer { |ex| ran << :around2_pre; ex.run; ran << :around2_post }
              before { ran << :before1 }
              example_group do
                before { ran << :before2 }
                around_layer { |ex| ran << :around3_pre; ex.run; ran << :around3_post }
                around_layer { |ex| ran << :around4_pre; ex.run; ran << :around4_post }
                example { ran << :example }
                after { ran << :after2 }
              end
              after { ran << :after1 }
            end
            check_report(passed: 1)
            assert_equal %i[around1_pre around2_pre before1 around3_pre around4_pre before2
                            example
                            after2 around4_post around3_post after1 around2_post around1_post],
                         ran
          end

          it "supports #around and #around_layer" do
            ran = []
            example_group do
              around { |ex| ran << :around1_pre; ex.run; ran << :around1_post }
              around_layer { |ex| ran << :around_layer_pre; ex.run; ran << :around_layer_post }
              around { |ex| ran << :around2_pre; ex.run; ran << :around2_post }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[around1_pre around2_pre around_layer_pre
                            example
                            around_layer_post around2_post around1_post], ran
          end

          it "supports #around with #before and #around hooks with nested example groups" do
            ran = []
            example_group do
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
            check_report(passed: 1)
            assert_equal %i[around1_pre around2_pre around3_pre around4_pre around5_pre
                            before1 before2 before3
                            example
                            after3 after2 after1
                            around5_post around4_post around3_post around2_post around1_post],
                         ran
          end

          it "helper methods can be called from hooks" do
            seen = []
            example_group do
              def helper_1 = 123
              before { seen[0] = helper_1 }
              after { seen[1] = helper_1 }
              around_layer { |h| seen[2] = helper_1; h.run }
              example_group do
                def helper_2 = 456
                before { seen[3] = helper_1 }
                before { seen[4] = helper_2 }
                after { seen[5] = helper_1 }
                after { seen[6] = helper_2 }
                around_layer { |h| seen[7] = helper_1; h.run }
                around_layer { |h| seen[8] = helper_2; h.run }
                example { seen[9] = helper_1 }
                example { seen[10] = helper_2 }
              end
            end
            check_report(passed: 2)
            assert_equal [123, 123, 123, 123, 456, 123, 456, 123, 456, 123, 456], seen
          end

          describe "metadata restrictions" do
            it "only runs #before/#after hooks with matching metadata" do
              seen = []
              example_group do
                before(abc: true) { @test1 = 123 }
                example_group(abc: true) do
                  before(def: true) { @test2 = 456 }
                  example { seen[0] = [@test1, @test2] }
                  example(def: true, abc: false) { seen[1] = [@test1, @test2] }
                  example_group(def: true) do
                    example { seen[2] = [@test1, @test2] }
                    example(abc: false, def: false) { seen[3] = [@test1, @test2] }
                  end
                end
                example { seen[4] = [@test1, @test2] }
                example(abc: true, def: true) { seen[5] = [@test1, @test2] }
              end
              check_report(passed: 6)
              assert_equal [[123, nil],
                            [nil, 456],
                            [123, 456],
                            [nil, nil],
                            [nil, nil],
                            [123, nil]],
                           seen
            end

            it "runs #around hook with matching metadata" do
              seen = nil
              example_group do
                around(test: true) { |h| @test = 123; h.run }
                example(test: true) { seen = @test }
              end
              check_report(passed: 1)
              assert_equal 123, seen
            end

            it "does not run #around hook with non-matching metadata" do
              ran = 0
              example_group do
                around(test: true) { |h| @test = 123; h.run }
                example { ran += 1 }
              end
              check_report(passed: 1)
              assert_equal 1, ran
            end
          end

          it "can add hooks via configuration" do
            ran = []
            configure do |config|
              config.before { ran << :global_before }
              config.after { ran << :global_after }
            end
            example_group do
              before { ran << :before }
              after { ran << :after }
              example { ran << :example }
            end
            check_report(passed: 1)
            assert_equal %i[global_before before example after global_after], ran
          end
        end
      end

      describe "context-level" do
        describe "#before" do
          it "runs hook only once" do
            ran = 0
            example_group do
              before(:context) { ran += 1 }
              example { }
              example { }
            end
            check_report(passed: 2)
            assert_equal 1, ran
          end
        end

        describe "#after" do
          it "runs hook only once" do
            ran = 0
            example_group do
              after(:context) { ran += 1 }
              example { }
              example { }
            end
            check_report(passed: 2)
            assert_equal 1, ran
          end
        end

        describe "#around_layer" do
          it "runs hook only once" do
            ran = 0
            example_group do
              around_layer(:context) { |h| ran += 1; h.run }
              example { }
              example { }
            end
            check_report(passed: 2)
            assert_equal 1, ran
          end

          it "runs hooks for nested example groups" do
            ran = []
            example_group do
              around_layer(:context) { |h| ran << :context1_pre; h.run; ran << :context1_post }
              around_layer(:context) { |h| ran << :context2_pre; h.run; ran << :context2_post }
              example_group do
                around_layer(:context) { |h| ran << :context3_pre; h.run; ran << :context3_post }
                example { ran << :example }
              end
            end
            check_report(passed: 1)
            assert_equal %i[context1_pre context2_pre context3_pre
                            example
                            context3_post context2_post context1_post],
                         ran
          end

          it "skips examples when the handle's #run method is not called" do
            ran = []
            example_group do
              around_layer(:context) { ran << :around }
              example { ran << :example }
            end
            check_report(skipped: 1)
            assert_equal %i[around], ran
          end
        end

        describe "combinations of hooks" do
          it "supports #before and #after hooks in the same example group" do
            ran = []
            example_group do
              before(:context) { ran << :before }
              after(:context) { ran << :after }
              example { ran << :example }
              example { ran << :example }
              example { ran << :example }
            end
            check_report(passed: 3)
            assert_equal %i[before example example example after], ran
          end

          it "supports #before and #after hooks in nested example groups" do
            ran = []
            example_group do
              before(:context) { ran << :context1_before }
              after(:context) { ran << :context1_after }
              example { ran << :example1 }
              example_group do
                before(:context) { ran << :context2_before }
                after(:context) { ran << :context2_after }
                example_group do
                  example { ran << :example2 }
                  example_group do
                    example_group do
                      around_layer(:context) { |h| ran << :context4_around_pre; h.run; ran << :context4_around_post }
                      example_group do
                        before(:context) { ran << :context5_before }
                        after(:context) { ran << :context5_after }
                        example { ran << :example3 }
                      end
                    end
                  end
                end
                before(:context) { ran << :context3_before }
                after(:context) { ran << :context3_after }
              end
            end
            check_report(passed: 3)
            assert_equal %i[context1_before
                            example1
                            context2_before
                            context3_before
                            example2
                            context4_around_pre
                            context5_before
                            example3
                            context5_after
                            context4_around_post
                            context3_after
                            context2_after
                            context1_after],
                         ran
          end

          it "carryovers instance variables" do
            seen1 = seen2 = seen3 = nil
            example_group do
              before(:context) { seen1 = @test; @test = 123 }
              after(:context) { seen2 = @test }
              example { seen3 = @test }
            end
            check_report(passed: 1)
            assert_equal [nil, 123, 123], [seen1, seen2, seen3]
          end

          it "carryovers instance variables for nested example groups" do
            seen = []
            example_group do
              before(:context) { seen[0] = [@test1, @test2]; @test1 = 123 }
              after(:context) { seen[1] = [@test1, @test2] }
              example { seen[2] = [@test1, @test2] }
              example_group do
                example { seen[3] = [@test1, @test2] }
                example_group do
                  before(:context) { seen[4] = [@test1, @test2]; @test2 = 456 }
                  after(:context) { seen[5] = [@test1, @test2] }
                  example { seen[6] = [@test1, @test2] }
                end
              end
            end
            check_report(passed: 3)
            assert_equal [[nil, nil],
                          [123, nil],
                          [123, nil],
                          [123, nil],
                          [123, nil],
                          [123, 456],
                          [123, 456]],
                         seen
          end

          describe "added via configuration" do
            it "can add #before/#after" do
              ran = []
              configure do |config|
                config.before(:context) { ran << :global_before }
                config.after(:context) { ran << :global_after }
              end
              example_group do
                before(:context) { ran << :before }
                after(:context) { ran << :after }
                example { ran << :example }
                example { ran << :example }
                example { ran << :example }
              end
              check_report(passed: 3)
              assert_equal %i[global_before before example example example after global_after], ran
            end

            describe ":suite scope" do
              it "can add #before/#after hooks" do
                ran = []
                configure do |config|
                  config.before(:suite) { ran << :global_before }
                  config.after(:suite) { ran << :global_after }
                end
                example_group do
                  before { ran << :before }
                  after { ran << :after }
                  example { ran << :example }
                  example { ran << :example }
                  example_group do
                    example { ran << :example }
                  end
                end
                check_report(passed: 3)
                assert_equal %i[global_before
                                before example after
                                before example after
                                before example after
                                global_after],
                             ran
              end

              it "can add #around hooks" do
                ran = []
                configure do |config|
                  config.around(:suite) { |h| ran << :global_pre; h.run; ran << :global_post }
                end
                example_group do
                  before { ran << :before }
                  after { ran << :after }
                  example { ran << :example }
                  example_group do
                    example_group do
                      example { ran << :example }
                    end
                  end
                  example { ran << :example }
                end
                check_report(passed: 3)
                assert_equal %i[global_pre
                                before example after
                                before example after
                                before example after
                                global_post],
                             ran
              end
            end
          end
        end
      end
    end

    describe "#shared_examples/#shared_context" do
      it "can access example group's \"let\" method from shared examples block" do
        seen = nil
        example_group do
          shared_examples "test" do
            example { seen = test }
          end
          let(:test) { 123 }
          include_examples "test"
        end
        check_report(passed: 1)
        assert_equal 123, seen
      end

      it "can access parent example group's \"let\" method from shared examples block" do
        seen = nil
        example_group do
          shared_examples "test" do
            example { seen = test }
          end
          let(:test) { 123 }
          example_group do
            include_examples "test"
          end
        end
        check_report(passed: 1)
        assert_equal 123, seen
      end

      it "can access overridden example group's \"let\" method from shared examples block" do
        seen = nil
        example_group do
          shared_examples "test" do
            example { seen = test }
          end
          let(:test) { 123 }
          example_group do
            let(:test) { 456 }
            include_examples "test"
          end
        end
        check_report(passed: 1)
        assert_equal 456, seen
      end

      it "supports global shared examples block" do
        seen = nil
        rspec.shared_examples "test" do
          example { seen = test }
        end
        example_group do
          include_examples "test"
          let(:test) { 123 }
        end
        check_report(passed: 1)
        assert_equal 123, seen
      end

      it "can use \"let\" method from shared context block in the example group" do
        seen = nil
        example_group do
          shared_context "test" do
            let(:test) { 123 }
          end
          example_group do
            include_context "test"
            example { seen = test }
          end
        end
        check_report(passed: 1)
        assert_equal 123, seen
      end

      it "example group uses hooks from shared context hook" do
        ran = []
        example_group do
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
        check_report(passed: 1)
        assert_equal %i[around_pre before example after around_post], ran
      end
    end

    describe "#it_behaves_like" do
      it "does not override \"let\" method in example group" do
        seen1 = seen2 = seen3 = seen4 = nil
        example_group do
          shared_examples "test" do
            let(:test2) { 456 }
            example { seen1 = test1 }
            example { seen2 = test2 }
          end
          let(:test1) { 123 }
          let(:test2) { 789 }
          it_behaves_like "test"
          example { seen3 = test1 }
          example { seen4 = test2 }
        end
        check_report(passed: 4)
        assert_equal [123, 456, 123, 789], [seen1, seen2, seen3, seen4]
      end
    end

    describe "SharedContext modules" do
      def shared_context_module(&)
        this = self
        Module.new do
          extend this.rspec::SharedContext
          module_eval(&)
        end
      end

      it "includes example of the module" do
        ran = 0
        m = shared_context_module { example { ran += 1 } }
        example_group { include m }
        check_report(passed: 1)
        assert_equal 1, ran
      end

      it "includes example group of the module" do
        ran = 0
        m = shared_context_module { example_group { example { ran += 1 } } }
        example_group { include m }
        check_report(passed: 1)
        assert_equal 1, ran
      end

      it "includes example of the module through another module" do
        ran = 0
        m1 = shared_context_module { example { ran += 1 } }
        m2 = shared_context_module { include m1 }
        example_group { include m2 }
        check_report(passed: 1)
        assert_equal 1, ran
      end

      describe "hooks" do
        it "includes #before/#after hooks of the module" do
          ran = []
          m = shared_context_module do
            before { ran << :before }
            after { ran << :after }
          end
          example_group do
            include m
            example { ran << :example }
          end
          check_report(passed: 1)
          assert_equal %i[before example after], ran
        end

        it "merges #before/#after hooks of the module with already existing hooks" do
          ran = []
          m = shared_context_module do
            before { ran << :shared_before }
            after { ran << :shared_after }
          end
          example_group do
            before { ran << :main_before }
            example { ran << :example }
            after { ran << :main_after }
            include m
          end
          check_report(passed: 1)
          assert_equal %i[main_before shared_before example shared_after main_after], ran
        end

        it "merges already existing #before/#after hooks with those of the module" do
          ran = []
          m = shared_context_module do
            before { ran << :shared_before }
            after { ran << :shared_after }
          end
          example_group do
            include m
            before { ran << :main_before }
            example { ran << :example }
            after { ran << :main_after }
          end
          check_report(passed: 1)
          assert_equal %i[shared_before main_before example main_after shared_after], ran
        end

        it "includes #before/#after hooks of the module through another module" do
          ran = []
          m1 = shared_context_module do
            before { ran << :before }
            after { ran << :after }
          end
          m2 = shared_context_module do
            include m1
          end
          example_group do
            include m2
            example { ran << :example }
          end
          check_report(passed: 1)
          assert_equal %i[before example after], ran
        end

        it "includes #around hooks of the module" do
          ran = []
          m = shared_context_module do
            around { |h| ran << :around_pre; h.run; ran << :around_post }
          end
          example_group do
            include m
            example { ran << :example }
          end
          check_report(passed: 1)
          assert_equal %i[around_pre example around_post], ran
        end

        it "merges #around hooks of the module with already existing hooks" do
          ran = []
          m = shared_context_module do
            around { |h| ran << :shared_around_pre; h.run; ran << :shared_around_post }
          end
          example_group do
            around { |h| ran << :main_around_pre; h.run; ran << :main_around_post }
            include m
            example { ran << :example }
          end
          check_report(passed: 1)
          assert_equal %i[main_around_pre shared_around_pre example shared_around_post main_around_post], ran
        end

        it "merges already existing #around hooks with those of the module" do
          ran = []
          m = shared_context_module do
            around { |h| ran << :shared_around_pre; h.run; ran << :shared_around_post }
          end
          example_group do
            include m
            around { |h| ran << :main_around_pre; h.run; ran << :main_around_post }
            example { ran << :example }
          end
          check_report(passed: 1)
          assert_equal %i[shared_around_pre main_around_pre example main_around_post shared_around_post], ran
        end
      end

      %i[including included].each do |which|
        it "makes helper methods available in the #{which} module" do
          ran = []
          m = shared_context_module do
            define_method(:test1) { ran << :test1 }
            let(:test2) { ran << :test2 }
            example { 2.times { test1; test2; test3; test4 } } if which == :included
          end
          example_group do
            define_method(:test3) { ran << :test3 }
            include m
            let(:test4) { ran << :test4 }
            example { 2.times { test1; test2; test3; test4 } } if which == :including
          end
          check_report(passed: 1)
          assert_equal %i[test1 test2 test3 test4 test1 test3], ran
        end
      end
    end

    describe "configuration" do
      describe "#expect_with" do
        %i[minitest test_unit].each do |expect_with_name|
          describe expect_with_name.to_s do
            before { configure { |config| config.expect_with expect_with_name } }

            it "can do simple assertions" do
              rspec.describe "something" do
                it("can pass") { assert true }
                it("can skip") { skip }
                it("can fail") { assert false }
              end
              check_report(passed: 1, failed: 1, skipped: 1, asserts: 2)
            end

            describe "#assert_golden" do
              let(:golden_store) { GoldenMaster::Store.new }
              let(:runner) { runner_class.new(golden_store:) }

              # one nil for the outer TestSuite
              def golden_key(labels, per_example_key = nil) = [[nil, :rspec, *labels], per_example_key]

              context "without golden value" do
                before do
                  example_group do
                    example("test") { assert_golden 123 }
                  end
                end

                it "passes" do
                  check_report(passed: 1)
                end

                it "does not count assertion" do
                  check_report(passed: 1, asserts: 0)
                end

                it "warns" do
                  report
                  assert_predicate report.each_test_case_result.first[1], :captured_stderr?
                end

                it "stores trial values" do
                  report
                  golden_store.accept_trial
                  assert_equal 123, golden_store.get_golden(golden_key([nil, "test"]))
                end
              end

              context "with golden value" do
                before do
                  golden_store.set_trial(golden_key([nil, "test"]), 123)
                  golden_store.accept_trial
                end

                context "with correct trial value" do
                  before do
                    example_group do
                      example("test") { assert_golden 123 }
                    end
                  end

                  it "passes" do
                    check_report(passed: 1)
                  end

                  it "counts assertion" do
                    check_report(passed: 1, asserts: 1)
                  end

                  it "stores the same trial value" do
                    report
                    golden_store.accept_trial
                    assert_equal 123, golden_store.get_golden(golden_key([nil, "test"]))
                  end

                  it "does not warn" do
                    report
                    assert_empty report.each_test_case_result.filter { |_, tr| tr.captured_stderr? }
                  end
                end

                context "with incorrect trial value" do
                  before do
                    example_group do
                      example("test") { assert_golden 456 }
                    end
                  end

                  it "fails" do
                    check_report(failed: 1)
                  end

                  it "counts assertion" do
                    check_report(failed: 1, asserts: 1)
                  end

                  it "stores new trial value" do
                    report
                    golden_store.accept_trial
                    assert_equal 456, golden_store.get_golden(golden_key([nil, "test"]))
                  end

                  it "does not warn" do
                    report
                    assert_empty report.each_test_case_result.filter { |_, tr| tr.captured_stderr? }
                  end
                end

                it "can distinguish per-example keys" do
                  golden_store.set_trial(golden_key([nil, "test"], :a), 123)
                  golden_store.set_trial(golden_key([nil, "test"], :b), 456)
                  golden_store.set_trial(golden_key([nil, "test"], :c), 789)
                  golden_store.accept_trial
                  done = nil
                  example_group do
                    example("test") do
                      assert_golden 123, key: :a
                      assert_golden 456, key: :b
                      assert_golden 789, key: :c
                      done = true
                    end
                  end
                  check_report(passed: 1, asserts: 3)
                  assert done
                  golden_store.accept_trial
                  assert_equal 123, golden_store.get_golden(golden_key([nil, "test"], :a))
                  assert_equal 456, golden_store.get_golden(golden_key([nil, "test"], :b))
                  assert_equal 789, golden_store.get_golden(golden_key([nil, "test"], :c))
                end
              end
            end
          end
        end

        describe "rspec" do
          before { configure { |config| config.expect_with :rspec } }

          it "can run simple test suite" do
            example_group do
              it("can pass") { expect('a').to eq('a') }
              skip("can skip") { expect('a').to eq('b') }
              it("can fail") { expect('a').to eq('b') }
            end
            check_report(passed: 1, skipped: 1, failed: 1, asserts: 2)
          end

          describe "#is_expected" do
            it "passes" do
              example_group do
                subject { 123 }
                it { is_expected.to eq(123) }
              end
              check_report(passed: 1, asserts: 1)
            end
          end

          describe "#should" do
            it "passes" do
              example_group do
                subject { 123 }
                it { should eq(123) }
              end
              check_report(passed: 1, asserts: 1)
            end
          end

          describe "#should_not" do
            it "passes" do
              example_group do
                subject { 123 }
                it { should_not eq(456) }
              end
              check_report(passed: 1, asserts: 1)
            end
          end
        end
      end

      describe "#mock_with" do
        describe "rspec" do
          before { configure { |config| config.mock_with :rspec } }

          it "can run simple test suite" do
            example_group do
              example("can pass") { o = double; expect(o).to receive(:test); o.test }
              example("can skip") { o = double; expect(o).to receive(:test); skip }
              pending("can pend") { o = double; expect(o).to receive(:test) }
              example("can fail") { o = double; expect(o).to receive(:test) }
            end
            check_report(passed: 1, skipped: 2, failed: 1)
          end

          it "can create double object in #before hook" do
            example_group do
              before { @o = double }
              example("can pass") { expect(@o).to receive(:test); @o.test }
              example("can skip") { expect(@o).to receive(:test); skip }
              pending("can pend") { expect(@o).to receive(:test) }
              example("can fail") { expect(@o).to receive(:test) }
            end
            check_report(passed: 1, skipped: 2, failed: 1)
          end
        end
      end

      describe "#include" do
        it "can include module with helper method" do
          ran = 0
          m = Module.new do
            define_method(:helper) { ran += 1 }
          end
          configure do |config|
            config.include(m)
          end
          example_group do
            example { helper }
            example_group do
              example { helper }
            end
          end
          check_report(passed: 2)
          assert_equal 2, ran
        end

        it "can include module with metadata filter" do
          seen = []
          m = Module.new do
            define_method(:helper) { }
          end
          configure do |config|
            config.include(m, :tag)
          end
          example_group do
            example_group(tag: true) do
              example { seen[0] = respond_to?(:helper) }
              example(tag: false) { seen[1] = respond_to?(:helper) } # NOTE: inherited
            end
            example_group do
              example { seen[2] = respond_to?(:helper) }
            end
            example(tag: true) { seen[3] = respond_to?(:helper) }
            example { seen[4] = respond_to?(:helper) }
          end
          check_report(passed: 5)
          assert_equal [true, true, false, true, false], seen
        end
      end

      describe "#include_context" do
        it "can include shared context with helper method with metadata filter" do
          configure do |config|
            config.include_context("shared", :tag)
          end
          seen = []
          example_group do
            shared_context "shared" do
              let(:helper) { }
            end
            example(tag: true) { seen[0] = respond_to?(:helper) }
            example { seen[1] = respond_to?(:helper) }
            example_group(tag: true) do
              example { seen[2] = respond_to?(:helper) }
            end
          end
          check_report(passed: 3)
          assert_equal [true, false, true], seen
        end

        it "can include shared context with hooks with metadata filter" do
          configure do |config|
            config.include_context("shared", :tag)
          end
          ran = []
          example_group do
            shared_context "shared" do
              around { |h| ran << :around_pre; h.run; ran << :around_post }
            end
            example(nil, :tag) { ran << :example }
          end
          check_report(passed: 1)
          assert_equal %i[around_pre example around_post], ran
        end

        it "can override helper method" do
          configure do |config|
            config.include_context("shared", :tag)
          end
          seen = []
          example_group do
            shared_context "shared" do
              let(:test1) { 123 }
              let(:test2) { test1 }
              let(:test3) { 456 }
            end
            example_group do
              example_group(nil, :tag) do
                example { seen[0] = [test1, test2, test3] }
              end
              example(nil, :tag) { seen[1] = [test1, test2, test3] }
              example_group do
                let(:test1) { 789 } # gets overridden
                example(nil, :tag) { seen[2] = [test1, test2, test3] }
                example_group(nil, :tag) do
                  example { seen[3] = [test1, test2, test3] }
                end
              end
              example_group(nil, :tag) do
                let(:test1) { 789 } # overrides
                example(nil, :tag) { seen[4] = [test1, test2, test3] }
                example_group(nil, :tag) do
                  example { seen[5] = [test1, test2, test3] }
                  example(nil, tag: false) { seen[6] = [test1, test2, test3] }
                end
              end
            end
          end
          check_report(passed: 7)
          assert_equal [[123, 123, 456],
                        [123, 123, 456],
                        [123, 123, 456],
                        [123, 123, 456],
                        [789, 789, 456],
                        [789, 789, 456],
                        [789, 789, 456]], seen
        end
      end

      describe "#when_first_matching_example_defined" do
        it "invokes block on first matching example" do
          ran = []
          configure do |config|
            config.when_first_matching_example_defined(test: 456) { ran << :matched }
          end
          example_group do
            ran << :def1
            example(nil, :test)
            ran << :def2
            example(nil, test: 123, abc: 456)
            ran << :def3
            example(nil, abc: 123, test: 456)
            ran << :def4
            example(nil, test: 456)
          end
          check_report(skipped: 4)
          assert_equal %i[def1 def2 def3 matched def4], ran
        end
      end

      describe "#on_example_group_definition" do
        it "invokes block on for each created example group" do
          all = []
          got = []
          configure do |config|
            config.on_example_group_definition { |eg| got << eg }
          end
          all[0] = example_group do
            example
            all[1] = example_group { example }
            example
          end
          assert_equal all, got
        end
      end

      describe "#filter_run_including/#filter_run_excluding" do
        it "runs only the examples matching an inclusion filter" do
          configure do |config|
            config.filter_run_including(:tag)
          end
          ran = []
          example_group do
            example(nil) { ran << 1 }
            example(nil, :tag) { ran << 2 }
            example(nil) { ran << 3 }
            example_group(nil, :tag) do
              example { ran << 4 }
              example(nil, tag: false) { ran << 5 }
              example_group(tag: false) do
                example(nil, :tag) { ran << 6 }
              end
            end
          end
          check_report(passed: 3)
          assert_equal [2, 4, 6], ran.sort
        end

        it "runs everything except the examples matching an exclusion filter" do
          configure do |config|
            config.filter_run_excluding(:tag)
          end
          ran = []
          example_group do
            example(nil) { ran << 1 }
            example(nil, :tag) { ran << 2 }
            example(nil) { ran << 3 }
          end
          check_report(passed: 2)
          assert_equal [1, 3], ran.sort
        end

        it "runs only the examples matching an inclusion filter and not matching an exclusion filter" do
          configure do |config|
            config.filter_run_including(:a)
            config.filter_run_excluding(:b)
          end
          ran = []
          example_group do
            example(nil, :a) { ran << 1 }
            example(nil, :a, :b) { ran << 2 }
            example(nil, :b) { ran << 3 }
            example(nil) { ran << 4 }
            example(nil, :a, :c) { ran << 5 }
            example(nil, :b, :c) { ran << 4 }
          end
          check_report(passed: 2)
          assert_equal [1, 5], ran.sort
        end
      end

      describe "#filter_run_when_matching" do
        before { configure { |config| config.filter_run_when_matching(:tag) } }

        it "runs only the matching examples when there are matching examples" do
          ran = []
          example_group do
            example(nil, :test) { ran << 1 }
            example(nil, :tag) { ran << 2 }
            example(nil) { ran << 3 }
          end
          check_report(passed: 1)
          assert_equal [2], ran.sort
        end

        it "runs all examples when there are no matching examples" do
          ran = []
          example_group do
            example(nil) { ran << 1 }
            example(nil, :test) { ran << 2 }
            example(nil) { ran << 3 }
          end
          check_report(passed: 3)
          assert_equal [1, 2, 3], ran.sort
        end
      end

      describe "#run_all_when_everything_filtered" do
        it "runs only the matching examples when there are any" do
          configure do |config|
            config.filter_run_including(:tag)
            config.run_all_when_everything_filtered = true
          end
          ran = []
          example_group do
            example(nil) { ran << 1 }
            example(nil, :tag) { ran << 2 }
            example(nil) { ran << 3 }
          end
          check_report(passed: 1)
          assert_equal [2], ran.sort
        end

        it "ignores inclusion filter when all examples would be filtered" do
          configure do |config|
            config.filter_run_including(:tag)
            config.filter_run_excluding(:test)
            config.run_all_when_everything_filtered = true
          end
          ran = []
          example_group do
            example(nil) { ran << 1 }
            example(nil, :test) { ran << 2 }
            example(nil, :tag, :test) { ran << 3 }
          end
          check_report(passed: 1)
          assert_equal [1], ran.sort
        end
      end
    end
  end
end
