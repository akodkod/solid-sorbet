# frozen_string_literal: true

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "solid_queue"

# An isolated in-memory queue database, with the schema shipped by the installed
# Solid Queue version. No application database or running worker is needed.
class QueueTestApplication < Rails::Application
  config.eager_load = false
  config.secret_key_base = "solid-queue-sorbet-test"
  config.logger = Logger.new(File::NULL)
  config.active_job.queue_adapter = :test
  config.solid_queue.connects_to = nil
  config.solid_queue.use_skip_locked = false
end

RSpec.describe "Solid Queue persistence" do
  before(:all) do
    ENV["DATABASE_URL"] = "sqlite3::memory:"
    QueueTestApplication.initialize! unless Rails.application&.initialized?
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Schema.verbose = false
    load File.join(Gem.loaded_specs.fetch("solid_queue").full_gem_path,
                   "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
  end

  after(:all) { ENV.delete("DATABASE_URL") }

  it "persists a typed payload and executes it through a claimed execution" do
    stub_const("PersistedJob", Class.new(TypedJob) do
      class_attribute :observed
      def run
        self.class.observed = super
      end
    end)
    PersistedJob.queue_adapter = :solid_queue
    job = PersistedJob.run_async(number: 73, tags: ["database"])
    stored = SolidQueue::Job.find_by!(active_job_id: job.job_id)
    expect(stored.arguments.fetch("arguments").first.fetch("number")).to eq(73)
    claimed = SolidQueue::ReadyExecution.claim(["low"], 1, nil).first
    expect(claimed).not_to be_nil
    claimed.perform
    expect(PersistedJob.observed).to eq([73, false, nil, ["database"]])
    expect(SolidQueue::FailedExecution.count).to eq(0)
    expect(SolidQueue::ReadyExecution.where(job_id: stored.id)).to be_empty
  end
end
