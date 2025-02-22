# frozen_string_literal: true

require_relative 'sink'
require_relative 'formatter'
require_relative 'exceptions'

module Ruptr
  class Formatter::TAP < Formatter
    self.formatter_name = :tap

    include Sink

    def initialize(output, **opts)
      super(**opts)
      @output = output
    end

    def begin_plan(fields)
      @total_tests = 0
      if (n = fields[:planned_test_case_count])
        @output << "1..#{n}\n"
        @emitted_plan = true
      else
        @emitted_plan = false
      end
    end

    def finish_plan(_fields)
      return if @emitted_plan
      @output << "1..#{@total_tests}\n"
    end

    private def escape(s) = s.gsub(/[\\#]/) { |m| "\\#{m}" }

    def finish_element(te, tr)
      pending = tr.skipped? && tr.exception.is_a?(PendingSkippedMixin)
      @output << (tr.passed? || (tr.skipped? && !pending) ? "ok" : "not ok")
      @output << ' ' << @total_tests.succ.to_s
      @output << ' - ' << escape(te.description) if te.description
      if tr.skipped?
        @output << ' # ' << (pending ? "TODO" : "SKIP")
        @output << ' ' << escape(tr.exception.message) if tr.exception&.message
      end
      @output << "\n"
      if tr.failed? && tr.exception
        tr.exception.full_message(highlight: false).each_line { |s| @output << '# ' << s }
      end
      @total_tests += 1
    end
  end
end
