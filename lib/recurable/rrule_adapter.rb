# frozen_string_literal: true

require 'active_support/core_ext/module/delegation'
require 'active_support/core_ext/time/zones'
require 'ice_cube'
require 'rrule'

# Projects recurrence times within a date range, handling DST transitions.
#
# Two adapters are used depending on frequency:
#
#   Daily or slower (YEARLY, MONTHLY, WEEKLY, DAILY) — delegates to the RRule gem,
#   which safely ignores ST/DST changes and keeps hours the same within the TZ.
#
#   Hourly or faster (HOURLY, MINUTELY) — delegates to IceCube, then manually
#   adjusts UTC offsets so that "every 1 hour" means every wall-clock hour, even
#   across a DST boundary. Without this, a spring-forward gap would produce a
#   duplicate time and a fall-back overlap would skip one.
class RruleAdapter
  delegate :rrule, to: :@recurrence

  def initialize(recurrence, dt_start_at:, tzid: nil)
    @recurrence = recurrence
    @dt_start_at = dt_start_at
    @tzid = tzid
  end

  def times_between(project_from:, project_to:)
    # RRule has a separate parameter for specifying time zone. Projection of days, months,
    # or greater are easy — the library safely ignores ST/DST changes and keeps hours the
    # same within TZ.
    if dst_no_effect?
      return RRule::Rule.new(rrule, dtstart: @dt_start_at, tzid: @tzid)
                        .between(project_from, project_to)
    end

    # For hourly recurrences we want to ensure the hour matches across the DST boundary.
    # i.e. 1am ST should also project for 1am DST as humans will take that measurement
    # at the same time though they are physically an hour apart.
    #
    # We first adjust the projection dates back by the difference in offset so we project
    # the same quantity of values, then readjust the projected times forward by the offset
    # difference. When projection is within the origin time zone nothing is adjusted.
    #
    # EXAMPLE: Recurrence with dt_start_at 2023-03-01 would adjust
    # from: 2023-03-12 00:00 -05:00 by 0 (same TZ as dt_start_at)
    # but to: 2023-03-12 23:59 -04:00 is adjusted to 2023-03-13 00:59 -04:00 to account
    # for the missing 2023-03-12 02:00 -05:00. Then 2023-03-13 00:00 -04:00 is readjusted
    # to 2023-03-12 23:00 -04:00.
    project_from -= dst_adjustment(project_from)
    project_to -= dst_adjustment(project_to)

    ice_cube_occurrences(project_from, project_to)
      .map { _1 + dst_adjustment(_1) }.uniq
  end

  private

  # IceCube uses the time zone on DT_START_AT
  def ice_cube_occurrences(project_from, project_to)
    schedule = IceCube::Schedule.new(@dt_start_at.in_time_zone(@tzid)) do |s|
      s.add_recurrence_rule IceCube::Rule.from_ical(rrule)
    end
    schedule.occurrences_between(project_from, project_to)
  end

  # `dst_adjustment` is the `utc_offset` difference between `dt_start_at` and the
  # specific recurrence instance time. `utc_offset` is seconds offset from UTC,
  # e.g. EST => `-18_000`s == `-5.hours`.
  #
  # Returns 0 or ±3600 (1 hour) for recurrences in the same TZ the recurrence was
  # created in, or in the opposing zone respectively.
  #
  # `dt_start_at` is part of the RRULE spec and what it bases all recurrences off of.
  # Like the first date of a recurring calendar event, we make this the day the
  # recurrence is active/created (e.g. `start_on`, `effective_on`).
  #
  # EXAMPLE: CT with `dt_start_at` of 2023-03-01 has `utc_offset` of `-18_000`.
  # Before DST at 2am on 2023-03-12: same offset, `dst_adjustment == 0`, no adjustment.
  # After springing ahead: noon 2023-03-12 has offset -14400, `dst_adjustment == -3600`,
  # so times need their hour set back 1.
  def dst_adjustment(datetime) = @dt_start_at.utc_offset - datetime.utc_offset

  def dst_no_effect? = @recurrence <= Recurrence.new(frequency: Recurrence::Frequencies::DAILY)
end
