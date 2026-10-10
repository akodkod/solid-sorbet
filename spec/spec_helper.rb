# frozen_string_literal: true

require "bundler/setup"
require "json"
require "solid_queue/sorbet"
require "solid_queue/sorbet/rspec"
require_relative "support/jobs"

ActiveJob::Base.logger = Logger.new(File::NULL)

RSpec.configure do |config|
  config.before do
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end
end
