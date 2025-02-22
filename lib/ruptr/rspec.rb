# frozen_string_literal: true

require_relative 'suite'
require_relative 'compat'
require_relative 'autorun'
require_relative 'rspec/example_group'
require_relative 'rspec/configuration'

module Ruptr
  class Compat
    class RSpec < self
      def default_project_load_paths = %w[spec]

      def default_project_test_globs = %w[spec/**/*_spec.rb]

      def global_install!
        if Object.const_defined?(:RSpec)
          return if Object.const_get(:RSpec) == @adapter_module
          fail "rspec already loaded!"
        end
        Object.const_set(:RSpec, adapter_module)
        this = self
        m = Module.new do
          define_method(:require) do |name|
            name = name.to_path unless name.is_a?(String)
            if name.start_with?('rspec/')
              case name.delete_prefix('rspec/')
              when 'version',
                   'support',
                   %r{\Asupport/},
                   'matchers',
                   %r{\Amatchers/},
                   'expectations',
                   %r{\Aexpectations/},
                   'mocks',
                   %r{\Amocks/}
                nil
              when 'core'
                return
              when 'autorun'
                this.schedule_autorun!
                return
              else
                fail "#{self.class.name}: unknown rspec library: #{name}"
              end
            end
            super(name)
          end
        end
        Kernel.prepend(m)
      end

      def global_monkey_patch!
        a = adapter_module
        m = Module.new do
          extend Forwardable
          define_method(:ruptr_rspec_adapter) { a }
          def_delegators :ruptr_rspec_adapter,
                         :describe, :context,
                         :shared_examples, :shared_examples_for, :shared_context
        end
        TOPLEVEL_BINDING.receiver.extend(m)
        Module.prepend(m)
      end

      def load_default_frameworks
        adapter_module.configure do |config|
          if config.expectation_frameworks.empty? && config.mock_frameworks.empty? ||
             config.expectation_frameworks.include?(:rspec) && config.mock_frameworks.include?(:rspec)
            begin
              config.expect_with(:rspec)
            rescue LoadError
            end
            begin
              config.mock_with(:rspec)
            rescue LoadError
            end
          end
        end
      end

      def finalize_configuration!
        load_default_frameworks
      end

      class Adapter < Module
        extend Forwardable

        def configuration = @configuration ||= Configuration.new(self)

        def configure = yield configuration

        def_delegators :root_example_group,
                       :example_group, :describe, :context,
                       :fdescribe, :fcontext, :xdescribe, :xcontext,
                       :shared_examples, :shared_examples_for, :shared_context,
                       :before, :after
      end

      def adapter_module
        @adapter_module ||= begin
          adapter_module = Adapter.new
          root_example_group = Class.new(ExampleGroup)
          adapter_module.define_singleton_method(:root_example_group) { root_example_group }
          root_example_group.define_singleton_method(:configuration) { adapter_module.configuration }
          shared_context_module = SharedContext.dup
          shared_context_module.define_method(:configuration) { adapter_module.configuration }
          adapter_module.const_set(:SharedContext, shared_context_module)
          adapter_module
        end
      end

      private def make_test_case(example_group, example)
        TestCase.new(example.label, tags: example.metadata) do |context|
          instance = example_group.new
          context.rspec_carryover_instance_variables(instance) # XXX
          instance.ruptr_initialize_test_instance(context)
          begin
            instance.ruptr_wrap_test_instance { instance.run_example(example) }
          rescue *Ruptr.passthrough_exceptions,
                 SkippedExceptionMixin
            raise
          rescue Exception
            raise PendingSkippedException, instance.pending_reason if instance.pending?
            raise
          else
            raise PendingPassedError, instance.pending_reason if instance.pending?
          end
        end
      end

      private def make_test_group(example_group)
        block = if example_group.need_wrap_context?
                  lambda do |context, &nest|
                    instance = example_group.new
                    context.rspec_carryover_instance_variables(instance) # XXX
                    instance.ruptr_initialize_test_instance(context)
                    instance.ruptr_wrap_test_instance { instance.wrap_context(&nest) }
                  end
                end
        root = example_group.equal?(adapter_module.root_example_group)
        TestGroup.new(root ? "[RSpec]" : example_group.label,
                      identifier: root ? :rspec : example_group.label,
                      tags: example_group.metadata, &block)
      end

      def adapted_test_group
        traverse = lambda do |example_group|
          make_test_group(example_group).tap do |tg|
            example_group.each_example do |example|
              tc = make_test_case(example_group, example)
              tg.add_test_case(tc)
            end
            example_group.each_example_group do |child_example_group|
              tg.add_test_subgroup(traverse.call(child_example_group))
            end
          end
        end
        traverse.call(adapter_module.root_example_group)
      end

      def filter_test_group(test_group)
        conf = adapter_module.configuration

        return test_group if conf.inclusion_filter.empty? && conf.exclusion_filter.empty?

        matches_inclusion_filters = lambda do |tc|
          conf.inclusion_filter.empty? ||
            conf.inclusion_filter.any? { |f| ExampleGroup.filter_matches?(f, tc.tags) }
        end
        matches_exclusion_filters = lambda do |tc|
          conf.exclusion_filter.empty? ||
            conf.exclusion_filter.none? { |f| ExampleGroup.filter_matches?(f, tc.tags) }
        end

        test_group = super
        filtered_test_group = test_group.filter_test_cases_recursive do |tc|
          matches_exclusion_filters === tc && matches_inclusion_filters === tc
        end
        if conf.run_all_when_everything_filtered &&
           filtered_test_group.count_test_cases.zero?
          filtered_test_group = test_group.filter_test_cases_recursive do |tc|
            matches_exclusion_filters === tc
          end
        end

        filtered_test_group
      end

      class Ruptr::Context
        attr_accessor :rspec_example_group_instance,
                      :rspec_example_group_instance_variables_carried_over

        def rspec_carryover_instance_variables(instance)
          context = parent
          loop do
            if context.rspec_example_group_instance_variables_carried_over
              if (parent_instance = context.rspec_example_group_instance)
                ExampleGroup.carryover_instance_variables(parent_instance, instance)
              end
              break
            end
            context = context.parent or break
          end
          self.rspec_example_group_instance = instance # XXX
          self.rspec_example_group_instance_variables_carried_over = true;
        end
      end
    end
  end
end
