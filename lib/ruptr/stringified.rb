# frozen_string_literal: true

require 'pp'

module Ruptr
  # Helper to get a string representation of an arbitrary object and write it to an IO stream while
  # attempting to deal with weird/buggy objects as well as possible.
  class Stringified
    def self.stringification_methods = %i[pretty_inspect inspect to_s]

    def self.from(value) = value.is_a?(self) ? value : new(value)

    def initialize(value)
      # String.new is used to get an immutable snapshot of the strings and also to make sure that
      # they are not derived classes or have instance variables that could make them unserializable.
      @original_class_name = String.new(value.class.to_s)
      if (@originally_a_string = value.class <= String)
        @stringified = String.new(value)
      else
        if (name = self.class.stringification_methods.find { |name| value.respond_to?(name) })
          # NOTE: String.new may call #to_s on the method's return value if needed.
          @stringified = String.new(value.public_send(name))
          @stringification_method = name
        end
      end
    end

    attr_reader :original_class_name,
                :stringified,
                :stringification_method

    def originally_a_string? = @originally_a_string
    def stringified? = !@stringified.nil?

    def compatible_with_io?(io)
      return nil unless stringified?
      @stringified.valid_encoding? &&
        Encoding.compatible?(@stringified, io.external_encoding) == io.external_encoding
    end

    private def unstringifiable_fallback = "#<#{self.class}: unstringifiable object of class #{@original_class_name}>"

    def string_for_io(io)
      case
      when !stringified? then unstringifiable_fallback
      when compatible_with_io?(io) then @stringified
      else @stringified.b.inspect
      end
    end

    def write_to_io(io) = io.write(string_for_io(io))

    def string = stringified? ? @stringified : unstringifiable_fallback
    alias to_s string
    alias to_str string
  end
end
