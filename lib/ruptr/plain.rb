# frozen_string_literal: true

require 'pp'
begin
  require 'diff/lcs'
  require 'diff/lcs/hunk'
rescue LoadError
end

require_relative 'formatter'
require_relative 'suite'
require_relative 'result'
require_relative 'tty_colors'
require_relative 'surrogate_exception'
require_relative 'stringified'
require_relative 'assertions'

module Ruptr
  class Formatter::Plain < Formatter
    self.formatter_name = :plain

    include Formatter::Colorizing
    include Formatter::Verbosity

    private

    def initialize(output, indent: "\t", heading_width: 80, unicode: false, **opts)
      super(**opts)
      @output = output
      @indent = indent
      @heading_width = heading_width
      @unicode = unicode
    end

    def write(s) = @output << s

    def newline = @output << "\n"

    def line(s) = @output << @line_prefix << s << "\n"

    def lines(s)
      last_line = nil
      s.each_line do |line|
        @output << @line_prefix << line
        last_line = line
      end
      # NOTE: This can misbehave if there are ANSI terminal codes after the newlines!
      @output << "\n" if last_line && !last_line.end_with?("\n")
    end

    def indent
      if block_given?
        saved = @line_prefix
        @line_prefix += @indent
        begin
          yield
        ensure
          @line_prefix = saved
        end
      else
        @output << @line_prefix
      end
    end

    def location_path_relative_from = @location_path_relative_from ||= Dir.pwd

    def render_backtrace_location(loc)
      if loc =~ /\A([^:]*)(:.*)\z/ && $1.start_with?((base_path = location_path_relative_from + '/'))
        rel_path = $1[base_path.length..]
        colorize(base_path + colorize(rel_path, bright: true) + $2, color: :cyan)
      else
        colorize(loc, color: :cyan)
      end
    end

    def render_exception(heading_prefix, ex)
      line("#{heading_prefix}: " +
           if ex.is_a?(SurrogateException) && ex.original_class_name
             "#{ex.original_class_name} (#{colorize(ex.class.name, color: :magenta)})"
           else
             colorize(ex.class.name, color: case ex
                                            when SkippedExceptionMixin,
                                                 PendingSkippedMixin then :yellow
                                            when StandardError then :red
                                            else :magenta
                                            end)
           end)
      indent do
        if (msg = if ex.respond_to?(:detailed_message)
                    ex.detailed_message(highlight: @colorizer.is_a?(TTYColors::ANSICodes)) || ex.message
                  else
                    ex.message
                  end)
          line("Message:")
          indent do
            lines(msg)
          end
        end
        case ex
        when Assertions::EquivalenceAssertionError
          render_exception_diff(ex.actual, ex.expected)
        when Assertions::EquivalenceRefutationError
          render_exception_value("Actual", ex.actual)
        end
        if ex.backtrace
          line("Backtrace:")
          indent do
            ex.backtrace.each { |loc| line(render_backtrace_location(loc)) }
          end
        end
      end
    end

    def render_stringified_value(label, stringified)
      extra = []
      extra << stringified.original_class_name
      extra << "<#{stringified.string.encoding.name}>" if stringified.originally_a_string?
      m = stringified.stringification_method
      s = stringified.string_for_io(@output)
      unless m || (s.end_with?("\n") && s.match?(/\A[[:print:]\t\n]*\z/))
        s = s.public_send((m = s.count("\n") > 1 ? :pretty_inspect : :inspect))
      end
      extra << "##{m}" if m
      line("#{label} (#{extra.join(' ')}):")
      indent do
        lines(s)
      end
    end

    def render_exception_value(label, value)
      render_stringified_value(label, Stringified.from(value))
    end

    def diff_lcs_available?
      Object.const_defined?(:Diff) && Diff.const_defined?(:LCS) && Diff::LCS.const_defined?(:Hunk)
    end

    def render_exception_diff(actual, expected)
      actual_stringified = Stringified.from(actual)
      expected_stringified = Stringified.from(expected)

      can_diff = defined?(Diff::LCS::Hunk) &&
                 actual_stringified.compatible_with_io?(@output) &&
                 expected_stringified.compatible_with_io?(@output) &&
                 begin
                   actual_lines = actual_stringified.string.lines
                   expected_lines = expected_stringified.string.lines
                   actual_lines.size > 1 || expected_lines.size > 1
                 end

      if !can_diff || verbose?(1)
        render_stringified_value("Actual", actual_stringified)
        render_stringified_value("Expected", expected_stringified)
      end

      return unless can_diff

      diff_colors = if !TTYColors.seems_to_contain_formatting_codes?(actual_stringified.string) &&
                       !TTYColors.seems_to_contain_formatting_codes?(expected_stringified.string)
                      { '@' => :cyan, '+' => :green, '-' => :red }
                    else
                      {}
                    end

      line("Difference:")
      indent do
        render_hunk = lambda do |hunk, last = false|
          hunk.diff(:unified, last).each_line(chomp: true) do |s|
            line(colorize(s, color: diff_colors[s[0]]))
          end
        end
        offset = 0
        last_hunk = nil
        Diff::LCS.diff(expected_lines, actual_lines).each do |piece|
          hunk = Diff::LCS::Hunk.new(expected_lines, actual_lines, piece, 3, offset)
          offset = hunk.file_length_difference
          render_hunk.call(last_hunk) if last_hunk && !hunk.merge(last_hunk)
          last_hunk = hunk
        end
        render_hunk.call(last_hunk, true) if last_hunk
      end
    end

    STATUS_COLORS = { passed: :green, skipped: :yellow, failed: :red, blocked: :magenta }
                    .tap { |h| h.default = :magenta }.freeze

    def render_element_details(te)
      labels = te.path_labels.compact
      labels.each_with_index do |label, index|
        if @unicode
          s = +''
          s << '  ' * (index - 1) + '└─' unless index.zero?
          s << (index == labels.size - 1 ? "─" : index == 0 ? '┌' : "┬") << '╼'
          s << " " << label
        else
          s = '  ' * index + label
        end
        line(s)
      end
      newline
    end

    def render_result_details(tr)
      unless quiet?(1)
        line("Status:          #{colorize(tr.status.to_s.upcase, color: STATUS_COLORS[tr.status])}")
        a = []
        a << "#{'%0.6f' % tr.user_time} user" if tr.user_time
        a << "#{'%0.6f' % tr.system_time} system" if tr.system_time
        line("Processor time:  #{a.join(', ')}") unless a.empty?
        a = []
        a << "#{tr.assertions}" unless tr.assertions.zero?
        a << colorize("#{tr.ineffective_assertions} ineffective", color: :yellow) \
          unless tr.ineffective_assertions.zero?
        line("Assertion count: #{a.join(', ')}") unless a.empty?
        newline
      end

      space = false
      if tr.exception
        each_exception_cause_innermost_first(tr.exception).with_index do |ex, index|
          render_exception("Exception ##{index + 1}", ex)
        end
        space = true
      elsif tr.failed?
        line("Problem:")
        indent do
          line(colorize("Expected test to fail", color: :red))
        end
        space = true
      end
      newline if space

      space = false
      if tr.captured_stderr?
        line("Captured stderr:")
        indent do
          tr.captured_stderr.each_line do |s|
            line(colorize(s.chomp, color: :yellow))
          end
        end
        space = true
      end
      if tr.captured_stdout?
        line("Captured stdout:")
        indent do
          tr.captured_stdout.each_line do |s|
            line(colorize(s.chomp, color: :blue))
          end
        end
        space = true
      end
      newline if space
    end

    def format_heading(title)
      w = @heading_width
      if @unicode
        ["╔#{'═' * (w - 2)}╗", "║#{title.center(w - 2)}║", "╚#{'═' * (w - 2)}╝"]
      else
        b = 4
        ['#' * w, "#{'#' * b}#{title.center(w - b * 2)}#{'#' * b}", '#' * w]
      end
    end

    def heading(title, **style)
      format_heading(title).each { |s| line(colorize(s, **style)) }
      @heading_count += 1
      newline unless @unicode
    end

    def render_element(te, tr)
      case
      when tr.passed?
        @total_passed_cases += 1 if te.test_case?
        @total_passed_groups += 1 if te.test_group?
        if tr.captured_stderr?
          @total_passed_warned_cases += 1 if te.test_case?
          @total_passed_warned_groups += 1 if te.test_group?
          return if quiet?(2)
          title = "WARNING ##{@warned_index}"
          @warned_index += 1
          color = :yellow
        else
          return unless verbose?(3)
          title = "PASSED ##{@passed_index}"
          @passed_index += 1
          color = :green
        end
      when tr.skipped?
        @total_skipped_cases += 1 if te.test_case?
        @total_skipped_groups += 1 if te.test_group?
        if tr.exception.is_a?(PendingSkippedMixin)
          @total_skipped_pending_cases += 1 if te.test_case?
          @total_skipped_pending_groups += 1 if te.test_group?
          return unless verbose?(2)
          title = "PENDING ##{@pending_index}"
          @pending_index += 1
        else
          return unless verbose?(2)
          title = "SKIPPED ##{@skipped_index}"
          @skipped_index += 1
        end
        color = :yellow
      when tr.blocked?
        @total_blocked_cases += 1 if te.test_case?
        @total_blocked_groups += 1 if te.test_group?
        return unless verbose?(2)
        title = "BLOCKED ##{@blocked_index}"
        @blocked_index += 1
        color = :magenta
      when tr.failed?
        @total_failed_cases += 1 if te.test_case?
        @total_failed_groups += 1 if te.test_group?
        return if quiet?(2)
        title = "FAILURE ##{@failed_index}"
        @failed_index += 1
        color = :red
      else
        @total_failed_cases += 1 if te.test_case?
        @total_failed_groups += 1 if te.test_group?
        return if quiet?(2)
        title = "UNKNOWN ##{@unknown_index}"
        @unknown_index += 1
        color = :magenta
      end
      heading(title, color:)
      render_element_details(te)
      render_result_details(tr)
    end

    def render_timing(fields)
      return unless verbose?(1)
      a = [
        *["User time", "System time", "Real time"],
        *%i[test_files_load_user_time test_files_load_system_time test_files_load_real_time
            test_suite_run_user_time test_suite_run_system_time test_suite_run_real_time
            overall_user_time overall_system_time overall_real_time].map { |s| fields[s] || Float::NAN },
      ]
      lines(format(<<~PRINTF, *a))
                             %14s  %14s  %14s
        Loading test files:  %14.6f  %14.6f  %14.6f
        Running test suite:  %14.6f  %14.6f  %14.6f
        Overall:             %14.6f  %14.6f  %14.6f

      PRINTF
    end

    def render_summary
      return if quiet?(3)

      s = +''
      s << "Ran #{@total_test_cases} test cases"
      a = []
      a << "#{@total_assertions} assertions" unless @total_assertions.zero?
      a << colorize("#{@total_ineffective_assertions} ineffective assertions", color: :yellow) \
        unless @total_ineffective_assertions.zero?
      s << " with #{a.join(' and ')}" unless a.empty?
      s << ": "

      s << colorize("#{@total_passed_cases} passed",
                    color: if @total_failed_cases.zero? &&
                              @total_failed_groups.zero? &&
                              !@total_passed_cases.zero?
                             :green
                           end)
      a = []
      a << colorize("#{@total_passed_warned_cases} warned", color: :yellow) \
        unless @total_passed_warned_cases.zero?
      a << colorize("#{@total_passed_warned_groups} warned test groups", color: :yellow) \
        unless @total_passed_warned_groups.zero?
      s << " (#{a.join(', ')})" unless a.empty?

      s << ", " << colorize("#{@total_skipped_cases} skipped", color: :yellow) \
        unless @total_skipped_cases.zero?
      a = []
      a << colorize("#{@total_skipped_pending_cases} pending", color: :yellow) \
        unless @total_skipped_pending_cases.zero?
      s << " (#{a.join(', ')})" unless a.empty?

      s << ", " << colorize("#{@total_failed_cases} failed", color: :red) \
        unless @total_failed_cases.zero?

      a = []
      a << colorize("#{@total_failed_groups} failed test groups", color: :red) \
        unless @total_failed_groups.zero?
      a << colorize("#{@total_skipped_groups} skipped test groups", color: :yellow) \
        unless @total_skipped_groups.zero?
      a << colorize("#{@total_blocked_groups} blocked test groups", color: :magenta) \
        unless @total_blocked_groups.zero?
      unless @total_blocked_cases.zero? && a.empty?
        s << ", " << colorize("#{@total_blocked_cases} blocked", color: :magenta)
        s << " (#{a.join(', ')})" unless a.empty?
      end

      line(s << ".")
    end

    public

    def begin_plan(_)
      @line_prefix = ''
      @heading_count = 0
      @unknown_index = @failed_index = @blocked_index =
                         @skipped_index = @pending_index =
                           @passed_index = @warned_index = 1
      @total_test_cases = @total_test_groups = 0
      @total_failed_cases = @total_blocked_cases =
        @total_skipped_cases = @total_skipped_pending_cases =
          @total_passed_cases = @total_passed_warned_cases = 0
      @total_failed_groups = @total_blocked_groups =
        @total_skipped_groups = @total_skipped_pending_groups =
          @total_passed_groups = @total_passed_warned_groups = 0
      @total_assertions = @total_ineffective_assertions = 0
    end

    def finish_plan(fields)
      unless @heading_count.zero?
        newline
        line('=' * @heading_width)
        newline
      end
      render_timing(fields)
      render_summary
    end

    def finish_element(te, tr)
      @total_test_cases += 1 if te.test_case?
      @total_test_groups += 1 if te.test_group?
      @total_assertions += tr.assertions
      @total_ineffective_assertions += tr.ineffective_assertions
      render_element(te, tr)
    end
  end
end
