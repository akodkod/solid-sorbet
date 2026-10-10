# frozen_string_literal: true

class TypedJob < ActiveJob::Base
  include SolidQueue::Sorbet

  queue_as :low

  class Args < T::Struct
    const :number, Integer
    const :enabled, T::Boolean, default: false
    const :note, T.nilable(String)
    const :tags, T::Array[String], factory: -> { [] }
  end

  def run
    [number, enabled, note, tags]
  end
end

class ChildJob < TypedJob; end

class ReplacementJob < TypedJob
  class Args < T::Struct
    const :name, String
  end

  def run
    name
  end
end

class EmptyJob < ActiveJob::Base
  include SolidQueue::Sorbet

  def run
    :done
  end
end

class ComplexJob < ActiveJob::Base
  include SolidQueue::Sorbet

  class Nested < T::Struct
    const :ids, T::Array[Integer]
  end

  class Args < T::Struct
    const :nested, Nested
    const :lookup, T::Hash[String, T::Array[Integer]]
    const :choice, T.any(String, Integer)
    const :symbol, Symbol
    const :date, Date
    const :time, Time
    const :datetime, DateTime
  end

  def run
    args
  end
end
