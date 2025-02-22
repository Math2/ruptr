# frozen_string_literal: true

require 'rr'

require_relative '../adapters'

module Ruptr
  module Adapters::RR
    include TestInstance

    def ruptr_wrap_test_instance
      super do
        ::RR.reset
        begin
          yield
          ::RR.verify
        ensure
          ::RR.reset
        end
      end
    end
  end
end
