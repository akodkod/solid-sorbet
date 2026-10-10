# frozen_string_literal: true

require_relative "lib/solid_queue/sorbet/version"

Gem::Specification.new do |spec|
  spec.name = "solid-sorbet"
  spec.version = SolidQueue::Sorbet::VERSION
  spec.authors = ["Andrew Kodkod"]
  spec.email = ["andrew@kodkod.me"]
  spec.summary = "Sorbet-validated arguments for Solid Queue and Active Job"
  spec.description = "Typed job arguments, serialization, scheduling helpers, and a Tapioca compiler for Solid Queue."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbi", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]
  spec.add_dependency "activejob", ">= 8.0", "< 8.2"
  spec.add_dependency "solid_queue", ">= 1.0", "< 2"
  spec.add_dependency "sorbet-runtime", ">= 0.6", "< 0.7"
  spec.add_dependency "sorbet-schema", ">= 0.10", "< 0.11"
end
