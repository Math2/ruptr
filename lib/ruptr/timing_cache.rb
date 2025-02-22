# frozen_string_literal: true

require 'zlib' # for crc32
require 'pathname'

require_relative 'sink'

module Ruptr
  class TimingCache
    TIMING_CACHE_FILENAME = 'timing'

    def initialize(state_dir, test_suite)
      @state_path = Pathname(state_dir)
      @test_suite = test_suite
    end

    attr_reader :test_suite

    def timing_store
      @timing_store ||= begin
        @cache_path = @state_path / TIMING_CACHE_FILENAME
        if @cache_path.exist?
          TimingCache::Store.load(@test_suite, @cache_path)
        else
          TimingCache::Store.new
        end
      end
    end

    def save!(replace: true)
      return unless @timing_store
      @timing_store.dump(@test_suite, @cache_path, replace:)
    end

    class Store
      def self.load(...) = new.tap { |o| o.load(...) }

      def initialize
        @current = {}
      end

      private def te_hash(te) = Zlib.crc32(te.description)

      private def load_hashed(path)
        s = Pathname(path).binread
        n = s.length / 8
        a = s.unpack("V#{n}e#{n}")
        h = {}
        n.times { |i| h[a[i]] = a[i + n] }
        h
      end

      def load(ts, path)
        h = load_hashed(path)

        traverse = lambda do |tg|
          total_time = 0
          tg.each_test_case do |tc|
            time = h[te_hash(tc)] or next
            @current[tc] = time
            total_time += time
          end
          tg.each_test_subgroup do |tg|
            total_time += traverse.call(tg)
          end
          @current[tg] = total_time
        end
        traverse.call(ts)
      end

      private def dump_hashed(path, h)
        n = h.size
        s = (h.keys + h.values).pack("V#{n}e#{n}")
        Pathname(path).binwrite(s)
      end

      def dump(_ts, path, replace: true)
        h = replace ? {} : load_hashed(path)
        @updated.each_pair do |te, time|
          k = te_hash(te)
          h[k] = [h[k] || 0, time].max
        end
        dump_hashed(path, h)
      end

      def [](te) = @current[te] || Float::INFINITY

      include Sink

      def begin_plan(_)
        @updated = {}
      end

      def finish_case(tc, tr)
        time = tr.processor_time
        @updated[tc] = time if time
      end
    end
  end
end
