# typed: true
# Minimal framework surface for the isolated generated-interface contract test.
# Runtime compatibility is exercised separately against real Active Job.
class ActiveJob::Base; end
class ActiveSupport::Duration; end
class ActiveSupport::TimeWithZone; end
module SolidQueue::Sorbet; end
