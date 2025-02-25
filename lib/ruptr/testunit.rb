# frozen_string_literal: true

require_relative 'suite'
require_relative 'compat'
require_relative 'autorun'
require_relative 'adapters/assertions'

module Ruptr
  class Compat
    class TestUnit < self
      def default_project_load_paths = %w[test]

      def default_project_test_globs = %w[test/**/*[-_]test.rb test/**/test[-_]*.rb]

      def global_install!
        m = if Object.const_defined?(:Test)
              Object.const_get(:Test)
            else
              Object.const_set(:Test, Module.new)
            end
        if m.const_defined?(:Unit)
          return if m.const_get(:Unit) == @adapter_module
          fail "test/unit already loaded!"
        end
        ::Test.const_set(:Unit, adapter_module)
        this = self
        m = Module.new do
          define_method(:require) do |name|
            name = name.to_path unless name.is_a?(String)
            case name
            when 'test/unit'
              return
            when 'test/unit/autorun'
              this.schedule_autorun!
              return
            when 'core_assertions'
              # Test::Unit::CoreAssertions#assert_separately spawns an interpreter with gems
              # disabled and include path arguments based on the current $LOAD_PATH.
              Gem.try_activate('test/unit')
            else
              fail "#{self.class.name}: unknown test/unit library: #{name}" if name.start_with?('test/unit/')
            end
            super(name)
          end
        end
        Kernel.prepend(m)
      end

      module DefBlockHelpers
        def def_module(name, &) = const_set(name, Module.new(&))
        def def_class(name, &) = const_set(name, Class.new(&))
      end

      def adapter_module
        @adapter_module ||= Module.new do
          extend(DefBlockHelpers)

          const_set :PendedError, Assertions::SkippedException
          const_set :AssertionFailedError, Assertions::AssertionError

          def_module(:Util) do
            extend(DefBlockHelpers)
            def_module(:Output) do
              def capture_output(&) = Assertions.capture_io(&)
            end
          end

          assertions_module = def_module(:Assertions) do
            include(Adapters::RuptrAssertions)
            # NOTE: Gem test-unit-ruby-core's "core_assertions" library will define some methods
            # directly in Test::Unit::Assertions.
          end

          def_class(:TestCase) do
            include(TestInstance)
            include(assertions_module)

            attr_accessor :method_name

            def setup = nil
            def teardown = nil
          end
        end
      end

      private def make_run_block(klass, method_name)
        lambda do |context|
          inst = klass.new
          inst.method_name = method_name
          inst.ruptr_initialize_test_instance(context)
          inst.ruptr_wrap_test_instance do
            inst.setup
            inst.public_send(method_name)
          ensure
            inst.teardown
          end
        end
      end

      def adapted_test_group
        traverse = lambda do |klass|
          root = klass.equal?(adapter_module::TestCase)
          TestGroup.new(root ? "[TestUnit]" : klass.name,
                        identifier: root ? :testunit : klass.name).tap do |tg|
            klass.public_instance_methods(true)
                 .filter { |sym| sym.start_with?('test_') }.each do |test_method_name|
              tc = TestCase.new(test_method_name.to_s, &make_run_block(klass, test_method_name))
              tg.add_test_case(tc)
            end
            klass.subclasses.each do |subklass|
              tg.add_test_subgroup(traverse.call(subklass))
            end
          end
        end
        traverse.call(adapter_module::TestCase)
      end
    end
  end
end
