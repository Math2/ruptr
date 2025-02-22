# frozen_string_literal: true

module Ruptr
  # Exception that copy some of the information of another original exception in a way that
  # (hopefully) can be safely marshalled.
  class SurrogateException < Exception
    def self.detailed_message_supported? = Exception.method_defined?(:detailed_message)

    def self.from_1(original_exception)
      new(original_exception.message,
          **if detailed_message_supported?
              {
                detailed_message: original_exception.detailed_message(highlight: false),
                highlighted_detailed_message: original_exception.detailed_message(highlight: true),
              }
            else
              {}
            end,
          original_class_name: original_exception.class.name,
          backtrace: original_exception.backtrace)
    end

    def self.from(original_exception)
      return from_1(original_exception) unless original_exception.cause
      # Recreate the cause exception chain by raising the surrogate exceptions.  Simply redefining
      # the #cause method does not work in CRuby (apparently the cause is stored in a special
      # instance variable that is then accessed directly).
      rec = lambda do |ex|
        if ex.cause
          if ex.cause.cause
            begin
              rec.call(ex.cause)
            rescue self
              raise from_1(ex)
            end
          else
            raise from_1(ex), cause: from_1(ex.cause)
          end
        else
          raise from_1(ex), cause: nil # don't use implicit $!, if any
        end
      end
      begin
        rec.call(original_exception)
      rescue self
        $!
      end
    end

    private def safe_string(v) = v.nil? ? v : String.new(v)

    def initialize(message = nil,
                   detailed_message: nil, highlighted_detailed_message: nil,
                   original_class_name: nil,
                   backtrace: nil)
      super(safe_string(message))
      @detailed_message = safe_string(detailed_message)
      @highlighted_detailed_message = safe_string(highlighted_detailed_message)
      set_backtrace(backtrace)
      @original_class_name = safe_string(original_class_name)
    end

    attr_reader :original_class_name

    if detailed_message_supported?
      def detailed_message(highlight: false, **_)
        (highlight ? @highlighted_detailed_message || @detailed_message : @detailed_message) || super
      end
    end
  end
end
