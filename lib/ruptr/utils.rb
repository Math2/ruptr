# frozen_string_literal: true

module Ruptr
  module_function

  def measure_real_time
    t = Time.now
    yield
    Time.now - t
  end

  def measure_processor_time
    t = Process.times
    yield
    tt = Process.times
    [(tt.utime + tt.cutime) - (t.utime + t.cutime),
     (tt.stime + tt.cstime) - (t.stime + t.cstime)]
  end

  def measure_processor_and_real_time(&)
    p = nil
    t = measure_real_time { p = measure_processor_time(&) }
    p << t
  end

  def at_normal_exit
    at_exit { yield if $!.nil? || ($!.is_a?(SystemExit) && $!.success?) }
  end

  def fork_piped_worker
    child_read_io, parent_write_io = IO.pipe
    begin
      parent_read_io, child_write_io = IO.pipe
    rescue
      child_read_io.close
      parent_write_io.close
      raise
    end
    begin
      begin
        pid = Process.fork do
          parent_read_io.close
          parent_write_io.close
          yield child_read_io, child_write_io
        end
      ensure
        child_read_io.close
        child_write_io.close
      end
    rescue
      parent_read_io.close
      parent_write_io.close
      raise
    end
    [pid, parent_read_io, parent_write_io]
  end
end
