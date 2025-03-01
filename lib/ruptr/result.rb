# frozen_string_literal: true

require_relative 'suite'
require_relative 'sink'

module Ruptr
  class TestResult
    # NOTE: Objects of this class will get dumped/loaded with Marshal.

    VALID_STATUSES = %i[passed skipped failed blocked].freeze

    def initialize(status,
                   exception: nil,
                   assertions: 0, ineffective_assertions: 0,
                   user_time: nil, system_time: nil,
                   captured_stdout: nil, captured_stderr: nil)
      raise ArgumentError unless VALID_STATUSES.include?(status)
      raise ArgumentError if exception && status == :passed
      @status = status
      @exception = exception
      @assertions = assertions
      @ineffective_assertions = ineffective_assertions
      @user_time = user_time
      @system_time = system_time
      @captured_stdout = captured_stdout
      @captured_stderr = captured_stderr
    end

    attr_reader :status,
                :exception,
                :assertions, :ineffective_assertions,
                :user_time, :system_time,
                :captured_stdout, :captured_stderr

    def passed? = @status == :passed
    def skipped? = @status == :skipped
    def failed? = @status == :failed
    def blocked? = @status == :blocked

    def processor_time = !@user_time ? @system_time : !@system_time ? @user_time : @user_time + @system_time

    def captured_stdout? = @captured_stdout && !@captured_stdout.empty?
    def captured_stderr? = @captured_stderr && !@captured_stderr.empty?
  end
end
