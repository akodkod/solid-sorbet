# frozen_string_literal: true

RSpec.describe "Default and collection serialization" do
  before do
    stub_const("DefaultsJob", Class.new(ActiveJob::Base) do
      include SolidQueue::Sorbet

      nested_class = const_set(:Nested, Class.new(T::Struct) do
        const :label, T.nilable(String), default: "fallback"
      end)
      const_set(:Args, Class.new(T::Struct) do
        const :label, T.nilable(String), default: "fallback"
        const :enabled, T::Boolean, default: true
        const :values, T::Array[String], factory: -> { [] }
        const :nested, nested_class
        const :list, T::Array[nested_class]
        const :mapping, T::Hash[String, T::Boolean]
      end)
      def run
        args
      end
    end)
  end

  it "preserves explicit nil, false, and nested nil against non-nil defaults" do
    nested = DefaultsJob::Nested.new(label: nil)
    job = DefaultsJob.run_async(label: nil, enabled: false, nested: nested, list: [nested],
                                mapping: { "flag" => false })
    result = ActiveJob::Base.execute(JSON.parse(JSON.generate(job.serialize)))
    expect(result.label).to be_nil
    expect(result.enabled).to be(false)
    expect(result.nested.label).to be_nil
    expect(result.list.first.label).to be_nil
    expect(result.mapping).to eq("flag" => false)
  end

  it "applies factories and defaults to missing fields" do
    result = DefaultsJob.perform_now("nested" => {}, "list" => [{}], "mapping" => {})
    expect(result.label).to eq("fallback")
    expect(result.enabled).to be(true)
    expect(result.values).to eq([])
    expect(result.nested.label).to eq("fallback")
    expect(result.list.first.label).to eq("fallback")
  end
end
