# frozen_string_literal: true

RSpec.describe SolidQueue::Sorbet do
  def round_trip(job)
    ActiveJob::Base.execute(JSON.parse(JSON.generate(job.serialize)))
  end

  it "requires an Active Job subclass" do
    expect { Class.new.include(described_class) }.to raise_error(ArgumentError, /ActiveJob/)
  end

  it "validates, serializes, and executes through Active Job" do
    job = TypedJob.run_async(number: 42)
    expect(job).to be_a(TypedJob)
    expect(job.queue_name).to eq("low")
    expect(job.arguments).to eq([{ "number" => 42, "enabled" => false, "note" => nil, "tags" => [] }])
    expect(round_trip(job)).to eq([42, false, nil, []])
    expect(TypedJob.run_sync(number: 42)).to eq([42, false, nil, []])
  end

  [{}, { number: "42" }, { number: 42, extra: 1 }, { number: 42, tags: [1] }].each do |kwargs|
    it "rejects #{kwargs.inspect} before enqueue" do
      expect { TypedJob.run_async(**kwargs) }.to raise_error(SolidQueue::Sorbet::InvalidArgsError)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end
  end

  it "rejects invalid arguments for every helper" do
    expect { TypedJob.run_in(30, number: "x") }.to raise_error(SolidQueue::Sorbet::InvalidArgsError)
    expect { TypedJob.run_at(Time.now, number: "x") }.to raise_error(SolidQueue::Sorbet::InvalidArgsError)
    expect { TypedJob.run_sync(number: "x") }.to raise_error(SolidQueue::Sorbet::InvalidArgsError)
  end

  it "supports empty jobs without silently dropping arguments" do
    expect(EmptyJob.run_sync).to eq(:done)
    expect(round_trip(EmptyJob.run_async)).to eq(:done)
    expect { EmptyJob.run_async(extra: 1) }.to raise_error(SolidQueue::Sorbet::InvalidArgsError)
    expect { EmptyJob.perform_now("extra" => 1) }.to raise_error(SolidQueue::Sorbet::SerializationError)
  end

  it "resolves inherited and replaced schemas" do
    expect(ChildJob.run_sync(number: 9)).to eq([9, false, nil, []])
    expect(ReplacementJob.run_sync(name: "child")).to eq("child")
    expect { ReplacementJob.run_sync(number: 9) }.to raise_error(SolidQueue::Sorbet::InvalidArgsError)
  end

  it "does not cache missing schemas" do
    klass = Class.new(EmptyJob)
    expect(klass.args_class).to be_nil
    klass.const_set(:Args, TypedJob::Args)
    expect(klass.args_class).to eq(TypedJob::Args)
  end

  it "reports invalid schema declarations" do
    klass = Class.new(EmptyJob)
    klass.const_set(:Args, 123)
    expect { klass.run_sync }.to raise_error(SolidQueue::Sorbet::ArgsNotDefinedError)
  end

  it "schedules durations, timestamps, and time values" do
    now = Time.now
    expect(TypedJob.run_in(1.minute, number: 1).scheduled_at.to_f).to be_within(2).of(now.to_f + 60)
    expect(TypedJob.run_at(now.to_f + 120, number: 1).scheduled_at.to_f).to be_within(0.01).of(now.to_f + 120)
    expect(TypedJob.run_at(now + 180, number: 1).scheduled_at).to eq(now + 180)
  end

  it "retains coercion during deserialization" do
    expect(TypedJob.perform_now("number" => "42", "enabled" => "true")).to eq([42, true, nil, []])
  end

  [[], { "number" => "invalid" }, { "number" => 1, "extra" => 2 }, {}].each do |payload|
    it "rejects malformed payload #{payload.inspect}" do
      expect { TypedJob.perform_now(payload) }.to raise_error(SolidQueue::Sorbet::SerializationError)
    end
  end

  it "preserves framework methods and private application methods" do
    stub_const("CollisionJob", Class.new(ActiveJob::Base) do
      include SolidQueue::Sorbet

      const_set(:Args, Class.new(T::Struct) do
        const :job_id, String
        const :secret, String
        const :run, String
        const :args, String
      end)
      def run
        [job_id, secret, args.job_id, args.secret, args.run, args.args]
      end

      private

      def secret
        "original"
      end
    end)
    result = CollisionJob.run_sync(job_id: "field", secret: "field", run: "run", args: "args")
    expect(result).to match([kind_of(String), "original", "field", "field", "run", "args"])
    expect(result.first).not_to eq("field")
  end

  context "with complex arguments" do
    let(:kwargs) do
      { nested: ComplexJob::Nested.new(ids: [1, 2]), lookup: { "key" => [3] }, choice: 1,
        symbol: :ready, date: Date.new(2026, 1, 2), time: Time.utc(2026, 1, 2, 3, 4, 5),
        datetime: DateTime.new(2026, 1, 2, 3, 4, 5) }
    end

    it "round trips nested structs, collections, unions, dates, times, and symbols" do
      result = round_trip(ComplexJob.run_async(**kwargs))
      expect(result.nested.ids).to eq([1, 2])
      kwargs.except(:nested).each { |field, value| expect(result.public_send(field)).to eq(value) }
    end

    it "rejects invalid hash and nested struct collection contents" do
      expect { ComplexJob.run_async(**kwargs, lookup: { "key" => ["bad"] }) }
        .to raise_error(SolidQueue::Sorbet::InvalidArgsError)
      kwargs[:nested].ids << "bad"
      expect { ComplexJob.run_async(**kwargs) }.to raise_error(SolidQueue::Sorbet::InvalidArgsError)
    end

    it "wraps serializer failures" do
      allow(Typed::HashSerializer).to receive(:new).and_raise(RuntimeError, "broken serializer")
      expect do
        ComplexJob.run_async(**kwargs)
      end.to raise_error(SolidQueue::Sorbet::SerializationError, /broken serializer/)
    end
  end

  it "runs callbacks and makes args available inside them" do
    stub_const("CallbackJob", Class.new(TypedJob) do
      before_perform { self.tags_seen = args.tags.dup }
      attr_accessor :tags_seen

      def run
        [super, tags_seen]
      end
    end)
    expect(CallbackJob.run_sync(number: 1, tags: ["callback"])).to eq([[1, false, nil, ["callback"]], ["callback"]])
  end

  it "returns false when an enqueue callback aborts" do
    stub_const("AbortedJob", Class.new(TypedJob) { before_enqueue { throw :abort } })
    expect(AbortedJob.run_async(number: 1)).to be(false)
    expect(AbortedJob.run_in(60, number: 1)).to be(false)
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
  end

  it "preserves application exceptions and Active Job handlers" do
    stub_const("FailureJob", Class.new(EmptyJob) do
      def run
        raise IOError, "original"
      end
    end)
    expect { FailureJob.run_sync }.to raise_error(IOError, "original")
    stub_const("DiscardJob", Class.new(FailureJob) { discard_on IOError })
    expect { DiscardJob.run_sync }.not_to raise_error
    stub_const("RetryJob", Class.new(FailureJob) { retry_on IOError, wait: 10, attempts: 2 })
    RetryJob.run_sync
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.last[:job]).to eq(RetryJob)
  end
end
