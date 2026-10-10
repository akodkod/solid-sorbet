# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

desc "Check generated job interfaces with Sorbet"
task :typecheck do
  ruby "bin/typecheck"
end

desc "Build and install the gem into an isolated directory"
task :smoke do
  ruby "bin/smoke"
end

task default: %i[spec rubocop typecheck smoke]
