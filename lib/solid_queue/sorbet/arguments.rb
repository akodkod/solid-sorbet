# frozen_string_literal: true

module SolidQueue
  module Sorbet
    # Shared by runtime validation and the optional test matchers.
    module Arguments
      module_function

      def build(job_class, kwargs)
        schema = job_class.args_class
        unless schema
          unless kwargs.empty?
            raise InvalidArgsError,
                  "#{job_class} has no Args; unexpected arguments: #{kwargs.keys.join(', ')}"
          end

          return nil
        end

        unknown = kwargs.keys - schema.props.keys
        raise InvalidArgsError, "Unknown arguments for #{job_class}: #{unknown.join(', ')}" unless unknown.empty?

        instance = schema.new(**kwargs)
        validate_tree(instance)
        instance
      rescue ArgumentError, TypeError => error
        raise InvalidArgsError, "Invalid arguments for #{job_class}: #{error.message}"
      end

      # Sorbet's constructor only checks collections shallowly. Validate every
      # element, then walk nested structs (including structs inside collections).
      def validate_tree(value, seen = {}.compare_by_identity)
        return if seen[value]

        seen[value] = true
        case value
        when T::Struct
          value.class.props.each do |field, info|
            member = value.public_send(field)
            unless info.fetch(:type_object).recursively_valid?(member)
              raise InvalidArgsError, "Invalid #{value.class}##{field}: expected #{info.fetch(:type_object)}"
            end

            validate_tree(member, seen)
          end
        when Array
          value.each { |member| validate_tree(member, seen) }
        when Hash
          value.each do |key, member|
            validate_tree(key, seen)
            validate_tree(member, seen)
          end
        end
      end

      def serialize(job_class, instance)
        return {} unless instance

        serializer = Typed::HashSerializer.new(schema: instance.class.schema, should_serialize_values: true)
        result = serializer.serialize(instance)
        raise SerializationError, result.error.message unless result.success?

        # sorbet-schema compacts nil fields. Retain every property so an explicit
        # nil cannot turn back into a non-nil default when the job executes.
        instance.class.props.to_h do |field, _info|
          original = instance.public_send(field)
          [field.to_s, serialize_nested(original, result.payload[field])]
        end
      rescue StandardError => error
        raise SerializationError, "Failed to serialize args for #{job_class}: #{error.message}"
      end

      def deserialize(job_class, payload)
        raise SerializationError, "Expected a hash payload for #{job_class}" unless payload.is_a?(Hash)

        schema = job_class.args_class
        unless schema
          raise SerializationError, "#{job_class} has no Args; expected an empty payload" unless payload.empty?

          return nil
        end

        unknown = payload.keys.map(&:to_s) - schema.props.keys.map(&:to_s)
        raise SerializationError, "Unknown arguments for #{job_class}: #{unknown.join(', ')}" unless unknown.empty?

        instance = deserialize_struct(schema, payload)
        validate_tree(instance)
        instance
      rescue ArgsNotDefinedError
        raise
      rescue StandardError => error
        raise SerializationError, "Failed to deserialize args for #{job_class}: #{error.message}"
      end

      def deserialize_struct(schema, payload)
        payload = payload.transform_keys(&:to_sym)
        unknown = payload.keys - schema.props.keys
        raise SerializationError, "Unknown arguments for #{schema}: #{unknown.join(', ')}" unless unknown.empty?

        fields = schema.props.map do |field, info|
          unless payload.key?(field)
            if info.key?(:factory)
              payload[field] = info.fetch(:factory).call
            elsif info.key?(:default)
              payload[field] = info.fetch(:default).deep_dup
            end
          end
          payload[field] = deserialize_nested(info.fetch(:type_object), payload[field]) if payload.key?(field)
          # Apply defaults only to missing keys, never to explicitly supplied nil.
          Typed::Field.new(name: field, type: info.fetch(:type_object))
        end
        serializer = Typed::HashSerializer.new(schema: Typed::Schema.new(target: schema, fields: fields))
        result = serializer.deserialize(payload)
        raise SerializationError, result.error.message unless result.success?

        result.payload
      end

      def deserialize_nested(type, value)
        case type
        when T::Types::Simple
          if value.is_a?(Hash) && type.raw_type.is_a?(Class) && type.raw_type < T::Struct
            deserialize_struct(type.raw_type, value)
          else
            value
          end
        when T::Types::TypedArray
          value.is_a?(Array) ? value.map { |member| deserialize_nested(type.type, member) } : value
        when T::Types::TypedHash
          return value unless value.is_a?(Hash)

          value.to_h { |key, member| [key, deserialize_nested(type.values, member)] }
        when T::Types::Union
          return value if value.nil? || type.recursively_valid?(value)

          # Only specialize an unambiguous struct union. Other coercion remains
          # sorbet-schema's responsibility, including primitive unions.
          structs = type.types.select { |member| member.is_a?(T::Types::Simple) && member.raw_type < T::Struct }
          structs.size == 1 ? deserialize_nested(structs.first, value) : value
        else
          value
        end
      end

      def serialize_nested(original, serialized)
        case original
        when T::Struct
          serialize(original.class, original)
        when Array
          original.each_with_index.map { |member, index| serialize_nested(member, serialized[index]) }
        when Hash
          original.to_h do |key, member|
            [key.to_s, serialize_nested(member, serialized.fetch(key) { serialized[key.to_s] })]
          end
        else
          serialized
        end
      end
    end
  end
end
