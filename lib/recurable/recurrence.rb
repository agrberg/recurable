# frozen_string_literal: true

require 'date'
require_relative 'version'
require_relative 'recurrence/parser'
require_relative 'recurrence/formatter'

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
  HOUR_OF_DAY_RANGE = 0..23
  MINUTE_OF_HOUR_RANGE = SECOND_OF_MINUTE_RANGE = 0..59
  MONTH_OF_YEAR_RANGE = 1..12
  DAY_OF_YEAR_RANGE = ((-366..-1).to_a + (1..366).to_a).freeze
  WEEK_OF_YEAR_RANGE = ((-53..-1).to_a + (1..53).to_a).freeze
  BYDAY_PATTERN = /\A[+-]?\d*(?:#{Regexp.union(DAYS_OF_WEEK).source})\z/
  # Parses an RRULE UNTIL string (e.g. "20261231T235959Z") into a Time object.
  UNTIL_PATTERN = /\A(?<Y>\d{4})(?<m>\d{2})(?<d>\d{2})T(?<H>\d{2})(?<M>\d{2})(?<S>\d{2})Z\z/

  ATTRIBUTES = %i[
    by_day by_month_day by_set_pos count day_of_year frequency hour_of_day interval
    minute_of_hour month_of_year repeat_until
    second_of_minute week_of_year week_start
  ].freeze

  ARRAY_ATTRIBUTES = %i[
    by_day by_month_day by_set_pos day_of_year hour_of_day minute_of_hour
    month_of_year second_of_minute week_of_year
  ].each do |attr|
    define_method(:"#{attr}=") do |value|
      coerced = Array(value)
      instance_variable_set(:"@#{attr}", coerced.empty? ? nil : coerced)
    end
  end.freeze

  attr_accessor(*(ATTRIBUTES - ARRAY_ATTRIBUTES - %i[repeat_until]))
  attr_reader :repeat_until, *ARRAY_ATTRIBUTES

  def self.from_rrule(rrule) = new(**Parser.call(rrule))

  def initialize(**attrs)
    unknown = attrs.keys - ATTRIBUTES
    raise ArgumentError, "Unknown attribute(s): #{unknown.join(', ')}" if unknown.any?

    attrs.each { |attr, value| public_send(:"#{attr}=", value) }
  end

  def repeat_until=(value)
    @repeat_until = case value
                    when nil, '' then nil
                    when Time then value.utc
                    when String then parse_until(value)
                    end
  end

  def monthly_option
    return unless frequency == 'MONTHLY'
    return 'NTH_DAY' if by_set_pos&.any? && by_day&.any?

    'DATE' if by_month_day&.any?
  end

  def by_month_day_option? = monthly_option == 'DATE'
  def by_set_pos_option? = monthly_option == 'NTH_DAY'
  def to_rrule = Formatter.call(self)

  def <=>(other)
    return super unless other.is_a?(self.class)

    FREQ_ORDER[frequency] <=> FREQ_ORDER[other.frequency]
  end

  private

  def parse_until(value)
    return if value.to_s.strip.empty?
    return unless (match = value.match(UNTIL_PATTERN))

    Time.utc(match[:Y], match[:m], match[:d], match[:H], match[:M], match[:S])
  end
end
