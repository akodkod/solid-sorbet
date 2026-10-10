# frozen_string_literal: true

require "active_job"
require "sorbet-runtime"
require "sorbet-schema"
require_relative "sorbet/version"
require_relative "sorbet/errors"
require_relative "sorbet/arguments"
require_relative "sorbet/class_methods"
require_relative "sorbet/instance_methods"

module SolidQueue
  module Sorbet
    def self.included(base)
      unless base.is_a?(Class) && base < ActiveJob::Base
        raise ArgumentError, "SolidQueue::Sorbet requires an ActiveJob::Base subclass"
      end

      base.extend(ClassMethods)
      base.include(InstanceMethods)
    end
  end
end
