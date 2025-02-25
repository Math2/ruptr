# frozen_string_literal: true

require_relative 'suite'
require_relative 'result'
require_relative 'instance'
require_relative 'exceptions'
require_relative 'surrogate_exception'
require_relative 'utils'
require_relative 'capture_output'

module Ruptr
  class Context
    def initialize(runner, test_element, parent)
      @runner = runner
      @test_element = test_element
      @parent = parent
      @assertions_count = 0
    end

    attr_reader :runner, :test_element, :parent
    attr_accessor :assertions_count
  end

  class TestElement
    private def maybe_capture_output(context, &)
      if context.runner.capture_output
        CaptureOutput.capture_output(&)
      else
        yield
        [nil, nil]
      end
    end

    def make_result(context)
      status = exception = user_time = system_time = nil
      captured_stdout, captured_stderr = maybe_capture_output(context) do
        user_time, system_time = Ruptr.measure_processor_time do
          yield
        rescue *Ruptr.passthrough_exceptions
          raise
        rescue SkippedExceptionMixin => exception
          status = :skipped
        rescue Exception => exception
          status = :failed
        else
          status = :passed
        end
      end
      assertions = context.assertions_count
      TestResult.new(status,
                     user_time:, system_time:, assertions:, exception:,
                     captured_stdout:, captured_stderr:)
    end
  end

  class TestCase
    def run_result(runner, group_context)
      return TestResult.new(:skipped) unless runnable?
      context = Context.new(runner, self, group_context)
      make_result(context) { run_context(context) }
    end
  end

  class TestGroup
    def wrap_result(runner, parent_context)
      context = Context.new(runner, self, parent_context)
      make_result(context) do
        if wrappable?
          wrap_context(context) { yield context }
        else
          yield context
        end
      end
    end
  end

  class TestResult
    def make_marshallable
      return unless @exception
      begin
        Marshal.dump(@exception)
      rescue TypeError
        @exception = SurrogateException.from(@exception)
      end
    end
  end

  class Runner
    class << self
      def class_from_env(env = ENV, default_parallel: true)
        if (s = env['RUPTR_RUNNER'])
          find_runner(s.to_sym) or fail "unknown runner: #{s}"
        else
          n = (s = env['RUPTR_JOBS']) ? s.to_i : default_parallel ? 0 : 1
          n = Runner::Parallel.default_parallel_jobs unless n.positive?
          n > 1 ? Runner::Forking : Runner
        end
      end

      def opts_from_env(klass, env = ENV, **opts)
        if klass <= Runner::Parallel
          if !opts.key?(:parallel_jobs) && (s = env['RUPTR_JOBS'])
            n = s.to_i
            n = Runner::Parallel.default_parallel_jobs unless n.positive?
            opts[:parallel_jobs] = n
          end
        end
        opts
      end

      def from_env(env = ENV, **opts)
        klass = class_from_env(env)
        opts = opts_from_env(klass, env, **opts)
        klass.new(**opts)
      end

      attr_accessor :runner_names

      def find_runner(name)
        traverse = proc do |c|
          return c if c.runner_names&.include?(name)
          c.subclasses.each(&traverse)
        end
        traverse.call(self)
        nil
      end
    end

    self.runner_names = %i[single s]

    def initialize(randomize: false, timing_store: nil, golden_store: nil, capture_output: true)
      @randomize = randomize
      @timing_store = timing_store
      @golden_store = golden_store
      @capture_output = capture_output
    end

    attr_reader :timing_store, :golden_store, :capture_output

    def expected_processor_time(te) = @timing_store ? @timing_store[te] : Float::INFINITY

    class BatchYielder
      Batch = Struct.new(:group_context, :test_cases, :fork_overlap)

      private

      def initialize(runner, sink, &block)
        @runner = runner
        @sink = sink
        @process_batch = block
      end

      def wrap_group(tg, gc)
        @sink.submit_group(tg) do
          ok = false
          tr = tg.wrap_result(@runner, gc) do |gc|
            ok = true
            yield gc
          end
          traverse_group_children_blocked(tg, tr.failed? ? :blocked : :skipped) unless ok
          tr
        end
      end

      def traverse_group(tg, gc)
        wrap_group(tg, gc) { |gc| traverse_group_children(tg, gc) }
      end

      def traverse_group_children_blocked(tg, status = :blocked)
        tg.each_test_case do |tc|
          @sink.submit_case(tc, TestResult.new(status))
        end
        tg.each_test_subgroup do |tg|
          @sink.submit_group(tg) do
            traverse_group_children_blocked(tg, status)
            TestResult.new(status)
          end
        end
      end

      def traverse_group_children(tg, gc)
        batched_cases = []
        pending_groups = []
        gather = lambda do |tg|
          tg.each_test_case do |tc|
            batched_cases << tc
          end
          tg.each_test_subgroup do |tg|
            if tg.wrappable?
              pending_groups << tg
            else
              @sink.submit_group(tg) do
                gather.call(tg)
                TestResult.new(:passed)
              end
            end
          end
        end
        gather.call(tg)

        if @randomize
          batched_cases.shuffle!
        elsif @runner.timing_store
          batched_cases.sort_by! { |tc| -@runner.expected_processor_time(tc) }
        end
        @process_batch.call(Batch.new(gc, batched_cases, !tg.tags[:ruptr_no_fork_overlap]))

        if @randomize
          pending_groups.shuffle!
        elsif @runner.timing_store
          pending_groups.sort_by! { |tg| -@runner.expected_processor_time(tg) }
        end
        pending_groups.each do |tg|
          traverse_group(tg, gc)
        end
      end

      public def yield_batches(tg, gc = nil)
        traverse_group(tg, gc)
      end
    end

    private def each_batch(ts, sink, &)
      BatchYielder.new(self, sink, &).yield_batches(ts)
    end

    private def dispatch_batch(batch, sink)
      batch.test_cases.each do |tc|
        sink.submit_case(tc) { tc.run_result(self, batch.group_context) }
      end
    end

    def dispatch(ts, sink)
      each_batch(ts, sink) do |batch|
        dispatch_batch(batch, sink)
        golden_store&.flush_trial
      end
    end

    def run_sink(ts, sink)
      fields = { planned_test_case_count: ts.count_test_cases }
      sink.submit_plan(fields) { dispatch(ts, sink) }
    end

    def run_report(ts, report = Report.new)
      run_sink(ts, Report::Builder.new(report))
      report
    end

    class Parallel < self
      def self.default_parallel_jobs
        require 'etc'
        Etc.nprocessors
      end

      def initialize(parallel_jobs: self.class.default_parallel_jobs, **opts)
        super(**opts)
        @parallel_jobs = parallel_jobs
      end

      attr_reader :parallel_jobs
    end

    class Threaded < Parallel
      self.runner_names = %i[t thread threads threaded]

      def dispatch_batch(batch, sink)
        pending_mtx = Mutex.new
        sink_mtx = Mutex.new
        pending_tcs = batch.test_cases
        [parallel_jobs, pending_tcs.size].min.times.map do
          Thread.new do
            # TODO: reduce locking overhead?
            while (tc = pending_mtx.synchronize { pending_tcs.shift })
              sink_mtx.synchronize { sink.begin_case(tc) }
              tr = tc.run_result(self, batch.group_context)
              sink_mtx.synchronize { sink.finish_case(tc, tr) }
            end
          end
        end.each(&:join)
      end
    end

    class Forking < Parallel
      self.runner_names = %i[f fork forking p process processes]

      private def child_worker_loop(batch, all_tcs, read_io, write_io)
        loop do
          request = begin
            Marshal.load(read_io)
          rescue EOFError
            break
          end
          response = all_tcs.values_at(*request).map do |tc|
            tc.run_result(self, batch.group_context).tap(&:make_marshallable)
          end
          Marshal.dump(response, write_io)
        end
      ensure
        read_io.close
        write_io.close
      end

      Worker = Struct.new(:pid, :read_io, :write_io, :pending_tcs, :stale) do
        def close
          read_io.close
          write_io.close
        end
      end

      Master = Struct.new(:sink, :all_workers, :free_workers)

      private def spawn_worker(master, batch, all_tcs)
        pid, parent_read_io, parent_write_io = Ruptr.fork_piped_worker do |child_read_io, child_write_io|
          ENV['RUPTR_WORKER_PROCESS_INDEX'] = master.all_workers.size.to_s
          master.all_workers.reverse_each(&:close)
          child_worker_loop(batch, all_tcs, child_read_io, child_write_io)
          golden_store&.flush_trial
        end
        worker = Worker.new(pid, parent_read_io, parent_write_io, [], false)
        master.all_workers << worker
        master.free_workers << worker
      end

      private def distribute_work(master, all_tcs, remaining_tc_indexes)
        workers = master.free_workers.pop(remaining_tc_indexes.size)
        return if workers.empty?
        worker_tc_indexes = workers.map { [] }
        worker_total_time = workers.map { 0 }
        i = 0
        while (tc_index = remaining_tc_indexes.first)
          tc = all_tcs[tc_index]
          ptime = expected_processor_time(tc)
          break if worker_tc_indexes[i].size >= 8 ||
                   !worker_tc_indexes[i].empty? && worker_total_time[i] + ptime >= 0.005
          remaining_tc_indexes.shift
          worker_tc_indexes[i] << tc_index
          worker_total_time[i] += ptime
          i = (i + 1) % workers.size
        end
        workers.zip(worker_tc_indexes) do |worker, tc_indexes|
          worker.pending_tcs = all_tcs.values_at(*tc_indexes)
          Marshal.dump(tc_indexes, worker.write_io)
          worker.pending_tcs.each do |tc|
            master.sink.begin_case(tc)
          end
        end
      end

      private def process_responses(master)
        busy_workers = master.all_workers - master.free_workers
        ready_ios, _, _ = IO.select(busy_workers.map(&:read_io))
        ready_ios.each do |ready_io|
          worker = busy_workers.find { |w| w.read_io == ready_io }
          results = Marshal.load(ready_io)
          worker.pending_tcs.zip(results).each do |tc, tr|
            master.sink.finish_case(tc, tr)
          end
          worker.pending_tcs = nil
          master.free_workers.push(worker)
        end
      end

      private def drop_workers(master, workers)
        workers.each { |w| w.write_io.close }
        workers.each do |w|
          Process.wait(w.pid)
          raise "worker process #{$?}" unless $?.success?
        end
        master.all_workers -= workers
        master.free_workers -= workers
      end

      private def finish_workers(master)
        process_responses(master) until (master.all_workers - master.free_workers).empty?
        drop_workers(master, master.all_workers)
      end

      private def workers_count_for_test_cases(tcs)
        # for very fast test cases, forking a process isn't worth it
        m = [tcs.size, parallel_jobs].min
        a = 0
        tcs.each do |tc|
          a += expected_processor_time(tc) * 512
          return m if a >= m
        end
        [a.to_i, 1].max
      end

      def dispatch(ts, sink)
        master = Master.new(sink, [], [])
        # NOTE: Each iteration of #yield_batches is run with a global state setup for this
        # particular batch of test cases. Worker processes must not be reused if they were forked
        # while a different state was active.
        total_workers_limit = parallel_jobs
        each_batch(ts, sink) do |batch|
          all_tcs = batch.test_cases
          batch_workers_limit = workers_count_for_test_cases(all_tcs)
          unless batch_workers_limit > 1
            # Fallback to single-threaded serial execution.
            dispatch_batch(batch, sink)
            next
          end
          batch_workers_count = 0
          remaining_tc_indexes = all_tcs.size.times.to_a
          until remaining_tc_indexes.empty?
            while master.all_workers.size < total_workers_limit &&
                  batch_workers_count < batch_workers_limit
              spawn_worker(master, batch, all_tcs)
              batch_workers_count += 1
            end
            distribute_work(master, all_tcs, remaining_tc_indexes)
            # See if we can spawn workers for the next batch before waiting on results.
            break if remaining_tc_indexes.empty?
            process_responses(master)
            drop_workers(master, master.free_workers.select(&:stale))
          end
          master.all_workers.each { |w| w.stale = true }
          if batch.fork_overlap
            drop_workers(master, master.free_workers)
          else
            finish_workers(master)
          end
        end
        finish_workers(master)
      ensure
        master.all_workers.each(&:close)
        master.all_workers = master.free_workers = nil
      end
    end
  end
end
