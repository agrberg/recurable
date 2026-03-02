# frozen_string_literal: true

require 'active_model'
require 'active_support/core_ext/object/inclusion'
require 'active_support/core_ext/string/inflections'

require 'date'
require_relative 'version'

# Core model representing an iCal RRULE recurrence pattern.
#
# Wraps RRULE string generation/parsing with named attributes, ActiveModel
# validations, time projection (via RruleAdapter), and human-readable
# statements (via I18n).
#
# Can be used standalone (no Rails required):
#
#   recurrence = Recurrence.new(frequency: 'DAILY', interval: 1)
#   recurrence.rrule   # => "FREQ=DAILY;INTERVAL=1"
#   recurrence.valid?  # => true
#
class Recurrence
  include ActiveModel::Model

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

  DELEGATED_ATTRIBUTES = %i[
    date_of_month day_of_month day_of_week frequency
    interval minute_of_hour monthly_option nth_day_of_month
  ].freeze

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
  #   day_of_week     — Two-letter day-of-week string for WEEKLY recurrences only.
  #                     Also maps to BYDAY but in the weekly context (no BYSETPOS).
  attr_accessor(
    :date_of_month,
    :day_of_month,
    :day_of_week,
    :frequency,
    :interval,
    :minute_of_hour,
    :monthly_option
  )

  attr_reader :nth_day_of_month # Setter is overridden below to coerce strings to integers

  # Highest frequency where DST transitions don't affect time projection.
  # Used by RruleAdapter to choose between RRule gem (daily+) and IceCube (hourly-).
  DST_THRESHOLD = new(frequency: 'DAILY').freeze

  validates :date_of_month, inclusion: { in: DATE_OF_MONTH_RANGE }, if: :date_of_month_option?
  validates :day_of_month, inclusion: { in: DAYS_OF_WEEK }, if: :nth_day_option?
  validates :day_of_week, inclusion: { in: DAYS_OF_WEEK }, allow_blank: true
  validates :frequency, presence: true, inclusion: { in: FREQUENCIES.keys }
  validates :interval, presence: true, numericality: { in: INTERVAL_RANGE }
  validates :minute_of_hour, numericality: { in: MINUTE_OF_HOUR_RANGE }, allow_blank: true
  validates :monthly_option, inclusion: { in: MONTHLY_OPTIONS }, allow_blank: true
  validates :nth_day_of_month, inclusion: { in: NTH_DAY_OF_MONTH.values }, if: :nth_day_option?

  class << self
    def from_rrule(rrule:)
      new(**attributes_from(parse_components(rrule)))
    end

    private

    # Parses "FREQ=DAILY;INTERVAL=1;BYDAY=MO…" into {"FREQ"=>"DAILY", "BYDAY"=>"MO", …}
    def parse_components(rrule)
      rrule.split(';').each_with_object({}) do |pair, hash|
        next if pair.blank?

        key, value = pair.split('=', 2)
        hash[key] = value
      end
    end

    def attributes_from(components)
      freq = components['FREQ']
      byday = components['BYDAY']
      bysetpos = components['BYSETPOS']&.to_i
      bymonthday = components['BYMONTHDAY']&.to_i

      {
        date_of_month: bymonthday,
        day_of_month: (byday if freq == 'MONTHLY'),
        day_of_week: (byday if freq == 'WEEKLY'),
        frequency: freq,
        interval: components['INTERVAL']&.to_i || 1,
        minute_of_hour: components['BYMINUTE']&.to_i,
        monthly_option: monthly_option_for(freq, bysetpos, byday, bymonthday),
        nth_day_of_month: bysetpos
      }
    end

    def monthly_option_for(freq, bysetpos, byday, bymonthday)
      return unless freq == 'MONTHLY'
      return 'NTH_DAY' if bysetpos && byday

      'DATE' if bymonthday
    end
  end

  def rrule
    day = day_of_week.presence || day_of_month.presence

    {
      'FREQ' => frequency,
      'INTERVAL' => interval,
      'BYDAY' => day.presence,
      'BYMONTHDAY' => date_of_month.presence,
      'BYMINUTE' => minute_of_hour.presence,
      'BYSETPOS' => nth_day_of_month.presence
    }.filter_map { |k, v| "#{k}=#{v}" if v.present? }.join(';')
  end

  def recurrence_statement
    frequency_noun = I18n.t(frequency, scope: 'recurrence_form.frequency_nouns').pluralize(interval)
    I18n.t('recurrence_form.recurrence_statement', interval:, frequency_noun:)
  end

  def nth_day_of_month=(value)
    @nth_day_of_month = value.presence&.to_i
  end

  def <=>(other)
    return super unless other.is_a?(self.class)

    FREQUENCIES.keys.index(frequency) <=> FREQUENCIES.keys.index(other.frequency)
  end

  private

  def date_of_month_option? = frequency == 'MONTHLY' && monthly_option == 'DATE'
  def nth_day_option? = frequency == 'MONTHLY' && monthly_option == 'NTH_DAY'
end
