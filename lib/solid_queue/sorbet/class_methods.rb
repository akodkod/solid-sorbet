# frozen_string_literal: true

module SolidQueue
  module Sorbet
    module ClassMethods
      def run_async(**kwargs)
        perform_later(serialize_run_args(kwargs))
      end

      def run_in(interval, **kwargs)
        payload = serialize_run_args(kwargs)
        set(wait: interval).perform_later(payload)
      end

      def run_at(time, **kwargs)
        payload = serialize_run_args(kwargs)
        set(wait_until: time.is_a?(Numeric) ? Time.at(time) : time).perform_later(payload)
      end

      def run_sync(**kwargs)
        perform_now(serialize_run_args(kwargs))
      end

      # Resolve on demand: no stale negative cache if Args is defined later,
      # and no shared class instance state between parent and child jobs.
      def args_class
        owner = ancestors.find { |ancestor| ancestor.is_a?(Class) && ancestor.const_defined?(:Args, false) }
        return unless owner

        schema = owner.const_get(:Args, false)
        unless schema.is_a?(Class) && schema < T::Struct
          raise ArgsNotDefinedError, "#{owner}::Args must inherit from T::Struct"
        end

        schema
      end

      private

      def serialize_run_args(kwargs)
        Arguments.serialize(self, Arguments.build(self, kwargs))
      end
    end
  end
end
