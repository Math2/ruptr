# frozen_string_literal: true

module Ruptr
  # Methods that can be used (or extended) by assertions/expectations/mocking/etc adapters that are
  # included in test class instances to integrate with the framework.
  module TestInstance
    def ruptr_initialize_test_instance(context)
      @ruptr_context = context
    end

    attr_reader :ruptr_context

    def ruptr_test_element = ruptr_context.test_element

    def ruptr_internal_variable?(name)
      name == :@ruptr_context
    end

    def ruptr_wrap_test_instance = yield

    def inspect = "#<#{self.class}: #{ruptr_context.test_element}>"
  end
end
