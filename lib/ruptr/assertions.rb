# frozen_string_literal: true

require_relative 'capture_output'

module Ruptr
  module Assertions
    class AssertionError < StandardError; end

    class UnexpectedExceptionError < AssertionError; end

    class UnexpectedValueError < AssertionError
      def initialize(message = nil, actual:)
        super(message)
        @actual = actual
      end

      attr_reader :actual
    end

    class EquivalenceAssertionError < UnexpectedValueError
      def initialize(message = nil, actual:, expected:)
        super(message, actual:)
        @expected = expected
      end

      attr_reader :expected
    end

    class EquivalenceRefutationError < UnexpectedValueError
      def initialize(message = nil, actual:, unexpected:)
        super(message, actual:)
        @unexpected = unexpected
      end

      attr_reader :unexpected
    end

    class SkippedException < Exception; end

    private

    def bump_assertions_count = nil
    def bump_skipped_blocks_count = nil

    def assertion_inspect_complete(val) = val.inspect
    def assertion_inspect_truncate = 256

    def assertion_inspect(val)
      str = assertion_inspect_complete(val)
      if (n = assertion_inspect_truncate) && str.length > n
        str = "#{str[0, n]}... (truncated)"
      end
      str
    end

    def assertion_capture_value(v) = v

    def get_assertion_message(msg)
      msg.is_a?(Proc) ? msg.call : msg
    end

    public

    def assertion_raise(klass, msg, ...)
      raise klass.new(get_assertion_message(msg), ...)
    end

    def assertion_failed(msg)
      assertion_raise(AssertionError, msg)
    end

    def assertion_unexpected_exception(exc, msg = nil)
      assertion_raise(UnexpectedExceptionError, msg || "unexpected exception: #{assertion_inspect(exc)}")
    end

    def assertion_unexpected_value(val, msg = nil)
      assertion_raise(UnexpectedValueError, msg || "unexpected value: #{assertion_inspect(val)}",
                      actual: assertion_capture_value(val))
    end

    def pass(_msg = nil)
      bump_assertions_count
    end

    def flunk(msg = nil)
      bump_assertions_count
      assertion_failed(msg || "Flunked")
    end

    def assert(val, msg = nil)
      bump_assertions_count
      return if val
      assertion_unexpected_value(val, msg || "expected #{assertion_inspect(val)} to be truthy")
    end

    def refute(val, msg = nil)
      bump_assertions_count
      return unless val
      assertion_unexpected_value(val, msg || "expected #{assertion_inspect(val)} to be falsey")
    end

    alias assert_not refute

    def assert_block(msg = nil) = assert(yield, msg)
    def refute_block(msg = nil) = refute(yield, msg)
    alias assert_not_block refute_block

    def assert_equal(exp, act, msg = nil)
      bump_assertions_count
      return if exp == act
      assertion_raise(EquivalenceAssertionError,
                      msg || "expected #{assertion_inspect(act)} to be #{assertion_inspect(exp)}",
                      actual: assertion_capture_value(act),
                      expected: assertion_capture_value(exp))
    end

    def refute_equal(exp, act, msg = nil)
      bump_assertions_count
      return unless exp == act
      assertion_raise(EquivalenceRefutationError,
                      msg || "expected #{assertion_inspect(act)} to be something else",
                      actual: assertion_capture_value(act),
                      unexpected: assertion_capture_value(exp))
    end

    alias assert_not_equal refute_equal

    def assert_match(pat, act, msg = nil)
      bump_assertions_count
      pat = Regexp.new(Regexp.quote(pat)) if pat.is_a?(String)
      return $~ if pat =~ act
      assertion_unexpected_value(act, msg || "expected #{assertion_inspect(pat)} " \
                                             "to match #{assertion_inspect(act)}")
    end

    def refute_match(pat, act, msg = nil)
      bump_assertions_count
      pat = Regexp.new(Regexp.quote(pat)) if pat.is_a?(String)
      return unless pat =~ act
      assertion_unexpected_value(act, msg || "expected #{assertion_inspect(pat)} " \
                                             "not to match #{assertion_inspect(act)}")
    end

    alias assert_not_match refute_match
    alias assert_no_match refute_match

    def assert_pattern(msg = nil)
      yield
    rescue NoMatchingPatternError
      bump_assertions_count
      assertion_failed(msg || $!.message)
    else
      bump_assertions_count
    end

    def refute_pattern(msg = nil)
      yield
    rescue NoMatchingPatternError
      bump_assertions_count
    else
      bump_assertions_count
      assertion_failed(msg || "expected pattern not to match")
    end

    def assert_true(val, msg = nil) = assert_equal(true, val, msg)
    def assert_false(val, msg = nil) = assert_equal(false, val, msg)
    def assert_boolean(val, msg = nil) = assert_includes([true, false], val, msg)

    def assert_predicate(target, pred, msg = nil)
      bump_assertions_count
      return if target.public_send(pred)
      assertion_unexpected_value(target, msg || "expected #{assertion_inspect(target)} to be #{pred}")
    end

    def refute_predicate(target, pred, msg = nil)
      bump_assertions_count
      return unless target.public_send(pred)
      assertion_unexpected_value(target, msg || "expected #{assertion_inspect(target)} not to be #{pred}")
    end

    alias assert_not_predicate refute_predicate

    def assert_operator(arg1, oper, arg2 = (no_arg2 = true; nil), msg = nil)
      return assert_predicate(arg1, oper, msg) if no_arg2
      bump_assertions_count
      return if arg1.public_send(oper, arg2)
      assertion_unexpected_value(arg1, msg || "expected #{assertion_inspect(arg1)} " \
                                              "to be #{oper} #{assertion_inspect(arg2)}")
    end

    alias assert_compare assert_operator

    def refute_operator(arg1, oper, arg2 = (no_arg2 = true; nil), msg = nil)
      return refute_predicate(arg1, oper, msg) if no_arg2
      bump_assertions_count
      return unless arg1.public_send(oper, arg2)
      assertion_unexpected_value(arg1, msg || "expected #{assertion_inspect(arg1)} " \
                                              "not to be #{oper} #{assertion_inspect(arg2)}")
    end

    alias assert_not_operator refute_operator

    def assert_all(enum, msg = nil, &)
      bump_assertions_count
      return if enum.all?(&)
      assertion_unexpected_value(enum, msg || "expected truthy block for all elements of #{assertion_inspect(enum)}")
    end

    def assert_send(array, msg = nil)
      target, method_name, *args = array
      bump_assertions_count
      return if target.__send__(method_name, *args)
      assertion_unexpected_value(target,
                                 msg || "expected #{assertion_inspect(target)}.#{method_name}" \
                                        "(#{args.map { |arg| assertion_inspect(arg) }.join(', ')}) to be truthy")
    end

    def refute_send(array, msg = nil)
      target, method_name, *args = array
      bump_assertions_count
      return unless target.__send__(method_name, *args)
      assertion_unexpected_value(target,
                                 msg || "expected #{assertion_inspect(target)}.#{method_name}" \
                                        "(#{args.map { |arg| assertion_inspect(arg) }.join(', ')}) not to be truthy")
    end

    alias assert_not_send refute_send

    def assert_in_delta(exp, act, delta = 0.001, msg = nil)
      raise ArgumentError if delta.negative?
      bump_assertions_count
      return if (exp - act).abs <= delta
      assertion_unexpected_value(act, msg || "expected #{assertion_inspect(act)} to be within " \
                                             "#{assertion_inspect(delta)} of #{assertion_inspect(exp)}")
    end

    def refute_in_delta(exp, act, delta = 0.001, msg = nil)
      raise ArgumentError if delta.negative?
      bump_assertions_count
      return if (exp - act).abs > delta
      assertion_unexpected_value(act, msg || "expected #{assertion_inspect(act)} not to be within " \
                                             "#{assertion_inspect(delta)} of #{assertion_inspect(exp)}")
    end

    alias assert_not_in_delta refute_in_delta

    def assert_in_epsilon(exp, act, epsilon = 0.001, msg = nil)
      assert_in_delta(exp, act, exp.zero? ? epsilon : exp.abs * epsilon, msg)
    end

    def refute_in_epsilon(exp, act, epsilon = 0.001, msg = nil)
      refute_in_delta(exp, act, exp.zero? ? epsilon : exp.abs * epsilon, msg)
    end

    alias assert_not_in_epsilon refute_in_epsilon

    def assert_path_exists(path, msg = nil)
      assert File.exist?(path), msg || "expected path #{assertion_inspect(path)} to exist"
    end

    def refute_path_exists(path, msg = nil)
      refute File.exist?(path), msg || "expected path #{assertion_inspect(path)} not to exist"
    end

    alias assert_path_exist assert_path_exists
    alias assert_path_not_exist refute_path_exists

    def assert_alias_method(obj, name1, name2, msg = nil)
      bump_assertions_count
      return if obj.method(name1) == obj.method(name2)
      assertion_unexpected_value(obj, msg || "expected #{assertion_inspect(obj)} " \
                                             "to have methods #{name1} and #{name2} be aliased")
    end

    def refute_alias_method(obj, name1, name2, msg = nil)
      bump_assertions_count
      return unless obj.method(name1) == obj.method(name2)
      assertion_unexpected_value(obj, msg || "expected #{assertion_inspect(obj)} " \
                                             "to not have methods #{name1} and #{name2} be aliased")
    end

    alias assert_not_alias_method refute_alias_method

    def assert_golden(actual, msg = nil, key: nil)
      assertion_set_golden_trial_value(key, actual)
      # NOTE: does not yield if there are no golden value saved yet
      assertion_yield_golden_value(key) do |golden|
        if block_given?
          yield golden, actual, msg
        else
          assert_equal golden, actual, msg
        end
      end
    end

    def self.def_predicate_shortcut(shortcut_name_suffix, predicate_name)
      define_method(:"assert_#{shortcut_name_suffix}") do |target, msg = nil|
        assert_predicate target, predicate_name, msg
      end
      define_method(:"refute_#{shortcut_name_suffix}") do |target, msg = nil|
        refute_predicate target, predicate_name, msg
      end
      alias_method(:"assert_not_#{shortcut_name_suffix}", :"refute_#{shortcut_name_suffix}")
    end

    def self.def_operator_shortcut(shortcut_name_suffix, operator_name, swapped: false)
      define_method(:"assert_#{shortcut_name_suffix}") do |arg1, arg2, msg = nil|
        arg1, arg2 = arg2, arg1 if swapped
        assert_operator arg1, operator_name, arg2, msg
      end
      define_method(:"refute_#{shortcut_name_suffix}") do |arg1, arg2, msg = nil|
        arg1, arg2 = arg2, arg1 if swapped
        refute_operator arg1, operator_name, arg2, msg
      end
      alias_method(:"assert_not_#{shortcut_name_suffix}", :"refute_#{shortcut_name_suffix}")
    end

    def_predicate_shortcut :nil, :nil?
    def_predicate_shortcut :empty, :empty?
    def_operator_shortcut :same, :equal?
    def_operator_shortcut :case_equal, :===
    def_operator_shortcut :respond_to, :respond_to?
    def_operator_shortcut :includes, :include?
    def_operator_shortcut :include, :include?
    def_operator_shortcut :instance_of, :instance_of?, swapped: true
    def_operator_shortcut :kind_of, :kind_of?, swapped: true
    def_operator_shortcut :const_defined, :const_defined?

    PASSTHROUGH_EXCEPTIONS = [
      AssertionError,
      SkippedException,
      SignalException,
      SystemExit,
    ].freeze

    def passthrough_exception?(ex) = case ex when *PASSTHROUGH_EXCEPTIONS then true else false end

    def assertion_exception?(ex) = ex.is_a?(AssertionError)

    def standard_exception?(ex) = ex.is_a?(StandardError)

    # minitest's

    def assert_raises(*expected)
      msg = expected.pop if expected.last.is_a?(String)
      expected = [StandardError] if expected.empty?
      begin
        yield
      rescue *expected
        bump_assertions_count
        $!
      rescue Exception
        raise if passthrough_exception?($!)
        bump_assertions_count
        assertion_unexpected_exception($!, msg)
      else
        bump_assertions_count
        assertion_failed(msg || "no exceptions raised")
      end
    end

    alias assert_raise_kind_of assert_raises

    # test/unit's

    def assert_raise_exception_matches?(exception, *expected)
      return true if expected.empty?
      expected_modules, expected_instances = expected.partition { |v| v.is_a?(Module) }
      expected_classes, expected_modules = expected_modules.partition { |v| v.is_a?(Class) }
      expected_modules.any? { |m| exception.is_a?(m) } ||
        expected_classes.any? { |c| exception.instance_of?(c) } ||
        expected_instances.any? { |e| e.class == exception.class && e.message == exception.message }
    end

    def assert_raise_with_message(expected, expected_message, msg = nil)
      yield
    rescue Exception
      if assert_raise_exception_matches?($!, *expected) &&
         (expected_message.nil? || expected_message === $!.message)
        bump_assertions_count
        $!
      else
        raise if passthrough_exception?($!)
        bump_assertions_count
        assertion_unexpected_exception($!, msg)
      end
    else
      bump_assertions_count
      assertion_failed(msg || "no exceptions raised")
    end

    def assert_raise(*expected, &)
      msg = expected.pop if expected.last.is_a?(String)
      assert_raise_with_message(expected, nil, msg, &)
    end

    def assert_nothing_raised(*expected)
      msg = expected.pop if expected.last.is_a?(String)
      begin
        r = yield
      rescue Exception
        raise unless assert_raise_exception_matches?($!, *expected)
        bump_assertions_count
        assertion_unexpected_exception($!, msg)
      else
        bump_assertions_count
      end
      r
    end

    def assert_raise_message(expected_message, msg = nil, &)
      assert_raise_with_message([], expected_message, msg, &)
    end

    def assert_fail_assertion(msg = nil, &)
      assert_raises(AssertionError, msg || "expected failed assertion", &)
    end

    def assert_throws(tag, msg = nil)
      caught = true
      r = catch(tag) do
        yield tag
        caught = false
      rescue Exception
        raise if assertion_exception?($!) || !standard_exception?($!)
        bump_assertions_count
        assertion_unexpected_exception($!)
      end
      bump_assertions_count
      return r if caught
      assertion_failed(msg || "expected block to throw #{assertion_inspect(tag)}")
    end

    alias assert_throw assert_throws

    def assert_nothing_thrown(msg = nil)
      begin
        r = yield
      rescue UncaughtThrowError
        bump_assertions_count
        assertion_failed(msg || "block threw #{assertion_inspect($!.tag)} unexpectedly")
      else
        bump_assertions_count
      end
      r
    end

    def capture_io(&) = Ruptr::CaptureOutput.capture_output(&)

    alias capture_output capture_io

    def assert_output(expected_stdout = nil, expected_stderr = nil, &)
      begin
        actual_stdout, actual_stderr = capture_io(&)
      rescue Exception
        raise if assertion_exception?($!) || !standard_exception?($!)
        bump_assertions_count
        assertion_unexpected_exception($!)
      end
      bump_assertions_count
      unless expected_stderr.nil? || expected_stderr === actual_stderr
        assertion_unexpected_value(actual_stderr,
                                   "expected stderr to be #{assertion_inspect(expected_stderr)} " \
                                   "instead of #{assertion_inspect(actual_stderr)}")
      end
      unless expected_stdout.nil? || expected_stdout === actual_stdout
        assertion_unexpected_value(actual_stdout,
                                   "expected stdout to be #{assertion_inspect(expected_stdout)} " \
                                   "instead of #{assertion_inspect(actual_stdout)}")
      end
    end

    def assert_silent(&)
      assert_output('', '', &)
    end

    def skip(msg = nil)
      raise ArgumentError if block_given?
      assertion_raise(SkippedException, msg || "skipped")
    end

    def pend(msg = nil, &)
      skip(msg) unless block_given?
      assert_raises(StandardError, msg, &)
      bump_skipped_blocks_count
    end

    def omit(msg = nil)
      skip(msg) unless block_given?
      bump_skipped_blocks_count
    end
  end
end
