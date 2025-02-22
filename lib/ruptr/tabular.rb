# frozen_string_literal: true

require_relative 'formatter'
require_relative 'result'

module Ruptr
  class Formatter::Tabular < Formatter
    self.formatter_name = :tabular

    private

    def initialize(output, **opts)
      super(**opts)
      @output = output
    end

    def finish_element(te, tr)
      @output.printf("%-7s %12.6f %s\n", tr.status, tr.processor_time || Float::NAN, te.description)
    end
  end
end
