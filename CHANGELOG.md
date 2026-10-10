# Changelog

## 1.0.0 (unreleased)

- Add `SolidQueue::Sorbet` for Active Job subclasses with `Args < T::Struct` and `run`.
- Validate helper arguments recursively; serialize and restore typed payloads with sorbet-schema.
- Add immediate, delayed, scheduled, and synchronous execution through Active Job.
- Preserve application exceptions, inherited schemas, defaults/factories, and existing methods.
- Include a Tapioca DSL compiler, optional RSpec matchers, Rails/SQLite integration tests, and CI.
