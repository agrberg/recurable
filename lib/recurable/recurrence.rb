# frozen_string_literal: true

require 'date'
require_relative 'version'

# Core model representing an iCal RRULE recurrence pattern.
#
# Pure Ruby data class — no Rails dependencies. Handles RRULE string
# generation/parsing with named attributes and frequency comparison.
#
#   recurrence = Recurrence.new(frequency: 'DAILY', interval: 1)
#   recurrence.rrule   # => "FREQ=DAILY;INTERVAL=1"
#   recurrence.daily?  # => true
#
class Recurrence
  # Provides `<`, `<=`, `>`, `>=`, `==`, `between?`, and `clamp` by defining `<=>`.
  include Comparable

  def initialize(**attrs)
    attrs.each { |attr, value| public_send(:"#{attr}=", value) }
  end

  # iCal BYDAY codes derived from Date::DAYNAMES, ordered Sunday–Saturday.
  # Exposes class constants: Recurrence::SUNDAY => 'SU', Recurrence::MONDAY => 'MO', etc.
  # `const_set` returns the value of the constant and map returns an array of the transformed values.
  DAYS_OF_WEEK = Date::DAYNAMES.map { |name| const_set(name.upcase, name[0, 2].upcase) }.freeze
  # Ordered by increasing frequency. Values are approximate period in days.
  # Order used by Comparable#<=> for RruleAdapter strategy selection.
  # Exposes class constants: Recurrence::YEARLY, Recurrence::DAILY, etc. and defines frequency predicates.
  FREQUENCIES = {
    'YEARLY' => 365,
    'MONTHLY' => 31,
    'WEEKLY' => 7,
    'DAILY' => 1,
    'HOURLY' => 1 / 24.0,
    'MINUTELY' => 1 / 24.0 / 60.0
  }.each_key do |freq|
    const_set(freq, freq)
    define_method(:"#{freq.downcase}?") { freq == frequency }
  end.freeze
  FREQ_ORDER = FREQUENCIES.keys.each_with_index.to_h.freeze

  # Exposes class constants: Recurrence::MONTHLY_DATE => 'DATE', Recurrence::MONTHLY_NTH_DAY => 'NTH_DAY'.
  MONTHLY_OPTIONS = %w[DATE NTH_DAY].each { |opt| const_set("MONTHLY_#{opt}", opt) }.freeze
  # Maps symbolic positions to iCal BYSETPOS integers. Positive 1–4 covers typical forward
  # positions; negative -1/-2 covers "last" and "second to last" (deeper negatives are better
  # expressed counting forward). A month has at most 5 of any single weekday.
  NTH_DAY_OF_MONTH = {
    first: 1,
    second: 2,
    third: 3,
    fourth: 4,
    last: -1,
    second_to_last: -2
  }.freeze

  # Positive = calendar date (1st–28th), negative = from end (-1 = last day, -2 = second to last).
  # Capped at ±28 because February has 28 days in a common year.
  DATE_OF_MONTH_RANGE = ((-28..-1).to_a + (1..28).to_a).freeze
  INTERVAL_RANGE = 1..12
  MINUTE_OF_HOUR_RANGE = 0..59
  HOUR_OF_DAY_RANGE = 0..23
  SECOND_OF_MINUTE_RANGE = 0..59
  MONTH_OF_YEAR_RANGE = 1..12
  DAY_OF_YEAR_RANGE = ((-366..-1).to_a + (1..366).to_a).freeze
  WEEK_OF_YEAR_RANGE = ((-53..-1).to_a + (1..53).to_a).freeze
  # Parses an RRULE UNTIL string (e.g. "20261231T235959Z") into a Time object.
  UNTIL_PATTERN = /\A(?<Y>\d{4})(?<m>\d{2})(?<d>\d{2})T(?<H>\d{2})(?<M>\d{2})(?<S>\d{2})Z\z/

  # Naming conventions for the monthly-related attributes:
  #
  #   date_of_month   — Numeric day of the month (1–28). Used with MONTHLY_DATE.
  #                     Maps to RRULE's BYMONTHDAY component. Named "date" because it's a
  #                     calendar date number, e.g. "the 15th of every month".
  #
  #   day_of_month    — Two-letter day-of-week string (SU/MO/TU/WE/TH/FR/SA).
  #                     Used with MONTHLY_NTH_DAY for rules like "the 2nd Tuesday
  #                     of every month". Maps to RRULE's BYDAY component. Named "day"
  #                     because it identifies which weekday.
  #
  #   nth_day_of_month — Ordinal position within the month (1=first, 2=second, ... -1=last,
  #                     -2=second-to-last). Paired with day_of_month to express rules like
  #                     "the last Friday". Maps to RRULE's BYSETPOS component.
  #
  #   day_of_week     — Two-letter day-of-week string(s) for WEEKLY recurrences only.
  #                     Also maps to BYDAY but in the weekly context (no BYSETPOS).
  ATTRIBUTES = %i[
    count date_of_month day_of_month day_of_week day_of_year
    frequency hour_of_day interval minute_of_hour month_of_year
    nth_day_of_month repeat_until second_of_minute week_of_year week_start
  ].freeze

  ARRAY_ATTRIBUTES = %i[
    day_of_month day_of_week day_of_year hour_of_day
    month_of_year second_of_minute week_of_year
  ].freeze

  attr_accessor(*(ATTRIBUTES - ARRAY_ATTRIBUTES - %i[nth_day_of_month repeat_until]))
  attr_reader :nth_day_of_month, :repeat_until, *ARRAY_ATTRIBUTES

  class << self
    def from_rrule(rrule:)
      new(**attributes_from(parse_components(rrule)))
    end

    private

    # Parses "FREQ=DAILY;INTERVAL=1;BYDAY=MO…" into {"FREQ"=>"DAILY", "BYDAY"=>"MO", …}
    def parse_components(rrule)
      rrule.split(';').each_with_object({}) do |pair, hash|
        next if pair.strip.empty?

        key, value = pair.split('=', 2)
        hash[key] = value
      end
    end

    def attributes_from(components)
      freq = components['FREQ']
      byday = split_list(components['BYDAY'])

      {
        count: components['COUNT']&.to_i,
        date_of_month: components['BYMONTHDAY']&.to_i,
        day_of_month: (byday if freq == 'MONTHLY'),
        day_of_week: (byday if freq == 'WEEKLY'),
        day_of_year: split_int_list(components['BYYEARDAY']),
        frequency: freq,
        hour_of_day: split_int_list(components['BYHOUR']),
        interval: components['INTERVAL']&.to_i || 1,
        minute_of_hour: components['BYMINUTE']&.to_i,
        month_of_year: split_int_list(components['BYMONTH']),
        nth_day_of_month: components['BYSETPOS']&.to_i,
        repeat_until: components['UNTIL'],
        second_of_minute: split_int_list(components['BYSECOND']),
        week_of_year: split_int_list(components['BYWEEKNO']),
        week_start: components['WKST']
      }
    end

    def split_list(csv)
      return unless csv

      list = csv.split(',')
      list unless list.empty?
    end

    def split_int_list(csv)
      split_list(csv)&.map(&:to_i)
    end
  end

  ARRAY_ATTRIBUTES.each do |attr|
    define_method(:"#{attr}=") do |value|
      coerced = Array(value)
      instance_variable_set(:"@#{attr}", coerced.empty? ? nil : coerced)
    end
  end

  def repeat_until=(value)
    @repeat_until = case value
                    when nil, '' then nil
                    when Time then value.utc
                    when String then parse_until(value)
                    end
  end

  def rrule
    byday = join_list(day_of_week) || join_list(day_of_month)

    {
      'FREQ' => frequency,
      'INTERVAL' => interval,
      'COUNT' => non_blank(count),
      'UNTIL' => format_until(repeat_until),
      'BYDAY' => byday,
      'BYMONTHDAY' => non_blank(date_of_month),
      'BYMONTH' => join_list(month_of_year),
      'BYHOUR' => join_list(hour_of_day),
      'BYMINUTE' => non_blank(minute_of_hour),
      'BYSECOND' => join_list(second_of_minute),
      'BYYEARDAY' => join_list(day_of_year),
      'BYWEEKNO' => join_list(week_of_year),
      'BYSETPOS' => non_blank(nth_day_of_month),
      'WKST' => non_blank(week_start)
    }.filter_map { |k, v| "#{k}=#{v}" unless v.nil? }.join(';')
  end

  def nth_day_of_month=(value)
    @nth_day_of_month = non_blank(value)&.to_i
  end

  def monthly_option
    return unless frequency == 'MONTHLY'
    return 'NTH_DAY' if nth_day_of_month && day_of_month&.any?

    'DATE' if date_of_month
  end

  def date_of_month_option? = monthly_option == 'DATE'
  def nth_day_option? = monthly_option == 'NTH_DAY'

  def <=>(other)
    return super unless other.is_a?(self.class)

    FREQ_ORDER[frequency] <=> FREQ_ORDER[other.frequency]
  end

  private

  def non_blank(value)
    value unless value.nil? || value.to_s.strip.empty?
  end

  def join_list(array)
    non_blank(array&.join(','))
  end

  def format_until(time)
    time&.utc&.strftime('%Y%m%dT%H%M%SZ')
  end

  def parse_until(value)
    return unless (match = non_blank(value)&.match(UNTIL_PATTERN))

    Time.utc(match[:Y], match[:m], match[:d], match[:H], match[:M], match[:S])
  end
end
