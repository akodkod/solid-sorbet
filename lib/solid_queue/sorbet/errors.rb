# frozen_string_literal: true

module SolidQueue
  module Sorbet
    class Error < StandardError; end
    class InvalidArgsError < Error; end
    class ArgsNotDefinedError < Error; end
    class SerializationError < Error; end
  end
end
