# typed: true

TypedJob.run_async(number: "wrong")
TypedJob.run_async
TypedJob.run_async(number: 1, unknown: true)
TypedJob.run_async(number: 1, tags: [1])
ReplacementJob.run_async(number: 1)
EmptyJob.run_async(unexpected: 1)
T.let(TypedJob.run_async(number: 1), String)
