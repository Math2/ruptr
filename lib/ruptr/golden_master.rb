# frozen_string_literal: true

require 'pathname'
require 'set'

module Ruptr
  class GoldenMaster
    GOLDEN_STORE_GOLDEN_FILENAME = 'golden'
    GOLDEN_STORE_TRIAL_FILENAME = 'trial'
    GOLDEN_STORE_TRIAL_PRESERVE_FILENAME = 'trial-preserve'

    def initialize(state_dir,
                   original_test_suite: nil,
                   filtered_test_suite: original_test_suite)
      @state_path = Pathname(state_dir)
      @original_test_suite = original_test_suite
      @filtered_test_suite = filtered_test_suite
    end

    attr_reader :original_test_suite, :filtered_test_suite

    def test_suite = filtered_test_suite || original_test_suite

    def golden_store
      @golden_store ||= begin
        (@state_path / "#{GOLDEN_STORE_TRIAL_PRESERVE_FILENAME}.new").open('w') do |io|
          Marshal.dump(
            if !@original_test_suite
              nil # preserve everything
            elsif @original_test_suite.equal?(@filtered_test_suite)
              [] # preserve nothing
            else
              # preserve records for test elements that have been filtered out
              @original_test_suite.each_test_element_recursive.map(&:path_identifiers) -
                @filtered_test_suite.each_test_element_recursive.map(&:path_identifiers)
            end,
            io
          )
        end
        GoldenMaster::Store::FS.new(
          golden_path: @state_path / GOLDEN_STORE_GOLDEN_FILENAME,
          trial_path: @state_path / GOLDEN_STORE_TRIAL_FILENAME,
        ).tap(&:load_golden)
      end
    end

    def save_trial!
      return unless @golden_store
      (@state_path / "#{GOLDEN_STORE_TRIAL_PRESERVE_FILENAME}.new")
        .rename(@state_path / GOLDEN_STORE_TRIAL_PRESERVE_FILENAME)
      @golden_store.dump_trial
    end

    def accept_trial!
      fail "no trial data" unless (@state_path / GOLDEN_STORE_TRIAL_FILENAME).exist?
      golden_store.accept_trial(
        preserve: (@state_path / GOLDEN_STORE_TRIAL_PRESERVE_FILENAME).open do |io|
                    v = Marshal.load(io)
                    if v.nil?
                      proc { true }
                    else
                      s = v.to_set
                      proc { |(id, _)| s.include?(id) }
                    end
                  end
      )
    end

    class Store
      def initialize
        @golden = {}
        @trial = {}
      end

      def get_golden(k, &)
        @golden.fetch(k, &)
      end

      def set_trial(k, v)
        raise ArgumentError, "key already used: #{k.inspect}" if @trial.include?(k)
        @trial.store(k, v)
      end

      def flush_trial = nil

      def accept_trial(preserve: nil)
        @golden.each_pair { |k, v| @trial[k] = v if !@trial.include?(k) && preserve.call(k) } if preserve
        @golden = @trial
        @trial = {}
      end

      class FS < self
        # The same store must be usable from multiple forked process.  For each process, trial data is
        # accumulated in @trial and appended to the @trial_tmp_path file before the process exits.

        def initialize(golden_path:, trial_path:)
          super()
          @golden_path = golden_path
          @golden_tmp_path = Pathname("#{golden_path}.new")
          @trial_path = trial_path
          @trial_tmp_path = Pathname("#{trial_path}.new")
          @trial_tmp_path.truncate(0) if @trial_tmp_path.exist?
        end

        def load_golden
          # NOTE: The golden file is always a single Marshal chunk.
          @golden = @golden_path.exist? ? @golden_path.open { |io| Marshal.load(io) } : {}
        end

        def load_trial
          # NOTE: The trial file may be made up of multiple Marshal chunks.
          @trial = {}.tap do |h|
            @trial_path.open { |io| h.merge!(Marshal.load(io)) until io.eof? } if @trial_path.exist?
          end
        end

        def flush_trial
          return if @trial.empty?
          @trial_tmp_path.open('a') do |io|
            # Ensuring (hopefully) that the Marshal chunk is appended with a single write(2) call.
            io.sync = true
            # XXX Would be better if Marshal errors were caught earlier.
            io.write(Marshal.dump(@trial))
          end
          @trial.clear
        end

        def dump_trial
          flush_trial
          @trial_tmp_path.rename(@trial_path) if @trial_tmp_path.exist?
        end

        def accept_trial(preserve: nil)
          load_trial
          super
          @golden = @golden.to_a.sort.to_h # keep golden file identical if possible
          @golden_tmp_path.open('w') { |io| Marshal.dump(@golden, io) }
          @golden_tmp_path.rename(@golden_path)
        end
      end
    end
  end
end
