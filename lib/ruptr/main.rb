# frozen_string_literal: true

require 'optparse'
require 'pathname'

require_relative 'suite'
require_relative 'utils'
require_relative 'runner'
require_relative 'timing_cache'
require_relative 'golden_master'
require_relative 'report'
require_relative 'sink'
require_relative 'progress'
require_relative 'formatter'
require_relative 'tabular'
require_relative 'tap'

require_relative 'minitest'
require_relative 'testunit'
require_relative 'rspec'

module Ruptr
  class Main
    DEFAULT_STATE_DIRNAME = '.ruptr-state'
    DEFAULT_PROJECT_LOAD_PATHS = %w[lib].freeze

    def initialize(project_dir = '.')
      @project_path = Pathname(project_dir)
      @extra_load_paths = []
      @extra_requires = []
      @add_default_project_load_paths = true
      @warnings = $VERBOSE
      @verbosity = 0
      @capture_output = true
      @monkey_patch = false
      @formatter_name = nil
      @runner_name = nil
      @pager_mode = true
      @pager_only_on_problem = true
      @output_path = nil
      @include_names = []
      @exclude_names = []
      @include_tags = []
      @exclude_tags = []
      @include_tags_values = {}
      @exclude_tags_values = {}
      @only_test_files = []
      @operations = []
    end

    attr_accessor :extra_load_paths,
                  :extra_requires,
                  :warnings,
                  :verbosity,
                  :capture_output,
                  :monkey_patch,
                  :parallel_jobs,
                  :output_path,
                  :only_test_files

    def load_all_tests? = @only_test_files.empty?

    def parse_options(argv)
      argv = argv.dup
      OptionParser.new do |op|
        op.on('-C', '--project-path=PATH') { |s| @project_path = Pathname(s) }
        op.on('--state-directory=PATH') { |s| @state_path = Pathname(s) }
        op.on('--[no-]default-project-load-paths') { |v| @add_default_project_load_paths = v }
        op.on('-I', '--include=PATH') { |s| @extra_load_paths << s }
        op.on('-r', '--require=PATH') { |s| @extra_requires << s }
        op.on('--[no-]capture-output') { |v| @capture_output = v }
        op.on('-m', '--[no-]monkey-patch') { |v| @monkey_patch = v }
        op.on('-w', '--[no-]warnings') { |v| @warnings = v ? true : nil }
        op.on('-o', '--output=PATH') { |s| @output_path = Pathname(s) }
        op.on('-f', '--formatter=NAME') { |s| @formatter_name = s }
        op.on('--[no-]pager') { |v| @pager_mode = v }
        op.on('--[no-]pager-only-on-problem') { |v| @pager_only_on_problem = v }
        op.on('--runner=NAME') { |s| @runner_name = s }
        op.on('-j', '--jobs=N') do |s|
          n = s.to_i
          n = Runner::Parallel.default_parallel_jobs unless n.positive?
          @parallel_jobs = n
        end
        op.on('--debuggable') do
          @pager_mode = false
          @capture_output = false
          @runner_name = :single
          @parallel_jobs = 1
        end
        op.on('-e', '--example=STRING') { |s| @include_names << Regexp.new(Regexp.quote(s)) }
        op.on('-E', '--example-matches=REGEXP') { |s| @include_names << Regexp.new(s) }
        op.on('-t', '--tag=TAG[:VALUE]') do |s|
          name, value = s.split(':', 2)
          name.delete_prefix!('~') if (exclude = name.start_with?('~'))
          name = name.to_sym
          if value
            value = value.delete_prefix(':').to_sym if value.start_with?(':')
            (exclude ? @exclude_tags_values : @include_tags_values)[name] = value
          else
            (exclude ? @exclude_tags : @include_tags) << name
          end
        end
        op.on('-q', '--[no-]quiet') { |v| @verbosity -= v ? 1 : 0 }
        op.on('-v', '--[no-]verbose') { |v| @verbosity += v ? 1 : 0 }
        op.on('--golden-accept') { @operations << :golden_accept }
        op.on('--show-test-suite') { @operations << :show_test_suite }
      end.order!(argv)
      @only_test_files = argv.dup
    end

    def state_path
      @state_path ||= @project_path / Pathname(DEFAULT_STATE_DIRNAME)
      unless @state_path_made
        @state_path.mkpath
        @state_path_made = true
      end
      @state_path
    end

    def with_state_directory_lock
      (state_path / "lock").open(File::CREAT | File::RDWR) do |io|
        io.flock(File::LOCK_EX | File::LOCK_NB) or fail "state directory locked"
        yield
      end
    end

    def compat_layers
      @compat_layers ||= Compat.subclasses.map(&:new)
    end

    def project_load_paths
      @project_load_paths ||=
        (@extra_load_paths +
         if @add_default_project_load_paths
           DEFAULT_PROJECT_LOAD_PATHS.map { |path| (@project_path / path).to_s } +
             compat_layers.flat_map(&:default_project_load_paths)
         else
           []
         end).uniq
    end

    def each_test_file(&)
      if load_all_tests?
        compat_layers.each { |compat| compat.each_default_project_test_file(@project_path, &) }
      else
        @only_test_files.each(&)
      end
    end

    private def prepare_compat
      compat_layers.each do |compat|
        compat.global_install!
        compat.global_monkey_patch! if @monkey_patch
      end
    end

    private def finalize_compat
      compat_layers.each(&:finalize_configuration!)
    end

    private def load_test_files
      return if @test_files_loaded
      prepare_compat
      @load_user_time, @load_system_time, @load_real_time = Ruptr.measure_processor_and_real_time do
        $LOAD_PATH.unshift(*project_load_paths)
        @extra_requires.each { |name| require(name) }
        each_test_file do |path|
          path = path.to_s
          require(%r{\A\.{0,2}/}.match?(path) ? path : "./#{path}")
        end
      end
      finalize_compat
      @test_files_loaded = true
    end

    def loaded_test_suite
      @loaded_test_suite ||= TestSuite.new.tap do |ts|
        load_test_files
        @total_loaded_test_cases_before_internal_filtering = 0
        compat_layers.each do |compat|
          tg = compat.adapted_test_group
          @total_loaded_test_cases_before_internal_filtering += tg.count_test_cases
          ts.add_test_subgroup(compat.filter_test_group(tg))
        end
      end
    end

    def filtered_test_suite
      @filtered_test_suite ||=
        if @include_names.empty? && @exclude_names.empty? &&
           @include_tags.empty? && @exclude_tags.empty? &&
           @include_tags_values.empty? && @exclude_tags_values.empty?
          loaded_test_suite
        else
          loaded_test_suite.filter_test_cases_recursive do |tc|
            (@include_names.empty? || @include_names.any? { |v| v === tc.description }) &&
              (@exclude_names.empty? || @exclude_names.none? { |v| v === tc.description }) &&
              (@include_tags.empty? || @include_tags.any? { |k| tc.tags.include?(k) }) &&
              (@exclude_tags.empty? || @exclude_tags.none? { |k| tc.tags.include?(k) }) &&
              (@include_tags_values.empty? || @include_tags_values.any? { |k, v| v === tc.tags[k] }) &&
              (@exclude_tags_values.empty? || @exclude_tags_values.none? { |k, v| v === tc.tags[k] })
          end
        end
    end

    def report_total_filtered
      return if @verbosity.negative?
      loaded_test_suite
      n = @total_loaded_test_cases_before_internal_filtering
      m = filtered_test_suite.count_test_cases
      $stderr.puts "#{n - m} test cases filtered" unless n == m
    end

    def pager_mode?
      @pager_mode && !@output_path && $stdout.tty?
    end

    private def default_pager_cmd = 'LESS=-R less'

    private def open_output
      fail if @output_file
      if pager_mode? && (!@pager_only_on_problem || test_suite_problem?)
        @output_file = IO.popen(ENV['PAGER'] || default_pager_cmd, 'w',
                                external_encoding: $stdout.external_encoding)
        @output_file_close = true
      else
        if @output_path
          @output_file = @output_path.open('w')
          @output_file_close = true
        else
          @output_file = $stdout
          @output_file_close = false
        end
      end
      @output_file
    end

    private def close_output
      @output_file.close if @output_file_close
      @output_file = @output_file_close = nil
    end

    def formatter
      @formatter ||= begin
        formatter_class = if @formatter_name
                            Formatter.find_formatter(@formatter_name.to_sym) or fail "unknown formatter: #{@formatter_name}"
                          else
                            Formatter.class_from_env
                          end
        opts = {}
        opts[:verbosity] = @verbosity if formatter_class.include?(Formatter::Verbosity)
        output = open_output
        if formatter_class.include?(Formatter::Colorizing)
          opts[:colorizer] = TTYColors.for(pager_mode? ? $stdout : output)
        end
        opts = Formatter.opts_from_env(formatter_class, **opts)
        formatter_class.new(output, **opts)
      end
    end

    def timing_cache
      @timing_cache ||= TimingCache.new(state_path, filtered_test_suite)
    end

    def golden_master
      @golden_master ||= GoldenMaster.new(
        state_path,
        original_test_suite: load_all_tests? ? loaded_test_suite : nil,
        filtered_test_suite: filtered_test_suite,
      )
    end

    def runner
      @runner ||= begin
        runner_class = if @runner_name
                         Runner.find_runner(@runner_name.to_sym) or fail "unknown runner: #{@runner_name}"
                       else
                         Runner.class_from_env(default_parallel: @parallel_jobs != 1)
                       end
        opts = {
          timing_store: timing_cache.timing_store,
          golden_store: golden_master.golden_store,
          capture_output: @capture_output,
        }
        opts[:parallel_jobs] = @parallel_jobs if !@parallel_jobs.nil? && runner_class <= Runner::Parallel
        opts = Runner.opts_from_env(runner_class, **opts)
        runner_class.new(**opts)
      end
    end

    def warmup
      Process.warmup if Process.respond_to?(:warmup)
    end

    def test_suite_passed?
      @report ? @report.passed? : @sink_passed.passed?
    end

    def test_suite_problem?
      if @report
        @report.failed? || @report.each_test_case_result.any? { |_, tr| tr.captured_stderr? }
      else
        !test_suite_passed?
      end
    end

    private def sink
      @sink ||= begin
        sinks = []
        if pager_mode?
          sinks << Report::Builder.new((@report = Report.new))
          sinks << Progress::StatusLine.new($stderr) if !@verbosity.negative? && $stderr.tty?
        else
          sinks << formatter
          sinks << (@sink_passed = Sink::Passed.new)
        end
        sinks << timing_cache.timing_store
        Sink::Tee.for(sinks)
      end
    end

    private def plan_header
      header = {
        planned_test_case_count: filtered_test_suite.count_test_cases,
      }
      sink.begin_plan(header)
    end

    private def plan_footer
      footer = {
        test_files_load_user_time: @load_user_time,
        test_files_load_system_time: @load_system_time,
        test_files_load_real_time: @load_real_time,
        test_suite_run_user_time: @run_user_time,
        test_suite_run_system_time: @run_system_time,
        test_suite_run_real_time: @run_real_time,
        overall_user_time: @overall_user_time,
        overall_system_time: @overall_system_time,
        overall_real_time: @overall_real_time,
      }
      sink.finish_plan(footer)
    end

    private def speedup_capture_output(&)
      return yield unless @capture_output
      CaptureOutput.fixed_install!(&)
    end

    private def run_test_suite
      speedup_capture_output do
        @run_real_time = Ruptr.measure_real_time do
          @run_user_time, @run_system_time = Ruptr.measure_processor_time do
            runner.dispatch(filtered_test_suite, sink)
          end
        end
      end
    end

    private def save_timing_cache
      @timing_cache&.save!(replace: load_all_tests? && loaded_test_suite.equal?(filtered_test_suite))
    end

    private def save_golden_master
      @golden_master&.save_trial!
    end

    private def save_bookkeeping
      save_timing_cache
      save_golden_master
    end

    def output_report
      return unless @report
      @report.emit(formatter)
    rescue Errno::EPIPE
    end

    private def possibly_with_warnings
      saved = $VERBOSE
      $VERBOSE = @warnings
      yield
    ensure
      $VERBOSE = saved
    end

    private def measure_overall_time(&)
      @overall_user_time, @overall_system_time, @overall_real_time =
        Ruptr.measure_processor_and_real_time(&)
    end

    private def run_tests
      possibly_with_warnings do
        measure_overall_time do
          plan_header
          report_total_filtered
          warmup
          with_state_directory_lock do
            run_test_suite
            save_bookkeeping
          end
        end
        plan_footer
        output_report
      ensure
        close_output
      end
    end

    private def golden_accept
      golden_master.accept_trial!
    end

    private def show_test_suite
      report_total_filtered

      io = $stdout
      w1, w2 = 1, 1
      traverse = lambda do |te, prefix, last|
        io << prefix << (last ? '└' : '├') << '─' * w1 if prefix
        io << (te.test_group? && !te.empty? ? (w2.zero? ? '┮' : '┬') : (w2.zero? ? '╼' : '─'))
        io << '─' * w2.pred << '╼' unless w2.zero?
        io << ' ' << (te.label || '...') << "\n"
        if te.test_group?
          prefix = prefix ? prefix + (last ? ' ' : '│') + ' ' * w1 : ''
          last_te = nil
          te.each_test_element do |te|
            traverse.call(last_te, prefix, false) if last_te
            last_te = te
          end
          traverse.call(last_te, prefix, true) if last_te
        end
      end
      traverse.call(filtered_test_suite, nil, true)
    end

    def run
      # NOTE: this method's return value is passed Kernel#exit
      if @operations.empty?
        run_tests
        test_suite_passed?
      else
        @operations.each { |operation_name| send(operation_name) }
        true
      end
    end
  end
end
