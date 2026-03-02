# frozen_string_literal: true

require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/time/zones'
require 'rrule'

module RruleUtils
  SUB_DAILY_NOUNS = { 'HOURLY' => 'hour', 'MINUTELY' => 'minute' }.freeze

  def recurrence_times(project_from:, project_to:, dt_start_at: nil)
    dt_start_at ||= project_from
    RRule::Rule.new(recurrence.rrule, dtstart: dt_start_at, tzid: Time.zone.tzinfo.identifier)
               .between(project_from, project_to)
               .uniq
  end

  def last_recurrence_time_before(dt_start_at:, end_at:)
    project_from = (Recurrence::FREQUENCIES[recurrence.frequency] * recurrence.interval).days.ago(end_at)
    recurrence_times(project_from:, project_to: end_at, dt_start_at:).last
  end

  def next_recurrence_time_after(dt_start_at:, after:)
    project_to = (Recurrence::FREQUENCIES[recurrence.frequency] * recurrence.interval).days.since(after)
    recurrence_times(project_from: after, project_to:, dt_start_at:).first
  end

  def humanize_recurrence
    noun = SUB_DAILY_NOUNS[recurrence.frequency]
    return RRule::Rule.new(recurrence.rrule).humanize unless noun

    "every #{recurrence.interval == 1 ? noun : "#{recurrence.interval} #{noun}s"}"
  end
end
