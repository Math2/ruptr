# frozen_string_literal: true

require 'rake/tasklib'

require_relative 'main'

module Ruptr
  class RakeTask < Rake::TaskLib
    def initialize(name = :ruptr, &)
      super()
      task(name) do
        main = Main.new
        instance_exec(main, &) if block_given?
        main.run
      end
    end
  end
end
