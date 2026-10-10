# frozen_string_literal: true

require "solid_queue/sorbet"
require "rspec/expectations"
require "rspec/core"
require_relative "rspec/matchers"

RSpec.configure do |config|
  config.include SolidQueue::Sorbet::RSpec::Matchers
end
