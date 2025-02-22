# frozen_string_literal: true

require_relative 'suite'
require_relative 'result'
require_relative 'sink'
require_relative 'tty_colors'

module Ruptr
  class Formatter
    class << self
      def class_from_env(env = ENV)
        if (s = env['RUPTR_FORMAT'])
          find_formatter(s.to_sym) or fail "unknown formatter: #{s}"
        else
          require_relative 'plain'
          Plain
        end
      end

      def opts_from_env(klass, env = ENV, **opts)
        if klass.include?(Verbosity)
          if (s = env['RUPTR_VERBOSE'])
            opts[:verbosity] = /\A-?\d+\z/.match?(s) ? s.to_i : 1
          end
        end
        opts
      end

      def from_env(output, env = ENV, **opts)
        klass = class_from_env(env)
        opts = opts_from_env(klass, env, **opts)
        klass.new(output, **opts)
      end

      attr_accessor :formatter_name

      def find_formatter(name)
        traverse = proc do |c|
          return c if c.formatter_name == name
          c.subclasses.each(&traverse)
        end
        traverse.call(self)
        nil
      end
    end

    include Sink

    private def each_exception_cause_innermost_first(ex, &)
      return to_enum __method__, ex unless block_given?
      each_exception_cause_innermost_first(ex.cause, &) if ex.cause
      yield ex
    end

    module Colorizing
      private

      def initialize(*args, colorizer: TTYColors::Dummy.new, **opts)
        super(*args, **opts)
        @colorizer = colorizer
      end

      def colorize(s, **opts) = @colorizer.wrap(s, **opts)
    end

    module Verbosity
      private

      def initialize(*args, verbosity: 0, **opts)
        super(*args, **opts)
        @verbosity = verbosity
      end

      def verbose?(n = 1) = @verbosity >= n
      def quiet?(n = 1) = @verbosity <= -n
    end
  end
end
