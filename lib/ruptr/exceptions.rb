# frozen_string_literal: true

module Ruptr
  module AssertionErrorMixin; end

  module SkippedExceptionMixin; end

  module PendingPassedMixin; end

  module PendingSkippedMixin; end

  module SaveMessageAsReason
    def initialize(msg = nil)
      super
      @reason = msg&.to_s # preserve nil as-is (unlike #message)
    end

    attr_reader :reason

    def reason? = !reason.nil?
  end

  class AssertionError < StandardError
    include AssertionErrorMixin
  end

  class SkippedException < Exception
    include SkippedExceptionMixin
    include SaveMessageAsReason
  end

  class PendingPassedError < StandardError
    include PendingPassedMixin
  end

  class PendingSkippedException < SkippedException
    include PendingSkippedMixin
    include SaveMessageAsReason
  end

  class << self
    attr_accessor :passthrough_exceptions
  end

  PASSTHROUGH_EXCEPTIONS = [NoMemoryError, SignalException, SystemExit].freeze
  self.passthrough_exceptions = PASSTHROUGH_EXCEPTIONS
end
