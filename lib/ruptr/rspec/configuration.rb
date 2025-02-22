# frozen_string_literal: true

require 'forwardable'
require 'set'

module Ruptr
  class Compat
    class RSpec < self
      class Adapter < Module
        class Configuration
          extend Forwardable

          def initialize(adapter)
            @adapter_module = adapter
            @delayed_example_group_alterations = []
            @delayed_example_alterations = []
            @inclusion_filter = []
            @exclusion_filter = []
            @run_all_when_everything_filtered = false
            @expectation_frameworks = Set.new
            @mock_frameworks = Set.new
          end

          attr_reader :adapter_module

          def disable_monkey_patching! = nil # TODO

          def color_enabled? = false # used in RSpec::Expectations::Configuration

          def full_backtrace=(v)
            raise ArgumentError, "unsupported" if v
          end

          def full_backtrace? = true

          def order=(v)
            raise ArgumentError, "unsupported" if v.to_sym != :random
          end

          def threadsafe = false

          def threadsafe=(v)
            # NOTE: The framework supports running the examples in multiple threads, but the example
            # blocks themselves should not call the framework from multiple threads.  This can be a
            # problem with memoized "let" helpers for example (but using "let!" helpers is fine).
            raise ArgumentError, "unsupported" if v
          end

          private def delayed_example_group_alteration(filter)
            @delayed_example_group_alterations << lambda do |example_group|
              next unless ExampleGroup.filter_matches?(filter, example_group.metadata)
              yield example_group
            end
          end

          def apply_to_example_group(example_group = nil)
            @delayed_example_group_alterations.each { |p| p.call(example_group ||= yield) }
          end

          private def delayed_example_alteration(filter)
            @delayed_example_alterations << lambda do |example|
              next unless ExampleGroup.filter_matches?(filter, example.metadata)
              yield example
            end
          end

          def apply_to_example(example = nil)
            @delayed_example_alterations.each { |p| p.call(example ||= yield) }
          end

          %i[include prepend extend].each do |name|
            define_method(name) do |m, *args, **opts|
              delayed_example_group_alteration(ExampleGroup.get_args_filter(args, opts)) do |example_group|
                example_group.send(name, m)
              end
            end
          end

          def include_context(include_name, *args, **opts)
            delayed_example_group_alteration(ExampleGroup.get_args_filter(args, opts)) do |example_group|
              example_group.include_context(include_name)
            end
          end

          def on_example_group_definition(&)
            delayed_example_group_alteration({}, &)
          end

          def when_first_matching_example_defined(*args, **opts)
            first = true
            delayed_example_alteration(ExampleGroup.get_args_filter(args, opts)) do |example|
              next unless first
              yield example
              first = false
            end
          end

          attr_accessor :inclusion_filter, :exclusion_filter,
                        :run_all_when_everything_filtered

          def filter_run_including(*args, **opts)
            inclusion_filter << ExampleGroup.get_args_filter(args, opts)
          end

          alias filter_run filter_run_including

          def filter_run_excluding(*args, **opts)
            exclusion_filter << ExampleGroup.get_args_filter(args, opts)
          end

          def filter_run_when_matching(*args, **opts)
            when_first_matching_example_defined(*args, **opts) { filter_run_including(*args, **opts) }
          end

          def silence_filter_announcements = true

          def silence_filter_announcements=(v)
            raise ArgumentError, "unsupported" if v
          end

          attr_reader :expectation_frameworks

          private def expect_with_1(handler)
            case handler
            when Module
              root_example_group.include(handler)
            when :test_unit, :minitest
              require 'ruptr/adapters/assertions'
              root_example_group.include(Adapters::RuptrAssertions)
            when :rspec
              require 'ruptr/adapters/rspec_expect'
              root_example_group.include(Adapters::RSpecExpect)
              root_example_group.include(Adapters::RSpecExpect::Helpers)
            else
              raise ArgumentError, "#{handler} not supported"
            end
            @expectation_frameworks << handler
          end

          def expect_with(*handlers)
            handlers.each { |handler| expect_with_1(handler) }
          end

          attr_reader :mock_frameworks

          private def mock_with_1(handler)
            case handler
            when :rspec
              require 'ruptr/adapters/rspec_mocks'
              root_example_group.include(Adapters::RSpecMocks)
              root_example_group.include(Adapters::RSpecMocks::Helpers)
            else
              raise ArgumentError, "#{handler} not supported"
            end
            @mock_frameworks << handler
          end

          def mock_with(*handlers)
            handlers.each { |handler| mock_with_1(handler) }
          end

          def alias_example_group_to(name, *args, **opts)
            metadata = ExampleGroup.get_args_filter(args, opts)
            root_example_group.singleton_class.def_example_group_shortcut(name, metadata)
            adapter_module.singleton_class.def_delegators(:root_example_group, name)
          end

          def alias_example_to(name, *args, **opts)
            metadata = ExampleGroup.get_args_filter(args, opts)
            root_example_group.singleton_class.def_example_shortcut(name, metadata)
            adapter_module.singleton_class.def_delegators(:root_example_group, name)
          end

          def alias_it_behaves_like_to(name, label_prefix)
            root_example_group.singleton_class.def_it_behaves_like_shortcut(
              name, ->(example_group_name) { "#{label_prefix} #{example_group_name}" }
            )
            adapter_module.singleton_class.def_delegators(:root_example_group, name)
          end

          alias alias_it_should_behave_like_to alias_it_behaves_like_to

          def_delegators :adapter_module,
                         :root_example_group
          def_delegators :root_example_group,
                         :before, :prepend_before, :after, :append_after, :around
        end
      end
    end
  end
end
