# typed: strict

TypedJob.run_async(number: 1)
TypedJob.run_in(60, number: 1, enabled: false, tags: ["tag"])
TypedJob.run_at(Time.now, number: 1, note: nil)
TypedJob.run_sync(number: 1)
ChildJob.run_async(number: 1)
ReplacementJob.run_async(name: "replacement")
EmptyJob.run_async
T.let(TypedJob.run_async(number: 1), T.any(TypedJob, FalseClass))
T.let(TypedJob.new.args, TypedJob::Args)
T.let(TypedJob.new.number, Integer)
T.let(EmptyJob.new.args, NilClass)
