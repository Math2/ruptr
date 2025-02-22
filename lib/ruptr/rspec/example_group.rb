# frozen_string_literal: true

require_relative '../adapters'

module Ruptr
  class Compat
    class RSpec < self
      # Passed to example and hook blocks.
      class Handle
        def initialize(element, exception = nil, &run)
          @element = element
          @exception = exception
          @run = run
        end

        def metadata = @element.metadata
        def exception = @exception
        def run = @run.call(chain)
        def to_proc = @run ? proc { run } : nil
        def chain(&) = self.class.new(@element, @exception, &)
        def caught(exception) = exception ? self.class.new(@element, exception) : self
      end

      # Common for both Examples and ExampleGroups.
      module Element
        DEFAULT_METADATA = {}.freeze
        def metadata = DEFAULT_METADATA
        def label = nil
      end

      class Example
        include Element

        def initialize(label:, metadata:, block:)
          @label = label
          @metadata = metadata
          @block = block
        end

        attr_reader :label, :metadata, :block
      end

      module ExampleGroupInstanceUserMethods
        def skip(reason = nil) = raise SkippedException, reason

        def pending? = @rspec_example_pending
        def pending_reason = @rspec_example_pending_reason

        def pending(reason = nil)
          @rspec_example_pending = true
          @rspec_example_pending_reason = reason
        end
      end

      module ExampleGroupInstanceInternal
        def wrap_context_handle(h) = yield h
        def wrap_context(&) = wrap_context_handle(Handle.new(self.class), &)

        def wrap_example_handle(h) = yield h

        def run_example(example)
          ran = false
          wrap_example_handle(Handle.new(example)) do |h|
            instance_exec(h, &example.block)
            ran = true
          end
          skip unless ran # may happen if an "around" hook didn't call its handle's #run method
        end
      end

      module ExampleGroupInternal
        def carryover_instance_variables(from, to)
          from.instance_variables.each do |name|
            next if from.ruptr_internal_variable?(name)
            to.instance_variable_set(name, from.instance_variable_get(name))
          end
        end

        def my_examples = @my_examples ||= []
        def my_example_groups = @my_example_groups ||= []

        def each_example(&) = my_examples.each(&)
        def each_example_group(&) = my_example_groups.each(&)

        def need_wrap_context? = false
      end

      module ExampleGroupHooks
        def self.def_hook(name, setup_method_name)
          iv_name = :"@#{name}"
          attr_reader name
          define_method(:"#{name}=") do |new|
            instance_variable_set(iv_name, new)
            send(setup_method_name)
            new
          end
        end

        # Context-level hooks are invoked by the runner.  It will recursively call #wrap_context as
        # it traverses the hierarchy of test groups.

        def_hook :context_around_layer_hook, :setup_context_hooks
        def_hook :context_before_hook, :setup_context_hooks
        def_hook :context_after_hook, :setup_context_hooks

        # For example-level hooks, "around" hooks are run in a separate phase that precedes all of
        # the nested "before" and "after" hooks.  This is not supported for context-level hooks, so
        # use "around_layer" semantics for those instead.  The behavior may not be exactly correct
        # (though it seems to be deprecated in RSpec and I'm not sure what the correct behavior
        # actually should be).  This at least makes :suite "around" hooks work as expected (as they
        # are added to the root example group, they will necessarily be run before all of the
        # "before" and "after" hooks without needing a separate phase).

        alias context_around_hook context_around_layer_hook
        alias context_around_hook= context_around_layer_hook=

        def need_wrap_context? = context_around_layer_hook || context_before_hook || context_after_hook

        module ContextHooksInstanceMethods
          def wrap_context_handle(h)
            eg = self.class
            # NOTE: Hooks for the parent example groups will already have been called by the runner.
            k = lambda do |h|
              instance_exec(h, &eg.context_before_hook) if eg.context_before_hook
              yield h
            ensure
              instance_exec(h, &eg.context_after_hook) if eg.context_after_hook
            end
            if eg.context_around_layer_hook
              instance_exec(h.chain(&k), &eg.context_around_layer_hook)
            else
              k.call(h)
            end
          end
        end

        def setup_context_hooks
          include ContextHooksInstanceMethods
        end

        # Example-level hooks are invoked by the test case instance before each example is run.
        # Method inheritance is used to call the hooks of the parent example groups (if any).
        #
        # Two phases are used: the "around" hooks are run in phase 1, the "before", "after" and
        # "around_layer" hooks in phase 2.
        #
        # The "around_layer" hooks behave similarly to "around" but they only wrap around the
        # "before" and "after" hooks of their own (and nested) example groups.

        def_hook :example_around_hook, :setup_example_phase1_hooks
        def_hook :example_around_layer_hook, :setup_example_phase2_hooks
        def_hook :example_before_hook, :setup_example_phase2_hooks
        def_hook :example_after_hook, :setup_example_phase2_hooks

        module ExampleHooksBaseInstanceMethods
          def wrap_example_phase1_hooks(h) = yield h
          def wrap_example_phase2_hooks(h) = yield h
          def wrap_example_handle(h, &) = wrap_example_phase1_hooks(h) { |h| wrap_example_phase2_hooks(h, &) }
        end

        def setup_example_phase1_hooks
          return if method_defined?(:wrap_example_phase1_hooks, false)
          include ExampleHooksBaseInstanceMethods
          eg = self
          define_method(:wrap_example_phase1_hooks) do |down_h, &up|
            super(down_h) { |h| instance_exec(h.chain(&up), &eg.example_around_hook) }
          end
        end

        def setup_example_phase2_hooks
          return if method_defined?(:wrap_example_phase2_hooks, false)
          include ExampleHooksBaseInstanceMethods
          eg = self
          define_method(:wrap_example_phase2_hooks) do |down_h, &up|
            super(down_h) do |h|
              k = if eg.example_before_hook || eg.example_after_hook
                    lambda do |h|
                      instance_exec(h, &eg.example_before_hook) if eg.example_before_hook
                      up.call(h)
                    ensure
                      instance_exec(h.caught($!), &eg.example_after_hook) if eg.example_after_hook
                    end
                  else
                    up
                  end
              if eg.example_around_layer_hook
                instance_exec(h.chain(&k), &eg.example_around_layer_hook)
              else
                k.call(h)
              end
            end
          end
        end
      end

      module SharedContext
        # This is almost identical to the implementation in RSpec 3 rspec-core's
        # lib/rspec/core/shared_context.rb. This makes SharedContext modules behave very similarly
        # to named #shared_examples/#shared_context blocks.
        def included(from)
          super
          ruptr_shared_context_recordings.each do |method_name, args, opts, blk|
            from.__send__(method_name, *args, **opts, &blk)
          end
        end

        def ruptr_shared_context_recordings = @ruptr_shared_context_recordings ||= []

        def self.record(method_name)
          define_method(method_name) do |*args, **opts, &blk|
            ruptr_shared_context_recordings << [method_name, args, opts, blk]
          end
        end
      end

      module ExampleGroupDSL
        module Meta; end
        extend Meta

        def self.extended(from)
          super
          from.singleton_class.extend(Meta)
        end

        def get_args_filter(args, opts)
          args.each { |key| opts[key] = true }
          opts
        end

        def filter_matches?(filter, metadata)
          filter.all? { |k, v| metadata[k] == v }
        end

        def get_args_metadata(extra, args, opts)
          return metadata if (extra.nil? || extra.empty?) && args.empty? && opts.empty?
          new_metadata = metadata.dup
          new_metadata.merge!(extra) if extra
          new_metadata.merge!(opts)
          args.each { |key| new_metadata[key] = true }
          new_metadata
        end

        def example_with_metadata_1(label, metadata, &blk)
          Example.new(
            label: label&.to_s,
            metadata:,
            block: if (reason = metadata[:skip]) || !blk
                     reason = nil if reason == true
                     ->(_h) { raise SkippedException, reason }
                   elsif (reason = metadata[:pending])
                     reason = nil if reason == true
                     ->(h) { pending(reason); instance_exec(h, &blk) }
                   else
                     blk
                   end
          ).tap do |example|
            configuration.apply_to_example(example)
            my_examples << example
          end
        end

        def example_with_metadata(label, metadata, &)
          unless metadata == self.metadata
            done = false
            configuration.apply_to_example_group do
              example_group_with_metadata(nil, metadata, apply_configuration: false) do
                example_with_metadata_1(label, metadata, &)
                done = true
              end
            end
          end
          example_with_metadata_1(label, metadata, &) unless done
        end

        # FIXME: This won't necessarily be unique with examples included from SharedContext modules.
        def default_example_name = "example ##{my_examples.size + 1}"

        module Meta
          def recordable(method_name) = SharedContext.record(method_name)
        end

        recordable def example(label = default_example_name, *args, **opts, &)
          example_with_metadata(label, get_args_metadata(nil, args, opts).freeze, &)
        end

        recordable alias_method :specify, :example
        recordable alias_method :it, :example

        module Meta
          def def_example_shortcut(name, extra_metadata)
            recordable name
            define_method(name) do |label = default_example_name, *args, **opts, &blk|
              example_with_metadata(label, get_args_metadata(extra_metadata, args, opts).freeze, &blk)
            end
          end
        end

        def_example_shortcut :focus, { focus: true }
        def_example_shortcut :fexample, { focus: true }
        def_example_shortcut :fspecify, { focus: true }
        def_example_shortcut :fit, { focus: true }

        def_example_shortcut :skip, { skip: true }
        def_example_shortcut :xexample, { skip: "Temporarily skipped with xexample" }
        def_example_shortcut :xspecify, { skip: "Temporarily skipped with xspecify" }
        def_example_shortcut :xit, { skip: "Temporarily skipped with xit" }

        def_example_shortcut :pending, { pending: true }

        def example_group_with_metadata(label, metadata, apply_configuration: true, &)
          Class.new(self) do
            define_singleton_method(:metadata) { metadata }
            define_singleton_method(:label) { label&.to_s }
            if label.is_a?(Module)
              define_singleton_method(:described_class) { label }
              define_method(:described_class) { label }
              if label.is_a?(Class)
                let(:subject) { label.new }
              else
                let(:subject) { label }
              end
            end
            configuration.apply_to_example_group(self) if apply_configuration
            class_exec(&) if block_given?
          end.tap { |example_group| my_example_groups << example_group }
        end

        recordable def example_group(label = nil, *args, **opts, &)
          example_group_with_metadata(label, get_args_metadata(nil, args, opts).freeze, &)
        end

        recordable alias_method :describe, :example_group
        recordable alias_method :context, :example_group

        module Meta
          def def_example_group_shortcut(name, extra_metadata)
            recordable name
            define_method(name) do |label, *args, **opts, &blk|
              example_group_with_metadata(label, get_args_metadata(extra_metadata, args, opts).freeze, &blk)
            end
          end
        end

        def_example_group_shortcut :fdescribe, { focus: true }
        def_example_group_shortcut :fcontext, { focus: true }
        def_example_group_shortcut :xdescribe, { skip: "Temporarily skipped with xdescribe" }
        def_example_group_shortcut :xcontext, { skip: "Temporarily skipped with xcontext" }

        def lookup_shared_examples(_name) = nil
        def shared_examples_stash = nil

        recordable def shared_examples(name, *args, **opts, &body)
          _child_metadata = get_args_metadata(nil, args, opts).freeze # TODO
          unless singleton_class.method_defined?(:shared_examples_stash, false)
            stash = {}
            define_singleton_method(:shared_examples_stash) { stash }
            define_singleton_method(:lookup_shared_examples) { |name| stash[name] || super(name) }
          end
          shared_examples_stash[name] = body
        end

        recordable alias_method :shared_examples_for, :shared_examples
        recordable alias_method :shared_context, :shared_examples

        def examples_included?(_name) = false
        def included_examples = nil

        recordable def include_examples(name, *args, **opts, &)
          return if examples_included?(name)
          unless singleton_class.method_defined?(:included_examples, false)
            included = []
            define_singleton_method(:examples_included?) { |name| included.include?(name) || super(name) }
            define_singleton_method(:included_examples) { included }
          end
          class_exec(*args, **opts, &lookup_shared_examples(name))
          included_examples << name
          class_exec(&) if block_given?
        end

        recordable alias_method :include_context, :include_examples

        recordable def it_behaves_like_with_label(name, label, *args, **opts, &)
          context(label) do
            include_examples(name, *args, **opts)
            class_exec(&) if block_given?
          end
        end

        module Meta
          def def_it_behaves_like_shortcut(shortcut_name, make_label = ->(name) { "it behaves like #{name}" })
            recordable shortcut_name
            define_method(shortcut_name) do |name, *args, **opts, &blk|
              it_behaves_like_with_label(name, make_label.call(name), *args, **opts, &blk)
            end
          end
        end

        def_it_behaves_like_shortcut :it_behaves_like
        recordable alias_method :it_should_behave_like, :it_behaves_like

        recordable def let(method_name, &)
          name = case
                 when method_name.end_with?('?') then :"rspec__#{method_name.name.chop}__p"
                 when method_name.end_with?('!') then :"rspec__#{method_name.name.chop}__d"
                 else :"rspec__#{method_name.name}"
                 end
          define_method(:"#{name}__uncached", &)
          module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
            def #{method_name} = defined?(@#{name}) ? @#{name} : (@#{name} = #{name}__uncached)
          RUBY
        end

        recordable def let!(name, &)
          let(name, &)
          before { public_send(name) }
        end

        recordable def subject(name = :subject, &)
          let(name, &)
          alias_method(:subject, name) if name != :subject
        end

        recordable def subject!(name = :subject, &)
          subject(name, &)
          before { public_send(name) }
        end

        def wrap_hook_block_with_metadata_test(args, opts, blk, around: false)
          filter = get_args_filter(args, opts)
          return blk if filter.empty?
          if around
            ->(h) { ExampleGroup.filter_matches?(filter, h.metadata) ? instance_exec(h, &blk) : h.run }
          else
            ->(h) { instance_exec(h, &blk) if ExampleGroup.filter_matches?(filter, h.metadata) }
          end
        end

        def self.def_hook_adder(method_name, hook_name, around: false)
          example_get_name = :"example_#{hook_name}"
          example_set_name = :"example_#{hook_name}="
          context_get_name = :"context_#{hook_name}"
          context_set_name = :"context_#{hook_name}="
          recordable method_name
          define_method(method_name) do |scope = :example, *args, **opts, &new|
            new = wrap_hook_block_with_metadata_test(args, opts, new, around:)
            eg = self
            case scope
            when :example, :each
              get_name, set_name = example_get_name, example_set_name
            when :context, :all
              get_name, set_name = context_get_name, context_set_name
            when :suite
              get_name, set_name = context_get_name, context_set_name
              eg = superclass while eg >= ExampleGroup
            else
              raise ArgumentError, "unsupported scope: #{scope}"
            end
            eg.public_send(set_name, (old = public_send(get_name)) ? yield(new, old) : new)
          end
        end

        def_hook_adder(:around, :around_hook, around: true) do |new, old|
          ->(h) { instance_exec(h.chain { instance_exec(h, &new) }, &old) }
        end

        def_hook_adder(:around_layer, :around_layer_hook, around: true) do |new, old|
          ->(h) { instance_exec(h.chain { instance_exec(h, &new) }, &old) }
        end

        def_hook_adder(:before, :before_hook) do |new, old|
          ->(h) { instance_exec(h, &old); instance_exec(h, &new) }
        end

        def_hook_adder(:prepend_before, :before_hook) do |new, old|
          ->(h) { instance_exec(h, &new); instance_exec(h, &old) }
        end

        def_hook_adder(:after, :after_hook) do |new, old|
          ->(h) { begin instance_exec(h, &new) ensure instance_exec(h.caught($!), &old) end }
        end

        def_hook_adder(:append_after, :after_hook) do |new, old|
          ->(h) { begin instance_exec(h, &old) ensure instance_exec(h.caught($!), &new) end }
        end
      end

      class ExampleGroup
        extend Element
        extend ExampleGroupInternal
        extend ExampleGroupHooks
        extend ExampleGroupDSL
        include ExampleGroupInstanceInternal
        include Ruptr::TestInstance
        include ExampleGroupInstanceUserMethods
      end
    end
  end
end
