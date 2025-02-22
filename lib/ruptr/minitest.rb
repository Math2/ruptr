# frozen_string_literal: true

require_relative 'suite'
require_relative 'compat'
require_relative 'autorun'
require_relative 'adapters/assertions'

module Ruptr
  class Compat
    class Minitest < self
      def default_project_load_paths = %w[test]

      def default_project_test_globs = %w[test/**/*_test.rb test/**/test_*.rb]

      def global_install!
        if Object.const_defined?(:Minitest)
          return if Object.const_get(:Minitest) == @adapter_module
          fail "minitest already loaded!"
        end
        Object.const_set(:Minitest, adapter_module)
        this = self
        m = Module.new do
          define_method(:require) do |name|
            name = name.to_path unless name.is_a?(String)
            case name
            when 'minitest', 'minitest/test', 'minitest/proveit', 'minitest/hooks'
              return
            when 'minitest/autorun'
              this.schedule_autorun!
              return
            when 'minitest/stub_const'
              nil
            else
              fail "#{self.class.name}: unknown minitest library: #{name}" if name.start_with?('minitest/')
            end
            super(name)
          end
        end
        Kernel.prepend(m)
      end

      def adapter_module
        @adapter_module ||= Module.new do
          def self.def_module(name, &) = const_set(name, Module.new(&))
          def self.def_class(name, &) = const_set(name, Class.new(&))

          const_set(:Assertion, Ruptr::Assertions::AssertionError)

          def_module(:Assertions) do
            include Adapters::RuptrAssertions
          end

          def_module(:Hooks) do
            # TODO: #around_all/#before_all/#after_all

            def around = yield

            def ruptr_wrap_test_instance
              ran = false
              super do
                around do
                  yield
                  ran = true
                end
              end
              raise SkippedException unless ran
            end
          end

          adapter_module = self

          def_class(:Test) do
            def self.parallelize_me! = nil

            def self.prove_it? = false
            def self.prove_it! = define_singleton_method(:prove_it?) { true }

            def name
              @test_method_name
            end

            def name=(v)
              @test_method_name = v
            end

            def prove_it
              flunk("Prove it!") if self.class.prove_it? && ruptr_assertions_count.zero?
            end

            def setup = nil
            def teardown = nil

            include TestInstance
            include adapter_module::Assertions
          end
        end
      end

      private def make_run_block(klass, method_name)
        lambda do |context|
          inst = klass.new
          inst.name = method_name
          inst.ruptr_initialize_test_instance(context)
          inst.ruptr_wrap_test_instance do
            inst.setup
            inst.public_send(method_name)
            inst.prove_it
          ensure
            inst.teardown
          end
        end
      end

      def adapted_test_group
        # TODO: Test descriptions should be "<class_name>#<method_name>"?
        traverse = lambda do |klass|
          root = klass.equal?(adapter_module::Test)
          TestGroup.new(root ? "[Minitest]" : klass.name,
                        identifier: root ? :minitest : klass.name).tap do |tg|
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
        traverse.call(adapter_module::Test)
      end
    end
  end
end
