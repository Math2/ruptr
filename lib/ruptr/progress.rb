# frozen_string_literal: true

require_relative 'suite'
require_relative 'tty_colors'

module Ruptr
  class Progress
    include Sink

    def initialize(output)
      @output = output
      @colorizer = TTYColors.for(output)
    end

    def begin_plan(fields)
      @planned_test_case_count = fields[:planned_test_case_count]
      progress_start
    end

    def finish_plan(_) = progress_end
    def finish_element(te, tr) = progress_result(te, tr)

    class Dots < self
      def progress_result(_te, tr)
        @output << case
                   when tr.passed? then @colorizer.wrap('.', color: :green)
                   when tr.skipped? then @colorizer.wrap('_', color: :yellow)
                   when tr.failed? then @colorizer.wrap('!', color: :red)
                   else @colorizer.wrap('?', color: :magenta)
                   end
      end

      def progress_end
        @output << "\n"
      end
    end

    class StatusLine < self
      def progress_start
        @processor_time = 0
        @test_cases = @assertions = 0
        @passed = @skipped = @failed = @blocked = 0
        @last_line_width = 0
        @twirls = @last_twirl_processor_time = 0
      end

      private def colorize(s, **opts) = @colorizer.wrap(s, **opts)

      CHARS = %w[\\ | / -].freeze

      def progress_result(te, tr)
        @processor_time += tr.processor_time || 0
        @assertions += tr.assertions || 0
        if te.test_case?
          @test_cases += 1
          @passed += 1 if tr.passed?
          @skipped += 1 if tr.skipped?
          @failed += 1 if tr.failed?
          @blocked += 1 if tr.blocked?
        end

        line = +"\r"
        line << "Running tests... "
        if (@processor_time - @last_twirl_processor_time) >= 0.25
          @twirls += 1
          @last_twirl_processor_time = @processor_time
        end
        line << CHARS[@twirls % CHARS.size]
        line << " ptime:" << colorize('%.03fs' % @processor_time, color: :cyan)
        line << " cases:" << colorize(@test_cases.to_s, color: :cyan)
        if (n = @planned_test_case_count)
          line << "/#{n}"
          line << " (#{@test_cases * 100 / n}%)" unless n.zero?
        end
        line << " asserts:" << colorize(@assertions.to_s, color: :cyan) unless @assertions.zero?
        line << " passed:" << colorize(@passed.to_s, color: :green) unless @passed.zero?
        line << " skipped:" << colorize(@skipped.to_s, color: :yellow) unless @skipped.zero?
        line << " failed:" << colorize(@failed.to_s, color: :red) unless @failed.zero?
        line << " blocked:" << colorize(@blocked.to_s, color: :magenta) unless @blocked.zero?
        line << ' '
        width = line.length - 1
        if width < @last_line_width
          n = @last_line_width - width + 1
          @last_line_width = width
          line << ' ' * n << "\b" * n
        else
          @last_line_width = width
        end
        @output << line
      end

      def progress_end
        n = @last_line_width
        @output << ("\b" * n + ' ' * (n + 1) + "\b" * (n + 1))
      end
    end
  end
end
