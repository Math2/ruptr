# frozen_string_literal: true

require_relative 'spec_helper'
require 'ruptr/assertions'

module Ruptr
  RSpec.describe Assertions do
    let(:wrapper_class) do
      Class.new do
        include Assertions
        def initialize = @assertions_count = 0
        def bump_assertions_count = @assertions_count += 1
        attr_reader :assertions_count
      end
    end

    subject { wrapper_class.new }

    def check_count(n)
      assert_equal n, subject.assertions_count
    end

    def check_exception(klass, msg = nil, &)
      e = assert_raises(klass, &)
      assert_operator msg, :===, e.message if msg
      e
    end

    def check_unexpected_exception(klass, msg = nil, &)
      e = check_exception(described_class::UnexpectedExceptionError, &)
      assert_kind_of klass, e.cause
      assert_operator msg, :===, e.cause.message if msg
      e.cause
    end

    def check_error(msg = nil, &)
      e = check_exception(described_class::AssertionError, msg, &)
      refute_kind_of described_class::UnexpectedExceptionError, e
      e
    end

    def check_skip(msg = nil, &)
      check_exception(described_class::SkippedException, msg, &)
    end

    def self.describe_assertions_pair_1(name, inverted, &)
      describe "##{name}" do
        define_singleton_method(:inverted_assertion?) { inverted }
        define_method(:inverted_assertion?) { inverted }
        define_method(:assertion_name) { name }
        define_method(:perform_assertion) do |*args, **opts, &blk|
          subject.public_send(assertion_name, *args, **opts, &blk)
        end
        define_method(inverted ? :negative_assertion : :positive_assertion) do |*args, **opts, &blk|
          perform_assertion(*args, **opts, &blk)
        end
        define_method(inverted ? :positive_assertion : :negative_assertion) do |*args, **opts, &blk|
          check_error { perform_assertion(*args, **opts, &blk) }
        end
        define_singleton_method(inverted ? :it_fails_msg : :it_passes_msg) do |_msg, *args, &blk|
          it "passes when given arguments #{args.inspect}#{blk ? ' and a block' : ''}" do
            perform_assertion(*args, &blk)
            check_count(1)
          end
        end
        define_singleton_method(inverted ? :it_passes_msg : :it_fails_msg) do |msg, *args, &blk|
          it "fails when given arguments #{args.inspect}#{blk ? ' and a block' : ''}" do
            check_error(msg) { perform_assertion(*args, &blk) }
            check_count(1)
          end
        end
        define_singleton_method(:it_passes) { |*args, &blk| it_passes_msg(nil, *args, &blk) }
        define_singleton_method(:it_fails) { |*args, &blk| it_fails_msg(nil, *args, &blk) }
        instance_eval(&)
      end
    end

    def self.describe_assertions_pair(name, inverted_name, &)
      describe_assertions_pair_1(name, false, &)
      describe_assertions_pair_1(inverted_name, true, &)
    end

    def self.describe_assertion(name, &)
      describe_assertions_pair_1(name, false, &)
    end

    it "starts with a zero assertions count" do
      check_count(0)
    end

    describe_assertion :pass do
      it_passes
    end

    describe_assertion :flunk do
      it_fails_msg "Flunked"
      describe "custom message" do
        it_fails_msg "Test!!!", "Test!!!"
        it_fails_msg "Test!!!", proc { "Test!!!" }
      end
    end

    describe_assertions_pair :assert, :refute do
      [true, 0, 1, 123, 'test', []].each do |a|
        it_passes_msg "expected #{a.inspect} to be falsey", a
      end
      it_fails_msg "expected nil to be truthy", nil
      it_fails_msg "expected false to be truthy", false
      describe "custom message" do
        it_passes_msg "Test!!!", true, "Test!!!"
        it_fails_msg "Test!!!", false, "Test!!!"
      end
    end

    describe_assertions_pair :assert_block, :refute_block do
      [true, 123, 'test'].each { |v| it_passes { v } }
      [false, nil].each { |v| it_fails { v } }
      describe "custom message" do
        it_passes_msg("!!!", "!!!") { true }
        it_fails_msg("!!!", "!!!") { false }
      end
    end

    describe_assertions_pair :assert_equal, :refute_equal do
      it_passes [1, 2, 3], [1, 2, 3]
      it_fails [1, 2, 3], [3, 2, 1]
      [
        nil, false, true, 123, 'test',
        'hehe'.encode('UTF-8'), 'hehe'.encode('US-ASCII'),
        'héhé'.encode('UTF-8'), 'héhé'.encode('ISO8859-1'),
        'h€h€'.encode('UTF-8'), 'h€h€'.encode('ISO8859-15'),
        'hehe'.b, [0x000180ff].pack('N'),
      ].tap do |l|
        l.each do |v|
          it_passes_msg "expected #{v.inspect} to be something else", v, v
        end
        l.product(l).reject { |e, a| e == a }.each do |e, a|
          it_fails_msg "expected #{a.inspect} to be #{e.inspect}", e, a
        end
      end

      it "uses the expected value's #==" do
        v = Object.new
        def v.==(_) = true
        positive_assertion(v, Object.new)
        negative_assertion(Object.new, v)
        check_count(2)
      end

      it "truncates values in default exception message" do
        a = "a" * 2000
        b = inverted_assertion? ? a : "b" * 2000
        refute_operator check_error { perform_assertion(a, b) }.message.length, :>, 1000
      end

      describe "custom message" do
        it_passes_msg "!!!", 123, 123, "!!!"
        it_fails_msg "!!!", 123, 456, "!!!"
      end
    end

    describe_assertions_pair :assert_match, :refute_match do
      it_passes 'test', "This is a test!"
      it_passes '(', '('
      it_passes /test/i, "Another Test!"
      it_passes /\n/, "\n"
      it_passes_msg "expected /test/ not to match \"test!\"", 'test', 'test!'
      it_passes_msg "expected /\\Ax+\\z/ not to match \"xxx\"", /\Ax+\z/, 'xxx'

      it_fails 'test', "Hello, world!"
      it_fails '(', ')'
      it_fails /test/i, "Hello, world!"
      it_fails /\n/, "\r"
      it_fails_msg "expected /test/ to match \"hello\"", 'test', 'hello'

      unless inverted_assertion?
        it "returns match data" do
          m = positive_assertion(/(\d+)(x+)/, '!123xxxyz')
          assert_kind_of MatchData, m
          assert_equal '123xxx', m[0]
          assert_equal '123', m[1]
          assert_equal 'xxx', m[2]
          check_count(1)
        end
      end

      it "calls matchee's #to_str" do
        o = Object.new
        def o.to_str = 'Test!'
        positive_assertion('Test!', o)
        negative_assertion('!!!', o)
        check_count(2)
      end

      it "calls matcher's #=~" do
        o = Object.new
        def o.=~(v) = v == 'Test!'
        positive_assertion(o, 'Test!')
        negative_assertion(o, '!!!')
        check_count(2)
      end
    end

    describe_assertions_pair :assert_pattern, :refute_pattern do
      it_passes { [123] => [123] }
      it_passes_msg("expected pattern not to match") { [456] => [456] }
      it_fails { [456] => [123] }
      it_fails_msg("[123]: 456 === 123 does not return true") { [123] => [456] }
    end

    describe_assertion :assert_true do
      it_passes true
      it_fails false
      it_fails nil
      it_fails 123
    end

    describe_assertion :assert_false do
      it_passes false
      it_fails true
      it_fails nil
      it_fails 123
    end

    describe_assertion :assert_boolean do
      it_passes true
      it_passes false
      it_fails nil
      it_fails 123
    end

    describe_assertions_pair :assert_predicate, :refute_predicate do
      it_passes 123, :odd?
      it_passes 456, :even?
      it_passes_msg "expected 123 not to be odd?", 123, :odd?
      it_passes_msg "expected 456 not to be even?", 456, :even?
      it_fails 123, :even?
      it_fails 456, :odd?
      it_fails_msg "expected 123 to be even?", 123, :even?
      it_fails_msg "expected 456 to be odd?", 456, :odd?
    end

    describe_assertions_pair :assert_operator, :refute_operator do
      it_passes 0, :<, 1
      it_passes 1, :>, 0
      it_passes_msg "expected 0 not to be < 1", 0, :<, 1
      it_passes_msg "expected 1 not to be > 0", 1, :>, 0
      it_fails 0, :>, 1
      it_fails 1, :<, 0
      it_fails_msg "expected 0 to be > 1", 0, :>, 1
      it_fails_msg "expected 1 to be < 0", 1, :<, 0

      describe "with a nil second operand" do
        it_passes nil, :==, nil
        it_fails false, :==, nil
      end

      describe "without a second operand" do
        it_passes 123, :odd?
        it_fails 123, :even?
      end
    end

    describe_assertion :assert_all do
      it_passes([1, 2, 3]) { true }
      it_passes([]) { false }
      it_passes([1, 2, 3], &:positive?)
      it_passes([1, 3, 5], &:odd?)
      it_passes([2, 4, 6], &:even?)
      it_fails([1, 2, 3]) { false }
      it_fails([1, 2, 3]) { }
      it_fails([1, 2, 3], &:odd?)
      it_fails([1, 2, 3], &:even?)
    end

    describe_assertions_pair :assert_send, :refute_send do
      it_passes ['test', :start_with?, 't']
      it_fails ['test', :start_with?, 'x']
    end

    describe_assertions_pair :assert_in_delta, :refute_in_delta do
      it_passes 123, 123.01, 0.1
      it_passes -123, -123.01, 0.1
      it_fails 123, 123.1, 0.01
      it_fails -123, -123.1, 0.01

      it "raises error on negative delta argument" do
        assert_raises(ArgumentError) { perform_assertion(123, 456, -0.1) }
        check_count(0)
      end
    end

    describe_assertions_pair :assert_in_epsilon, :refute_in_epsilon do
      it_passes 0, 0.1, 0.2
      it_passes 0, -0.1, 0.2
      it_passes 100, 95, 0.1
      it_passes 100, 105, 0.1
      it_passes -100, -95, 0.1
      it_passes -100, -105, 0.1
      it_fails 0, 0.3, 0.2
      it_fails 0, -0.3, 0.2
      it_fails 100, 85, 0.1
      it_fails 100, 115, 0.1
      it_fails -100, -85, 0.1
      it_fails -100, -115, 0.1

      it "raises error on negative delta argument" do
        assert_raises(ArgumentError) { perform_assertion(123, 456, -0.1) }
        check_count(0)
      end
    end

    describe_assertions_pair :assert_path_exists, :refute_path_exists do
      it_passes '/dev'
      it_passes '/dev/null'
      it_fails 'jkewbhrgg9238jevbe'
    end

    describe_assertions_pair :assert_alias_method, :refute_alias_method do
      it_passes [], :size, :length
      it_fails [], :push, :pop
    end

    describe_assertions_pair :assert_nil, :refute_nil do
      it_passes nil
      [false, true, 123, 'test'].each { |v| it_fails v }
    end

    describe_assertions_pair :assert_empty, :refute_empty do
      it_passes ''
      it_passes []
      it_fails ' '
      it_fails ['']
    end

    describe_assertions_pair :assert_same, :refute_same do
      it_passes *[Object.new] * 2
      it_passes *['test'] * 2
      it_fails Object.new, Object.new
      it_fails 'test'.dup, 'test'.dup
    end

    describe_assertions_pair :assert_case_equal, :refute_case_equal do
      it_passes 'test', 'test'
      it_passes /test/, "A test!"
      it_passes Array, []
      it_fails 'test', 'A test!'
      it_fails /test/, 'Test'
      it_fails String, []
    end

    describe_assertions_pair :assert_respond_to, :refute_respond_to do
      it_passes 123, :finite?
      it_fails 'test', :times
    end

    describe_assertions_pair :assert_includes, :refute_includes do
      it_passes 'test', 'es'
      it_passes [123, 456, 789], 456
      it_fails 'test', 'hello'
      it_fails [123, 456, 789], 147
    end

    describe_assertions_pair :assert_instance_of, :refute_instance_of do
      it_passes Array, []
      it_passes Module, Module.new
      it_fails String, []
      it_fails Module, Class.new
    end

    describe_assertions_pair :assert_kind_of, :refute_kind_of do
      it_passes Array, []
      it_passes Module, Module.new
      it_passes Module, Class.new
      it_fails String, []
      it_fails Class, Module.new
    end

    describe_assertions_pair :assert_const_defined, :refute_const_defined do
      m = Module.new { const_set :A, nil }
      it_passes m, :A
      it_fails m, :B
    end

    describe "golden master checking" do
      let(:wrapper_class) do
        Class.new(super()) do
          def assertions_golden_values = @assertions_golden_values ||= {}
          def assertions_golden_trial_values = @assertions_golden_trial_values ||= {}
          def assertion_yield_golden_value(key, &)
            yield assertions_golden_values[key] if assertions_golden_values.include?(key)
          end
          def assertion_set_golden_trial_value(key, v)
            assertions_golden_trial_values[key] = v
          end
        end
      end

      describe_assertion :assert_golden do
        context "without a golden value" do
          it "passes" do
            perform_assertion(123)
            check_count(0)
          end

          it "sets the trial value with default key" do
            perform_assertion(123)
            assert_equal({ nil => 123 }, subject.assertions_golden_trial_values)
          end

          it "sets the trial value with explicit key" do
            perform_assertion(123, key: 'test')
            assert_equal({ 'test' => 123 }, subject.assertions_golden_trial_values)
          end

          it "does not call block" do
            called = false
            perform_assertion(123) { called = true }
            refute called
          end
        end

        context "with a golden value" do
          before { subject.assertions_golden_values[nil] = 123 }
          after { assert_equal({ nil => 123 }, subject.assertions_golden_values) }

          context "with correct actual value" do
            it_passes 123

            it "sets the trial value" do
              perform_assertion(123)
              assert_equal({ nil => 123 }, subject.assertions_golden_trial_values)
            end

            it "calls block to check actual value" do
              called = false
              perform_assertion(123) do |golden, actual|
                called = true
                assert_equal 123, golden
                assert_equal 123, actual
              end
              assert called
            end
          end

          context "with incorrect actual value" do
            [456, nil, false, true].each { |v| it_fails v }

            it "sets the trial value and raises error" do
              check_error { perform_assertion(456) }
              assert_equal({ nil => 456 }, subject.assertions_golden_trial_values)
            end

            it "calls block to check actual value" do
              called = false
              perform_assertion(456) do |golden, actual|
                called = true
                assert_equal 123, golden
                assert_equal 456, actual
              end
              assert called
            end
          end
        end
      end
    end

    shared_examples "common #assert_raise/#assert_raises" do
      it "passes by default when raising a StandardError" do
        perform_assertion { raise StandardError }
        check_count(1)
      end

      it "passes by default when raising a RuntimeError" do
        perform_assertion { fail }
        check_count(1)
      end

      it "fails when no exception raised" do
        check_error("no exceptions raised") { perform_assertion { } }
        check_count(1)
      end

      it "wraps unexpected exceptions" do
        c1 = Class.new(StandardError)
        c2 = Class.new(StandardError)
        check_unexpected_exception(c1) { perform_assertion(c2) { raise c1 } }
        check_count(1)
      end

      it "does not wrap and count nested assertion error" do
        check_error { perform_assertion(RuntimeError) { subject.assert(false) } }
        check_count(1)
      end

      it "does not wrap and count nested unexpected exceptions" do
        c1 = Class.new(StandardError)
        c2 = Class.new(StandardError)
        check_unexpected_exception(c1) { perform_assertion(c2) { perform_assertion(c2) { raise c1 } } }
        check_count(1)
      end

      it "catches specified exception class" do
        c1 = Class.new(StandardError)
        c2 = Class.new(StandardError)
        check_unexpected_exception(c1) { perform_assertion(c2) { raise c1 } }
        check_unexpected_exception(c2) { perform_assertion(c1) { raise c2 } }
        perform_assertion(c1) { raise c1 }
        perform_assertion(c2) { raise c2 }
        perform_assertion(c1, c2) { raise c1 }
        perform_assertion(c2, c2) { raise c2 }
        check_count(6)
      end

      it "catches exception that includes specified module" do
        m = Module.new
        c1 = Class.new(StandardError) { include m }
        c2 = Class.new(StandardError)
        perform_assertion(m) { raise c1 }
        check_unexpected_exception(c2) { perform_assertion(m) { raise c2 } }
        check_count(2)
      end

      it "returns caught exception" do
        c = Class.new(StandardError)
        e = perform_assertion { raise c, "test" }
        assert_kind_of c, e
        assert_equal "test", e.message
        check_count(1)
      end

      it "does not wrap skip exception" do
        check_skip { perform_assertion(StandardError) { subject.skip } }
        check_count(0)
      end

      it "does not wrap SignalException exception" do
        assert_raises(SignalException) { perform_assertion(StandardError) { raise SignalException, :INT } }
        check_count(0)
      end

      it "does not wrap SystemExit exception" do
        assert_raises(SystemExit) { perform_assertion(StandardError) { exit } }
        check_count(0)
      end

      describe "with custom message" do
        it "can pass" do
          perform_assertion("unused message") { fail "test" }
          perform_assertion(RuntimeError, "unused message") { fail "test" }
          check_count(2)
        end

        it "can fail" do
          check_error("test") { perform_assertion("test") { } }
          check_error("test") { perform_assertion(RuntimeError, "test") { } }
          check_count(2)
        end
      end
    end

    describe_assertion :assert_raises do
      include_examples "common #assert_raise/#assert_raises"

      it "catches RuntimeError when expecting a StandardError" do
        perform_assertion(StandardError) { fail }
        check_count(1)
      end

      it "does not catch non-StandardError by default" do
        check_unexpected_exception(Exception) { perform_assertion { raise Exception } }
        check_count(1)
      end

      it "catches specified exception subclass" do
        ec1 = Class.new(Exception)
        ec2 = Class.new(ec1)
        check_unexpected_exception(ec1) { perform_assertion(ec2) { raise ec1 } }
        perform_assertion(ec1) { raise ec1 }
        perform_assertion(ec1) { raise ec2 }
        check_count(3)
      end

      it "does not catch skip exceptions by default" do
        check_skip { perform_assertion { subject.skip } }
        check_count(0)
      end
    end

    describe_assertion :assert_raise do
      include_examples "common #assert_raise/#assert_raises"

      it "catches all exceptions by default" do
        perform_assertion { raise Exception }
        check_count(1)
      end

      it "catches exception instance with matching message" do
        perform_assertion(RuntimeError.new("Test!")) { fail "Test!" }
        check_count(1)
      end

      it "does not catch exception instance with message that does not match" do
        check_unexpected_exception(RuntimeError, "Test!") { perform_assertion(RuntimeError.new("x")) { fail "Test!" } }
        check_count(1)
      end
    end

    describe_assertion :assert_nothing_raised do
      it "passes when there are no exceptions" do
        perform_assertion { }
        check_count(1)
      end

      it "returns value returned by the block" do
        v = Object.new
        assert_same v, perform_assertion { v }
        check_count(1)
      end

      it "wraps exception" do
        check_unexpected_exception(Exception, "Test!") { perform_assertion { raise Exception, "Test!" } }
        check_count(1)
      end

      it "catches only specified exception class" do
        check_exception(Exception, "Test!") { perform_assertion(StandardError) { raise Exception, "Test!" } }
        check_count(0)
      end
    end

    describe_assertion :assert_raise_message do
      it "catches matching exception" do
        perform_assertion("Test!") { raise Exception, "Test!" }
        check_count(1)
      end

      it "does not catch non-matching exception" do
        check_unexpected_exception(Exception, "Test!") { perform_assertion("Hello") { raise Exception, "Test!" } }
        check_count(1)
      end
    end

    describe_assertion :assert_fail_assertion do
      it "passes when assertion fails" do
        perform_assertion { subject.flunk }
      end

      it "fails when no assertions fail" do
        check_error("expected failed assertion") { perform_assertion { } }
      end
    end

    describe_assertion :assert_throws do
      it "catches matching tag" do
        perform_assertion(:test) { throw :test }
        check_count(1)
      end

      it "does not catch non-matching tag" do
        assert_throws(:test) { perform_assertion(:other) { throw :test } }
        check_count(0)
      end

      it "fails when nothing thrown" do
        check_error("expected block to throw :test") { perform_assertion(:test) { } }
        check_count(1)
      end

      it "returns thrown value" do
        v = Object.new
        assert_same v, perform_assertion(:test) { throw :test, v }
        check_count(1)
      end

      it "wraps unexpected exceptions" do
        check_unexpected_exception(StandardError, "Test!") { perform_assertion(:test) { fail "Test!" } }
        check_count(1)
      end

      it "wraps unexpected throws" do
        check_unexpected_exception(UncaughtThrowError) { perform_assertion(:other) { throw :test } }
        check_count(1)
      end

      it "does not wrap assertion exception" do
        check_error { perform_assertion(:test) { subject.flunk } }
        check_count(1)
      end

      it "does not wrap skip exception" do
        check_skip { perform_assertion(:test) { subject.skip } }
        check_count(0)
      end
    end

    describe_assertion :assert_nothing_thrown do
      it "passes when nothing thrown" do
        perform_assertion { }
        check_count(1)
      end

      it "returns value returned by the block" do
        assert_equal 123, perform_assertion { 123 }
        check_count(1)
      end

      it "fails when block throws" do
        check_error("block threw :test unexpectedly") { perform_assertion { throw :test } }
        check_count(1)
      end
    end

    describe "#capture_io" do
      it "captures stdout" do
        assert_equal ["test\n", ''], subject.capture_io { puts "test" }
        check_count(0)
      end

      it "captures stderr" do
        assert_equal ['', "test\n"], subject.capture_io { warn "test" }
        check_count(0)
      end

      it "can capture output from concurrent threads" do
        q1 = Thread::Queue.new
        q2 = Thread::Queue.new
        r1 = r2 = nil
        t1 = Thread.new do
          r1 = subject.capture_io do
            %w[a b c].each do |s|
              puts s
              q1.push(1)
              assert_equal 2, q2.pop
              warn s.upcase
            end
          end
        end
        t2 = Thread.new do
          r2 = subject.capture_io do
            %w[d e f].each do |s|
              puts s
              assert_equal 1, q1.pop
              q2.push(2)
              warn s.upcase
            end
          end
        end
        t1.join
        t2.join
        assert_equal ["a\nb\nc\n", "A\nB\nC\n"], r1
        assert_equal ["d\ne\nf\n", "D\nE\nF\n"], r2
      end

      it "uncaptures stdout on fork" do
        subject.capture_io do
          IO.popen('-', 'r') do |io|
            if io # parent
              assert_equal "test\n", io.read
            else # child
              puts "test"
            end
          end
        end
      end

      it "can capture output within ractors" do
        r = Ractor.new(subject) do |subject|
          subject.capture_io { puts "test 1"; warn "test 2" }
        end
        assert_equal ["test 1\n", "test 2\n"], r.take
      end
    end

    describe_assertion :assert_output do
      it "can check nothing" do
        perform_assertion { puts "test"; warn "test" }
        check_count(1)
      end

      it "passes when stdout matches" do
        perform_assertion("test\n") { puts "test" }
        check_count(1)
      end

      it "fails when stdout does not match" do
        check_error { perform_assertion("hello\n") { puts "test" } }
        check_count(1)
      end

      it "passes when stderr matches" do
        perform_assertion(nil, "test\n") { warn "test" }
        check_count(1)
      end

      it "fails when stderr does not match" do
        check_error { perform_assertion(nil, "hello\n") { warn "test" } }
        check_count(1)
      end

      it "passes when both stdout and stderr match" do
        perform_assertion("123\n", "456\n") { warn "456"; puts "123" }
        check_count(1)
      end

      it "wraps unexpected exceptions" do
        check_unexpected_exception(StandardError, "Test!") { perform_assertion(nil, nil) { fail "Test!" } }
        check_count(1)
      end

      it "does not wrap assertion exception" do
        check_error { perform_assertion(nil, nil) { subject.flunk } }
        check_count(1)
      end

      it "does not wrap skip exception" do
        check_skip { perform_assertion(nil, nil) { subject.skip } }
        check_count(0)
      end
    end

    describe_assertion :assert_silent do
      it "passes when silent" do
        perform_assertion { }
        check_count(1)
      end

      it "fails on stdout" do
        check_error { perform_assertion { puts "test" } }
        check_count(1)
      end

      it "fails on err" do
        check_error { perform_assertion { warn "test" } }
        check_count(1)
      end
    end

    describe "#skip" do
      it "can skip" do
        check_skip("skipped") { subject.skip; fail }
      end

      it "does not use StandardError" do
        check_skip { subject.skip rescue nil; fail }
      end

      it "can skip with message" do
        check_skip("!!!") { subject.skip("!!!"); fail }
      end
    end
  end
end
