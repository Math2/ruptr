# frozen_string_literal: true

require_relative 'test_helpers'
require 'minitest/autorun'
require 'ruptr/suite'

module Ruptr
  module Tests
    class SuiteTests < Minitest::Test
      def test_1
        tg = TestGroup.new
        tc = TestCase.new
        tg.add_test_case(tc)
        assert_equal [tc], tg.each_test_element.to_a
        assert_equal [tc], tg.each_test_case.to_a
        assert_equal [], tg.each_test_subgroup.to_a
        assert_equal [tg, tc], tg.each_test_element_recursive.to_a
        assert_equal [tc], tg.each_test_case_recursive.to_a
        assert_equal [tg], tg.each_test_group_recursive.to_a
        assert_equal [], tg.each_test_subgroup_recursive.to_a
        assert_equal 2, tg.count_test_elements
        assert_equal 1, tg.count_test_cases
        assert_equal 1, tg.count_test_groups
        assert_equal 0, tg.count_test_subgroups
        tg.filter_recursive! { false }
        assert_equal [], tg.each_test_element.to_a
        assert_equal [], tg.each_test_case.to_a
        assert_equal [], tg.each_test_subgroup.to_a
        assert_equal [tg], tg.each_test_element_recursive.to_a
        assert_equal [], tg.each_test_case_recursive.to_a
        assert_equal [tg], tg.each_test_group_recursive.to_a
        assert_equal [], tg.each_test_subgroup_recursive.to_a
        assert_equal 1, tg.count_test_elements
        assert_equal 0, tg.count_test_cases
        assert_equal 1, tg.count_test_groups
        assert_equal 0, tg.count_test_subgroups
      end
    end
  end
end
