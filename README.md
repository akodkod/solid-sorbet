# Solid Sorbet

Sorbet-validated arguments for Solid Queue jobs, with the `Args + run` interface from [Sidekiq Sorbet](https://github.com/akodkod/sidekiq-sorbet).

Requires Ruby 3.2+ and Rails / Active Job 8.0 or 8.1. Rails 8.1 requires Ruby 3.2+; CI also covers Ruby 4.0. Solid Queue 1.x is supported. Your application configures Solid Queue and its database normally; the gem does not change the queue adapter.

## Installation

Add the gem to your Gemfile (v0.1 is prepared locally; it is not yet published):

```ruby
gem "solid-sorbet", path: "/path/to/solid_queue_sorbet"
```

Bundler loads the gem automatically. For explicit loading, use `require "solid-sorbet"` (or `require "solid_queue/sorbet"`). The Ruby namespace is `SolidQueue::Sorbet`.

## Jobs

```ruby
class AnalyzeAttachmentJob < ApplicationJob
  include SolidQueue::Sorbet

  queue_as :low
  retry_on IOError, wait: 30.seconds, attempts: 3

  class Args < T::Struct
    const :attachment_id, Integer
    const :regenerate, T::Boolean, default: false
  end

  def run
    attachment = Attachment.find(attachment_id)
    attachment.analyze! if regenerate || !attachment.analyzed?
  end
end

job = AnalyzeAttachmentJob.run_async(attachment_id: 1)
AnalyzeAttachmentJob.run_in(1.hour, attachment_id: 1)
AnalyzeAttachmentJob.run_at(1.day.from_now, attachment_id: 1)
AnalyzeAttachmentJob.run_sync(attachment_id: 1, regenerate: true)
```

You can include the module once in `ApplicationJob`. A subclass inherits the nearest ancestor's `Args`, or replaces it by defining its own `Args < T::Struct`. Implement `run`, leaving `perform` to the gem.

| Helper | Behavior | Return |
| --- | --- | --- |
| `run_async(**kwargs)` | Validate and enqueue immediately | Job instance, or `false` if enqueue is aborted |
| `run_in(interval, **kwargs)` | Enqueue with a delay in seconds or an ActiveSupport duration | Job instance or `false` |
| `run_at(time, **kwargs)` | Enqueue at a Time, TimeWithZone, or numeric Unix timestamp | Job instance or `false` |
| `run_sync(**kwargs)` | Validate, serialize, and execute via `perform_now` | Active Job's result, normally the return value of `run` |

Enqueue failures retain Active Job / adapter behavior, including exceptions. A returned job can be deferred until the surrounding database transaction commits.

Jobs without arguments can omit `Args`. Passing keywords to such a job raises `InvalidArgsError`.

## Validation and serialization

Arguments are checked before every `run_*` helper executes or enqueues. Missing required fields, unknown keywords, invalid types, and invalid elements inside arrays, hashes, and nested structs raise `SolidQueue::Sorbet::InvalidArgsError`.

Defaults, factories, and implicit nilable defaults follow `T::Struct` construction. Factories are evaluated when building arguments. Explicit `nil` and `false` survive serialization, including when a field has a different default.

The queued argument is one string-keyed hash. Serialization uses `sorbet-schema`; deserialization retains its coercion behavior, such as converting `"42"` to an integer. Nested structs, arrays/hashes, primitive unions, symbols, dates, DateTime, and Time are supported. Hash keys are serialized as strings. Pass record IDs rather than Active Record / GlobalID objects. Unsupported types raise serialization errors; arbitrary objects and cyclic data are not supported.

```ruby
class NotifyJob < ApplicationJob
  include SolidQueue::Sorbet

  class Recipient < T::Struct
    const :email, String
  end

  class Args < T::Struct
    const :recipient, Recipient
    const :tags, T::Array[String], factory: -> { [] }
    const :note, T.nilable(String)
  end

  def run
    Mailer.notify(recipient.email, tags: tags, note: note).deliver_now
  end
end

NotifyJob.run_async(recipient: NotifyJob::Recipient.new(email: "person@example.com"))
```

Field readers are available during `run`. Existing public, protected, and private methods are never replaced: use `args.job_id`, for example, if a field conflicts with Active Job's `job_id`. Use `args` inside perform callbacks; direct field readers are installed when `perform` starts. Both synchronous and queued execution run Active Job's perform callbacks and exception handlers. Application exceptions keep their original type and backtrace, allowing `retry_on` and `discard_on` to work normally.

Errors defined by this gem:

- `ArgsNotDefinedError`: an `Args` constant exists but is not a `T::Struct` subclass.
- `InvalidArgsError`: arguments supplied to a helper fail validation.
- `SerializationError`: serialization or restoration of a queued payload fails.

All inherit from `SolidQueue::Sorbet::Error`. A missing `run` raises `NotImplementedError`.

## Native Active Job and Solid Queue configuration

Native `perform_later`, `perform_now`, `.set`, and recurring jobs accept the serialized hash. They do **not** perform the helpers' strict enqueue-time validation. Deserialization validates their payload when they execute.

```ruby
# Low-level payload interface; prefer run_async in application code.
AnalyzeAttachmentJob.set(queue: :critical).perform_later({ "attachment_id" => 1 })
```

Solid Queue concurrency keys receive that same hash:

```ruby
limits_concurrency to: 1,
  key: ->(payload) { payload.fetch("attachment_id") },
  duration: 5.minutes
```

A recurring job in `config/recurring.yml` uses a single hash argument:

```yaml
production:
  analyze_attachment:
    class: AnalyzeAttachmentJob
    args:
      - attachment_id: 1
        regenerate: false
    schedule: every day at 5am
```

Typed `.set(...).run_async`, bulk helpers, Sidekiq uniqueness/status emulation, and an application migration are outside v0.1.

## Tapioca

Install Tapioca in the application's development bundle. The gem's compiler is discovered through Tapioca's standard gem DSL compiler loading:

```sh
bundle exec tapioca dsl --only SolidQueueSorbet
```

Or run `bundle exec tapioca dsl` for all compilers. Generated RBIs include typed helper keywords, required versus optional fields, direct readers, the concrete `args` type, and job-or-false enqueue return types. The compiler supports inherited schemas and avoids reader signatures that would conflict with existing methods. It coexists with Tapioca's Active Job compiler. Neither Tapioca nor RSpec is loaded by the runtime entrypoint.

## RSpec matchers

```ruby
require "solid_queue/sorbet/rspec"

expect(AnalyzeAttachmentJob).to have_arg(:attachment_id, Integer)
expect(AnalyzeAttachmentJob).to have_arg(:regenerate, T::Boolean).with_default(false)
expect(AnalyzeAttachmentJob).to have_args(attachment_id: Integer, regenerate: T::Boolean)
expect(AnalyzeAttachmentJob).to accept_args(attachment_id: 1)
expect(AnalyzeAttachmentJob).to reject_args(attachment_id: "bad")
  .with_error(SolidQueue::Sorbet::InvalidArgsError, /Invalid/)
```

Validation matchers construct and validate the struct, without enqueueing or executing the job. Use Active Job's testing helpers to assert queue behavior.

## Migrating from Sidekiq Sorbet

1. Make each job inherit from `ApplicationJob` and replace `include Sidekiq::Sorbet` with `include SolidQueue::Sorbet`.
2. Keep its `Args`, `run`, field access, and `run_*` call sites.
3. Translate `sidekiq_options` deliberately into `queue_as`, `retry_on`, and Solid Queue concurrency controls; the semantics are different.
4. Update call sites expecting a Sidekiq job ID to use the returned job's `job_id`. Enqueue cancellation returns `false`.
5. Update error constants, RSpec requires, and regenerate Tapioca RBIs.

`run_sync` now runs the Active Job lifecycle, uses the same serialization path as queued execution, and preserves application exceptions instead of wrapping them. Existing Sidekiq payloads are not migrated.

## Development

```sh
bundle install
bundle exec rake
```

The default task runs RSpec, RuboCop, generated-interface Sorbet checks, and an isolated gem install/load smoke test. The integration spec initializes a minimal Rails application and uses Solid Queue's installed schema in an in-memory SQLite database; no Redis or worker daemon is needed.

`bundle exec rake typecheck` generates fixtures under `tmp/typecheck`, checks valid calls, and verifies that seven deliberately invalid calls fail. Its small framework RBI isolates the generated interface contract; it is not a replacement for application-wide type checking. After generation, `bundle exec srb tc` checks the valid fixtures using `sorbet/config`.

CI covers Ruby 3.2 / Rails 8.0, Ruby 3.3 / Rails 8.1, and Ruby 4.0 / Rails 8.1. Set `RAILS_VERSION='~> 8.0.0'` before `bundle update` to test Rails 8.0 locally.

```sh
bundle exec rake build
```

Builds the release package locally. Publishing is a separate step.

## License

MIT. Adapted from Andrew Kodkod's Sidekiq Sorbet; see [LICENSE.txt](LICENSE.txt).
