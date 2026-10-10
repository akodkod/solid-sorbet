# frozen_string_literal: true

module SolidQueue
  module Sorbet
    module InstanceMethods
      def perform(payload = {})
        @sorbet_args = Arguments.deserialize(self.class, payload)
        define_arg_accessors
        run
      end

      # Lazy loading also makes typed arguments available in perform callbacks.
      def args
        return @sorbet_args if defined?(@sorbet_args)

        @sorbet_args = Arguments.deserialize(self.class, arguments.first || {})
      end

      def run
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      private

      def define_arg_accessors
        return unless @sorbet_args

        @sorbet_args.class.props.each_key do |field|
          next if respond_to?(field, true)

          define_singleton_method(field) { args.public_send(field) }
        end
      end
    end
  end
end
