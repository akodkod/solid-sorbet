# frozen_string_literal: true

require "tapioca/dsl"
require "tapioca/dsl/compilers/active_job"
require "tapioca/dsl/compilers/solid_queue_sorbet"

RSpec.describe Tapioca::Dsl::Compilers::SolidQueueSorbet do
  def compile(job_class, compiler_class = described_class)
    tree = RBI::Tree.new
    compiler_class.new(Tapioca::Dsl::Pipeline.new(requested_constants: [job_class]), tree, job_class, []).decorate
    tree.string
  end

  it "discovers inherited jobs" do
    expect(described_class.gather_constants).to include(TypedJob, ChildJob, EmptyJob)
  end

  it "types keywords, defaults, factories, nilables, scheduling and returns" do
    output = compile(TypedJob)
    expect(output).to include(
      "def self.run_async(number:, enabled: T.unsafe(nil), note: T.unsafe(nil), tags: T.unsafe(nil))"
    )
    expect(output).to include("T.any(::TypedJob, FalseClass)", "returns(::TypedJob::Args)")
    expect(output).to include("ActiveSupport::Duration", "def number; end", "def self.run_sync")
    expect(compile(ChildJob)).to include("returns(::TypedJob::Args)", "T.any(::ChildJob, FalseClass)")
    expect(compile(ReplacementJob)).to include("def self.run_async(name:)")
    expect(compile(EmptyJob)).to include("returns(NilClass)", "def self.run_async; end")
  end

  it "does not generate readers for existing methods" do
    stub_const("CompilerCollisionJob", Class.new(TypedJob) { def number = "custom" })
    expect(compile(CompilerCollisionJob)).not_to include("def number;")
  end

  it "coexists with the Active Job compiler" do
    native = compile(TypedJob, Tapioca::Dsl::Compilers::ActiveJob)
    typed = compile(TypedJob)
    expect(native).not_to include("run_async")
    expect { RBI::Parser.parse_string(native + typed) }.not_to raise_error
    expect(typed).not_to include("def self.perform_later")
  end
end
