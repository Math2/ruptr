# frozen_string_literal: true

require 'minitest/test_task'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

Minitest::TestTask.create

RSpec::Core::RakeTask.new

RuboCop::RakeTask.new

task :lint => [:rubocop]

task :check => [:test, :spec, :lint]

task default: :check
