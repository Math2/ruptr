# frozen_string_literal: true

RSpec.configure do |rspec|
  rspec.expect_with(:minitest)
  rspec.disable_monkey_patching!
end

Warning[:experimental] = false
