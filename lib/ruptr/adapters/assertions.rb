# frozen_string_literal: true

require_relative '../assertions'
require_relative '../exceptions'
require_relative '../adapters'
require_relative '../stringified'

module Ruptr
  class Assertions::AssertionError
    include AssertionErrorMixin
  end

  class Assertions::SkippedException
    include SkippedExceptionMixin
  end

  module Adapters::RuptrAssertions
    include TestInstance
    include Ruptr::Assertions

    def bump_assertions_count = self.ruptr_assertions_count += 1
    def passthrough_exception?(ex) = ex.is_a?(SkippedExceptionMixin) || super
    def assertion_exception?(ex) = ex.is_a?(AssertionErrorMixin) || super

    def assertion_capture_value(v) = Stringified.from(v)

    def assertions_golden_store = ruptr_context.runner.golden_store

    def assertion_golden_key(k) = [ruptr_context.test_element.path_identifiers, k]

    def assertion_set_golden_trial_value(k, v)
      assertions_golden_store.set_trial(assertion_golden_key(k), v)
    end

    def assertion_golden_value_missing(_k)
      self.ruptr_ineffective_assertions_count += 1
    end

    def assertion_yield_golden_value(k)
      yield assertions_golden_store.get_golden(assertion_golden_key(k)) { return assertion_golden_value_missing(k) }
    end
  end
end
