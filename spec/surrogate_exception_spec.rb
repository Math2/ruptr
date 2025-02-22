# frozen_string_literal: true

require_relative 'spec_helper'
require 'ruptr/surrogate_exception'

module Ruptr
  RSpec.describe SurrogateException do
    subject { described_class.from(original_exception) }

    let(:original_exception) do
      begin
        raise StandardError.new("Inner exception").tap { |ex| ex.set_backtrace(["abc:123", "def:456", "ghi:789"]) }
      rescue StandardError
        begin
          raise StandardError.new("Middle exception").tap { |ex| ex.set_backtrace(["test"]) }
        rescue StandardError
          raise StandardError.new("Outer exception").tap { |ex| ex.set_backtrace(["foo:451", "bar:1997"]) }
        end
      end
    rescue
      $!
    end

    it "has chained cause exceptions" do
      refute_nil subject.cause
      refute_nil subject.cause.cause
      assert_nil subject.cause.cause.cause
    end

    it "has the same messages" do
      assert_equal "Outer exception", subject.message
      assert_equal "Middle exception", subject.cause.message
      assert_equal "Inner exception", subject.cause.cause.message
    end

    it "remembers the original class name" do
      assert_equal 'StandardError', subject.original_class_name
      assert_equal 'StandardError', subject.cause.original_class_name
      assert_equal 'StandardError', subject.cause.cause.original_class_name
    end

    describe "#full_message" do
      if method_defined?(:assert_golden)
        [false, true].each do |highlight|
          describe "#{highlight ? "with" : "without"} highlight" do
            it "did not change" do
              assert_golden subject.full_message(highlight:)
            end
          end
        end
      end
    end
  end
end
