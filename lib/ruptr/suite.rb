# frozen_string_literal: true

module Ruptr
  class TestElement
    DEFAULT_TAGS = {}.freeze

    def initialize(label = nil, identifier: label, tags: DEFAULT_TAGS, &block)
      @parent = nil
      @label = label
      @identifier = identifier
      @tags = tags
      @block = block
    end

    attr_accessor :label, :identifier, :tags, :block

    attr_reader :parent

    def orphan? = @parent.nil?

    def reparent!(new_parent)
      fail "already has a parent" if new_parent && @parent
      @parent = new_parent
      @description = nil
    end

    def orphanize! = reparent!(nil)

    def description
      return label.nil? ? '' : label if orphan?
      @description ||= if label.nil?
                         parent.description
                       elsif parent.description.empty?
                         label
                       else
                         "#{parent.description} #{label}"
                       end
    end

    def each_parent_and_self(&)
      return to_enum __method__ unless block_given?
      parent.each_parent_and_self(&) unless orphan?
      yield self
    end

    def path_labels = each_parent_and_self.map(&:label)
    def path_identifiers = each_parent_and_self.map(&:identifier)

    def test_case? = false
    def test_group? = false

    def block? = !@block.nil?

    def initialize_dup(_)
      super
      orphanize!
    end

    def to_s = "#<#{self.class}: #{description.inspect}>"
  end

  class TestCase < TestElement
    def test_case? = true

    def run_context(context) = @block.call(context)
  end

  class TestGroup < TestElement
    def initialize(...)
      super
      @test_cases = []
      @test_subgroups = []
    end

    def test_group? = true

    def wrap_context(context, &) = @block.call(context, &)

    def each_test_case(&) = @test_cases.each(&)
    def each_test_subgroup(&) = @test_subgroups.each(&)

    def each_test_element(&)
      return to_enum __method__ unless block_given?
      each_test_case(&)
      each_test_subgroup(&)
    end

    def each_test_element_recursive(&)
      return to_enum __method__ unless block_given?
      yield self
      each_test_case(&)
      each_test_subgroup { |tg| tg.each_test_element_recursive(&) }
    end

    def each_test_case_recursive(&)
      return to_enum __method__ unless block_given?
      each_test_case(&)
      each_test_subgroup { |tg| tg.each_test_case_recursive(&) }
    end

    def each_test_group_recursive(&)
      return to_enum __method__ unless block_given?
      yield self
      each_test_subgroup do |tg|
        yield tg
        tg.each_test_subgroup_recursive(&)
      end
    end

    def each_test_subgroup_recursive(&)
      return to_enum __method__ unless block_given?
      each_test_subgroup do |tg|
        yield tg
        tg.each_test_subgroup_recursive(&)
      end
    end

    def count_test_elements(&) = each_test_element_recursive.count(&)
    def count_test_cases(&) = each_test_case_recursive.count(&)
    def count_test_groups(&) = each_test_group_recursive.count(&)
    def count_test_subgroups(&) = each_test_subgroup_recursive.count(&)

    def empty? = @test_cases.empty? && @test_subgroups.empty?

    def clear_test_cases
      @test_cases.each(&:orphanize!)
      @test_cases.clear
    end

    def clear_test_subgroups
      @test_subgroups.each(&:orphanize!)
      @test_subgroups.clear
    end

    def add_test_case(tc)
      tc.reparent!(self)
      @test_cases << tc
    end

    def add_test_subgroup(tg)
      tg.reparent!(self)
      @test_subgroups << tg
    end

    def add_test_element(te)
      case
      when te.test_case? then add_test_case(te)
      when te.test_group? then add_test_subgroup(te)
      else raise ArgumentError
      end
    end

    def filter_recursive!(&)
      @test_cases.filter!(&)
      @test_subgroups.filter! do |tg|
        if yield tg
          tg.filter_recursive!(&)
          true
        end
      end
    end

    def filter_recursive(&)
      dup.tap { |tg| tg.filter_recursive!(&) }
    end

    def filter_test_cases_recursive(&)
      filter_recursive { |te| !te.test_case? || yield(te) }
    end

    def initialize_dup(_)
      super
      @test_cases = @test_cases.map { |tc| tc.dup.tap { |tc| tc.reparent!(self) } }
      @test_subgroups = @test_subgroups.map { |tc| tc.dup.tap { |tc| tc.reparent!(self) } }
    end

    def freeze
      @test_cases.each(&:freeze)
      @test_subgroups.each(&:freeze)
      @test_cases.freeze
      @test_subgroups.freeze
      super
    end
  end

  class TestSuite < TestGroup
  end
end
