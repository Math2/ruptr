# frozen_string_literal: true

require_relative 'suite'

module Ruptr
  class Compat
    def filter_test_group(tg) = tg

    def adapted_test_suite
      filter_test_group(TestSuite.new.tap { |ts| ts.add_test_subgroup(adapted_test_group) })
    end

    def global_install! = nil
    def global_uninstall! = nil
    def global_monkey_patch! = nil
    def finalize_configuration! = nil

    def default_project_load_paths = []

    def default_project_test_globs = []

    def each_default_project_test_file(project_path, &)
      return to_enum(__method__, project_path) unless block_given?
      project_path.glob(default_project_test_globs, &)
    end
  end
end
