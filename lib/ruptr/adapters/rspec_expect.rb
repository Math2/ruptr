# frozen_string_literal: true

require 'rspec/expectations'

require_relative '../adapters'

module Ruptr
  module Adapters::RSpecExpect
    include TestInstance
    include ::RSpec::Matchers

    def expect(...)
      ruptr_context.bump_assertions_count
      super
    end

    module Helpers
      def should(matcher, message = nil)
        ruptr_context.bump_assertions_count
        ::RSpec::Expectations::PositiveExpectationHandler.handle_matcher(subject, matcher, message)
      end

      def should_not(matcher, message = nil)
        ruptr_context.bump_assertions_count
        ::RSpec::Expectations::NegativeExpectationHandler.handle_matcher(subject, matcher, message)
      end

      def subject = nil
      def is_expected = expect(subject)
    end
  end
end
