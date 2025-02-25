# frozen_string_literal: true

require_relative 'spec_helper'
require 'ruptr/runner'
require 'ruptr/formatter'
require 'ruptr/plain'
require 'ruptr/tabular'
require 'ruptr/tap'
require 'ruptr/assertions'

module Ruptr
  RSpec.describe Formatter do
    # For now, this pretty much just does golden master testing...

    shared_examples "a formatter" do
      shared_examples "a formatter with its output" do
        it "renders with a valid encoding" do
          assert_predicate output, :valid_encoding?
        end

        if method_defined?(:assert_golden)
          it "renders to the same thing as before" do
            puts output
            assert_golden output
          end
        end
      end

      context "with no results" do
        context "without an expected number of test cases in the header" do
          before { formatter.submit_plan { } }

          it_behaves_like "a formatter with its output"
        end

        context "with an expected number of test cases in the header" do
          before { formatter.submit_plan({ planned_test_case_count: 0 }) { } }

          it_behaves_like "a formatter with its output"
        end
      end

      # TODO: user_time/system_time/assertions

      context "with a single passed test case" do
        before do
          formatter.submit_plan do
            formatter.submit_case(TestCase.new("Test!"), TestResult.new(:passed))
          end
        end

        it_behaves_like "a formatter with its output"
      end

      context "with a single failed test case" do
        {
          "a nil exception" => nil,
          "a bare surrogate exception" => SurrogateException.new,
          "a surrogate exception with a message" => SurrogateException.new("Failed!"),
          "a surrogate exception with a backtrace" => SurrogateException.new(backtrace: %w[a b c]),
          "a surrogate exception with an original class name" =>
            SurrogateException.new(original_class_name: 'OriginalException'),
          "a surrogate exception with a detailed message" =>
            SurrogateException.new(detailed_message: "Blah blah blah"),
          "a surrogate exception with a highlighted detailed message" =>
            SurrogateException.new(highlighted_detailed_message: "\e[1mBlah blah blah\e[m"),
          "a bare exception" => Exception.new,
          "an exception with a message" => Exception.new("Failed!"),
        }.each_pair do |description, exception|
          context "with #{description}" do
            before do
              formatter.submit_plan do
                formatter.submit_case(TestCase.new("Test!"), TestResult.new(:failed, exception:))
              end
            end

            it_behaves_like "a formatter with its output"
          end
        end
      end

      context "with a single skipped test case" do
        {
          "a nil exception" => nil,
          "a StandardError exception (shouldn't happen...)" => StandardError.new,
          "a SkippedException exception" => SkippedException.new,
          "a SkippedException exception with a message" => SkippedException.new("Skipped!"),
          "a PendingSkippedException exception" => PendingSkippedException.new,
          "a PendingSkippedException exception with a message" => PendingSkippedException.new("Pending!"),
        }.each_pair do |description, exception|
          context "with #{description}" do
            before do
              formatter.submit_plan do
                formatter.submit_case(TestCase.new("Test!"), TestResult.new(:skipped, exception:))
              end
            end

            it_behaves_like "a formatter with its output"
          end
        end
      end

      context "with a single warned test case" do
        before do
          formatter.submit_plan do
            formatter.submit_case(TestCase.new("Test!"),
                                  TestResult.new(:passed, captured_stderr: "Warning message!\n"))
          end
        end

        it_behaves_like "a formatter with its output"
      end

      context "with a single blocked test case" do
        before do
          formatter.submit_plan do
            formatter.submit_case(TestCase.new("Test!"), TestResult.new(:blocked))
          end
        end

        it_behaves_like "a formatter with its output"
      end

      # TODO: test groups errors/warnings, blocked test cases

      # TODO: test uninspectable/unmarshallable values

      describe "assertion diff" do
        [
          [123, 456],
          ["test", "test\n"],
          ["test".b, "test\n".b],
          ["a\nb\nc\nd\ne\n", "a!\nb\nd\ne"],
        ].each_with_index do |(expected, actual), index|
          context "with pair ##{index} (expected: #{expected.inspect}, actual: #{actual.inspect})" do
            before do
              exception = Assertions::EquivalenceAssertionError.new(
                "expected #{actual.inspect} to be #{expected.inspect}", actual:, expected:
              )
              formatter.submit_plan do
                formatter.submit_case(TestCase.new("diff test"), TestResult.new(:failed, exception:))
              end
            end

            it_behaves_like "a formatter with its output"
          end
        end
      end
    end

    shared_context "with formatter StringIO output" do
      let(:string_io) { StringIO.new }
      let(:output) { string_io.string }
    end

    describe Formatter::Plain do
      include_context "with formatter StringIO output"

      (-3..4).each do |verbosity|
        context "with verbosity #{verbosity}" do
          context "without colorizer" do
            let(:formatter) { described_class.new(string_io, verbosity:) }
            it_behaves_like "a formatter"
          end

          [TTYColors::ANSICodes.new].each do |colorizer|
            context "with colorizer #{colorizer.class.name}" do
              let(:formatter) { described_class.new(string_io, verbosity:, colorizer:) }
              it_behaves_like "a formatter"
            end
          end
        end
      end
    end

    describe Formatter::TAP do
      include_context "with formatter StringIO output"

      let(:formatter) { described_class.new(string_io) }

      it_behaves_like "a formatter"
    end

    describe Formatter::Tabular do
      include_context "with formatter StringIO output"

      let(:formatter) { described_class.new(string_io) }

      it_behaves_like "a formatter"
    end
  end
end
