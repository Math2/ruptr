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
    # Test::Unit::CoreAssertions (gem test-unit-ruby-core) which accesses it directly.

    def ruptr_assertions_count
      @_assertions || 0
    end

    def ruptr_assertions_count=(n)
      @_assertions = n
    end

    def ruptr_ineffective_assertions_count
      @ruptr_ineffective_assertions_count || 0
    end

    def ruptr_ineffective_assertions_count=(n)
      @ruptr_ineffective_assertions_count = n
    end

    def ruptr_internal_variable?(name)
      name == :@_assertions || name == :@ruptr_ineffective_assertions_count || name == :@ruptr_context
    end

    private def ruptr_update_context
      ruptr_context.assertions_count += ruptr_assertions_count
      ruptr_context.ineffective_assertions_count += ruptr_ineffective_assertions_count
    end

    def ruptr_wrap_test_instance
      yield
    ensure
      ruptr_update_context
    end

    def inspect = "#<#{self.class}: #{ruptr_context.test_element}>"
  end
end
