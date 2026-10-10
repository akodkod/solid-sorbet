# typed: false
# frozen_string_literal: true

require "tapioca/dsl"
require "solid_queue/sorbet"

module Tapioca
  module Dsl
    module Compilers
      class SolidQueueSorbet < Compiler
        def self.gather_constants
          all_classes.select { |klass| klass < ::ActiveJob::Base && klass < ::SolidQueue::Sorbet }
        end

        def decorate
          root.create_path(constant) do |scope|
            schema = constant.args_class
            scope.create_method("args", return_type: schema ? "::#{schema.name}" : "NilClass")
            schema&.props&.each do |field, info|
              next if constant.method_defined?(field) || constant.private_method_defined?(field) ||
                      constant.protected_method_defined?(field)

              scope.create_method(field.to_s, return_type: info.fetch(:type_object).to_s)
            end
            { "run_async" => nil, "run_sync" => nil,
              "run_in" => ["interval", "T.any(Numeric, ActiveSupport::Duration)"],
              "run_at" => ["time", "T.any(Time, ActiveSupport::TimeWithZone, Numeric)"] }.each do |method, timing|
              params = []
              if timing
                name = timing[0]
                name = "_#{name}" while schema&.props&.key?(name.to_sym)
                params << RBI::TypedParam.new(param: RBI::ReqParam.new(name), type: timing[1])
              end
              params.concat(keyword_params(schema))
              scope.create_method(method, parameters: params, class_method: true,
                                          return_type: return_type(method))
            end
          end
        end

        private

        def return_type(method)
          method == "run_sync" ? "T.untyped" : "T.any(::#{constant.name}, FalseClass)"
        end

        def keyword_params(schema)
          return [] unless schema

          schema.props.map do |field, info|
            optional = info.key?(:default) || info.key?(:factory) ||
                       (info.fetch(:type_object).valid?(nil) && !info[:raise_on_nil_write])
            param = if optional
                      RBI::KwOptParam.new(field.to_s, "T.unsafe(nil)")
                    else
                      RBI::KwParam.new(field.to_s)
                    end
            RBI::TypedParam.new(param: param, type: info.fetch(:type_object).to_s)
          end
        end
      end
    end
  end
end
