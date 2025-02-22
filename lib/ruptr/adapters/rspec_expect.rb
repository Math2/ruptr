# frozen_string_literal: true

require 'rspec/expectations'

require_relative '../adapters'

module Ruptr
  module Adapters::RSpecExpect
    include TestInstance
    include ::RSpec::Matchers

    def expect(...)
      self.ruptr_assertions_count += 1
      super
    end

    module Helpers
      def should(matcher, message = nil)
        self.ruptr_assertions_count += 1
        ::RSpec::Expectations::PositiveExpectationHandler.handle_matcher(subject, matcher, message)
      end

      def should_not(matcher, message = nil)
        self.ruptr_assertions_count += 1
        ::RSpec::Expectations::NegativeExpectationHandler.handle_matcher(subject, matcher, message)
      end

      def subject = nil
      def is_expected = expect(subject)
    end
  end
end
