# frozen_string_literal: true

require 'delegate'
require 'stringio'

module Ruptr
  class CaptureOutput < Delegator
    def initialize(real_io, tls_key)
      @real_io = real_io
      @tls_key = tls_key
    end

    attr_reader :real_io

    if Fiber.respond_to?(:[])
      private def tls_obj = Fiber
    else
      private def tls_obj = Thread.current
    end

    private def __getobj__
      tls_obj[@tls_key] || @real_io
    end

    def capture
      strio = StringIO.new(+'', 'w')
      saved = tls_obj[@tls_key]
      begin
        tls_obj[@tls_key] = strio
        yield
        strio.string
      ensure
        tls_obj[@tls_key] = saved
        strio.close
      end
    end

    @mutex = Mutex.new
    @pinned = 0
    @fixed = false

    class << self
      def installed? = $stdout.is_a?(self) && $stderr.is_a?(self)

      def install!
        $stdout = new($stdout, :ruptr_stdout)
        $stderr = new($stderr, :ruptr_stderr)
      end

      def uninstall!
        $stdout = $stdout.real_io
        $stderr = $stderr.real_io
      end

      def reset!
        uninstall! if @fixed || @pinned.positive?
        @fixed = false
        @pinned = 0
      end

      def fixed_install!
        return block_given? ? yield : nil if @fixed
        @fixed = true
        install!
        return unless block_given?
        begin
          yield
        ensure
          @fixed = false
          uninstall!
        end
      end

      def capture_output(&)
        unless @fixed
          if (ractor = defined?(::Ractor) && Ractor.current != Ractor.main)
            install! unless installed?
          else
            @mutex.synchronize do
              install! unless @pinned.positive?
              @pinned += 1
            end
          end
        end
        begin
          stdout = stderr = nil
          stderr = $stderr.capture { stdout = $stdout.capture(&) }
          [stdout, stderr]
        ensure
          unless @fixed || ractor
            @mutex.synchronize do
              @pinned -= 1
              uninstall! unless @pinned.positive?
            end
          end
        end
      end
    end

    module ForkHandler
      # NOTE: This assumes that the child will exit and the parent unwinds.
      def _fork = super.tap { |pid| CaptureOutput.reset! if pid.nil? || pid.zero? }
    end
    Process.singleton_class.prepend(ForkHandler)
  end
end
