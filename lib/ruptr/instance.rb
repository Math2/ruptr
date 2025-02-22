# frozen_string_literal: true

module Ruptr
  module TestInstance
    def ruptr_initialize_test_instance(context)
      @ruptr_context = context
    end

    attr_reader :ruptr_context

    def ruptr_test_element = ruptr_context.test_element

    # Common methods to let multiple assertions/expectations libraries use a shared assertions
    # counter.  The @_assertions instance variable name was chosen to be compatible with
    # Test::Unit::Assertions::CoreAssertions which accesses it directly.

    def ruptr_assertions_count
      @_assertions || 0
    end

    def ruptr_assertions_count=(n)
      @_assertions = n
    end

    def ruptr_internal_variable?(name)
      name == :@_assertions || name == :@ruptr_context
    end

    def ruptr_wrap_test_instance
      yield
    ensure
      ruptr_context.assertions_count += ruptr_assertions_count
    end

    def inspect = "#<#{self.class}: #{ruptr_context.test_element}>"
  end
end
