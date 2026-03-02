# frozen_string_literal: true

require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/time/zones'
require 'rrule'

class RruleAdapter
  class << self
    def times_between(recurrence, project_from:, project_to:, dt_start_at: nil)
      dt_start_at ||= project_from
      RRule::Rule.new(recurrence.rrule, dtstart: dt_start_at, tzid: Time.zone.tzinfo.identifier)
                 .between(project_from, project_to)
                 .uniq
    end

    def last_time_before(recurrence, dt_start_at:, end_at:)
      project_from = (Recurrence::FREQUENCIES[recurrence.frequency] * recurrence.interval).days.ago(end_at)
      times_between(recurrence, project_from:, project_to: end_at, dt_start_at:).last
    end
  end
end
