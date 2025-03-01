# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'ruptr'
  s.version     = '0.1.4'
  s.license     = 'MIT'
  s.summary     = "RUby Parallel Test Runner, partially compatible with RSpec, Test::Unit and Minitest"
  s.author      = "Mathieu"
  s.email       = 'sigsys@gmail.com'
  s.homepage    = 'https://github.com/Math2/ruptr'

  s.files = Dir.glob(%w[lib/**/*])
  s.executables = %w[ruptr]

  s.required_ruby_version = '>= 3.1'
end
