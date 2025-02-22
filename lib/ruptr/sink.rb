# frozen_string_literal: true

module Ruptr
  module Sink
    def begin_plan(_fields) = nil
    def finish_plan(_fields) = nil

    def submit_plan(fields = {})
      begin_plan(fields)
      yield
    ensure
      finish_plan(fields)
    end

    private def begin_element(_te) = nil
    private def finish_element(_te, _tr) = nil

    def begin_case(tc) = begin_element(tc)
    def finish_case(tc, tr) = finish_element(tc, tr)

    def submit_case(tc, tr = yield)
      begin_case(tc)
      finish_case(tc, tr)
    end

    def begin_group(tg) = begin_element(tg)
    def finish_group(tg, tr) = finish_element(tg, tr)

    def submit_group(tg, tr = (tr_missing = true; nil))
      begin_group(tg)
      finish_group(tg, tr_missing ? yield : tr)
    end

    class Tee
      include Sink

      def self.for(targets)
        return targets.first if targets.size == 1
        new(targets)
      end

      def initialize(targets) = @targets = targets

      %i[begin_plan finish_plan begin_case finish_case begin_group finish_group].each do |method_name|
        class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def #{method_name}(...) = @targets.each { |target| target.#{method_name}(...) }
        RUBY
      end
    end

    class Passed
      include Sink
      def begin_plan(_) = @passed = true
      def finish_element(_, tr) = @passed &&= !tr.failed?
      def passed? = @passed
    end
  end
end
