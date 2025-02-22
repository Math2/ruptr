# frozen_string_literal: true

require 'rspec/mocks'

require_relative '../adapters'
require_relative 'rspec_expect'

module Ruptr
  module Adapters::RSpecMocks
    include TestInstance
    # NOTE: On inclusion, RSpec::Mocks::ExampleMethods will define its own restricted variant of the
    # #expect method if it is not already defined in the including module.  Thus, always include
    # RSpec::Matchers (via Adapters::RSpecExpect) first to get the real #expect method.
    include Adapters::RSpecExpect
    include ::RSpec::Mocks::ExampleMethods

    def ruptr_wrap_test_instance
      super do
        ::RSpec::Mocks.setup
        begin
          yield
          ::RSpec::Mocks.verify
        ensure
          ::RSpec::Mocks.teardown
        end
      end
    end
  end
end
