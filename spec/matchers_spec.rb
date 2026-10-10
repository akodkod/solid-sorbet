# frozen_string_literal: true

RSpec.describe "RSpec matchers" do
  it "checks fields, defaults, and types" do
    expect(TypedJob).to have_arg(:enabled, T::Boolean).with_default(false)
    expect(TypedJob).to have_args(number: Integer, tags: T::Array[String])
    expect(TypedJob).to have_args(:number, Integer).and_arg(:enabled, T::Boolean)
    expect(TypedJob).not_to have_arg(:missing)
    expect(TypedJob).not_to have_arg(:number, String)
  end

  it "validates without running or enqueueing" do
    expect(TypedJob).not_to receive(:perform_later)
    expect(TypedJob).not_to receive(:perform_now)
    expect(TypedJob).to accept_args(number: 1)
    expect(TypedJob).to reject_args(number: "wrong").with_error(SolidQueue::Sorbet::InvalidArgsError, /Invalid/)
    expect(TypedJob).to reject_args(number: 1, tags: [3])
    expect(EmptyJob).to reject_args(extra: true)
  end
end
