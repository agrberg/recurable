# frozen_string_literal: true

require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/time/zones'
require 'rrule'

module RruleUtils
  def recurrence_times(project_from:, project_to:, dt_start_at: nil)
    dt_start_at ||= project_from
    RRule::Rule.new(recurrence.to_rrule, dtstart: dt_start_at, tzid: Time.zone.tzinfo.identifier)
               .between(project_from, project_to)
               .uniq
  end

  def last_recurrence_time_before(before, dt_start_at:)
    project_from = (Recurrence::FREQUENCIES[recurrence.frequency] * recurrence.interval).days.ago(before)
    recurrence_times(project_from:, project_to: before, dt_start_at:).last
  end

  def next_recurrence_time_after(after, dt_start_at:)
    project_to = (Recurrence::FREQUENCIES[recurrence.frequency] * recurrence.interval).days.since(after)
    recurrence_times(project_from: after, project_to:, dt_start_at:).first
  end

  def humanize_recurrence
    RRule::Rule.new(recurrence.to_rrule).humanize
  end
end
