# frozen_string_literal: true

require_relative 'suite'
require_relative 'utils'

module Ruptr
  class Compat
    def prepare_autorun!(test_suite = Ruptr::TestSuite.global_autorun_test_suite)
      @autorun_test_suite = test_suite
      global_install!
    end

    def schedule_autorun!
      return if @autorun_scheduled
      return unless @autorun_test_suite
      @autorun_test_suite.run_on_exit!
      Ruptr.at_normal_exit do
        finalize_configuration!
        @autorun_test_suite.add_test_subgroup(adapted_test_group)
      end
      @autorun_scheduled = true
    end
  end

  class TestSuite
    def self.global_autorun_test_suite = @global_autorun_test_suite ||= TestSuite.new

    def run_on_exit!
      return if @run_on_exit
      require_relative 'runner'
      require_relative 'formatter'
      Ruptr.at_normal_exit do
        Runner.from_env.run_sink(self, Formatter.from_env($stdout))
      end
      @run_on_exit = true
    end
  end
end
