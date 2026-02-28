# frozen_string_literal: true

require 'active_model'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/object/inclusion'
require 'active_support/core_ext/string/inflections'

require_relative 'version'
require_relative 'rrule_adapter'

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

  module ByDayValues
    SUNDAY = 'SU'
    MONDAY = 'MO'
    TUESDAY = 'TU'
    WEDNESDAY = 'WE'
    THURSDAY = 'TH'
    FRIDAY = 'FR'
    SATURDAY = 'SA'
  end

  # Order defines the sequence of days in the week
  BY_DAY_VALUES = [
    ByDayValues::SUNDAY,
    ByDayValues::MONDAY,
    ByDayValues::TUESDAY,
    ByDayValues::WEDNESDAY,
    ByDayValues::THURSDAY,
    ByDayValues::FRIDAY,
    ByDayValues::SATURDAY
  ].freeze

  # This order roughly matches the order that the options appear in the UI.
  module Frequencies
    YEARLY = 'YEARLY'
    MONTHLY = 'MONTHLY'
    WEEKLY = 'WEEKLY'
    DAILY = 'DAILY'
    HOURLY = 'HOURLY'
    MINUTELY = 'MINUTELY'
  end

  # Order matters here! Elements grow as frequency grows. I.e. Hertz times/second or times/day.
  # Used by Comparable#<=> to determine which adapter strategy RruleAdapter should use.
  FREQUENCY_VALUES = [
    Frequencies::YEARLY,
    Frequencies::MONTHLY,
    Frequencies::WEEKLY,
    Frequencies::DAILY,
    Frequencies::HOURLY,
    Frequencies::MINUTELY
  ].freeze

  DAYS_FROM_FREQUENCY = {
    Frequencies::YEARLY => 365,
    Frequencies::MONTHLY => 31,
    Frequencies::WEEKLY => 7,
    Frequencies::DAILY => 1,
    Frequencies::HOURLY => 1 / 24.0,
    Frequencies::MINUTELY => 1 / 24.0 / 60.0
  }.freeze

  module MonthlyOptions
    DATE = 'DATE'
    NTH_DAY = 'NTH_DAY'
  end

  MONTHLY_OPTIONS_VALUES = [MonthlyOptions::DATE, MonthlyOptions::NTH_DAY].freeze

  NTH_DAY_OF_MONTH = {
    first: 1,
    second: 2,
    third: 3,
    fourth: 4,
    last: -1,
    second_to_last: -2
  }.freeze

  DATE_OF_MONTH_RANGE = 1..28
  INTERVAL_RANGE = 1..12
  MINUTE_OF_HOUR_RANGE = 0..59

  DEFAULT_PARAMS = {
    frequency: Frequencies::DAILY,
    interval: 1
  }.freeze

  # Naming conventions for the monthly-related attributes:
  #
  #   date_of_month   — Numeric day of the month (1–28). Used with MonthlyOptions::DATE.
  #                     Maps to RRULE's BYMONTHDAY component. Named "date" because it's a
  #                     calendar date number, e.g. "the 15th of every month".
  #
  #   day_of_month    — Two-letter day-of-week string (SU/MO/TU/WE/TH/FR/SA).
  #                     Used with MonthlyOptions::NTH_DAY for rules like "the 2nd Tuesday
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

  attr_reader :nth_day_of_month # Setter is defined explicitly below

  DELEGATED_ATTRIBUTES = %i[
    date_of_month day_of_month day_of_week frequency
    interval minute_of_hour monthly_option nth_day_of_month
  ].freeze

  # Highest frequency where DST transitions don't affect time projection.
  # Used by RruleAdapter to choose between RRule gem (daily+) and IceCube (hourly-).
  DST_THRESHOLD = new(frequency: Frequencies::DAILY).freeze

  validates :date_of_month, numericality: { in: DATE_OF_MONTH_RANGE }, if: :date_of_month_option?
  validates :day_of_month, inclusion: { in: BY_DAY_VALUES }, if: :nth_day_option?
  validates :day_of_week, inclusion: { in: BY_DAY_VALUES }, allow_blank: true
  validates :frequency, presence: true, inclusion: { in: FREQUENCY_VALUES }
  validates :interval, presence: true, numericality: { in: INTERVAL_RANGE }
  validates :minute_of_hour, numericality: { in: MINUTE_OF_HOUR_RANGE }, allow_blank: true
  validates :monthly_option, inclusion: { in: MONTHLY_OPTIONS_VALUES }, allow_blank: true
  validates :nth_day_of_month, inclusion: { in: NTH_DAY_OF_MONTH.values }, if: :nth_day_option?

  def self.with_defaults
    new(DEFAULT_PARAMS)
  end

  def self.from_rrule(rrule:)
    new(**attributes_from(parse_components(rrule)))
  end

  # Parses "FREQ=DAILY;INTERVAL=1;BYDAY=MO" into {"FREQ"=>"DAILY", ...}
  private_class_method def self.parse_components(rrule)
    rrule.split(';').each_with_object({}) do |pair, hash|
      next if pair.blank?

      key, value = pair.split('=', 2)
      hash[key] = value
    end
  end

  private_class_method def self.attributes_from(components)
    freq = components['FREQ']
    byday = components['BYDAY']
    bysetpos = components['BYSETPOS']&.to_i
    bymonthday = components['BYMONTHDAY']&.to_i

    {
      date_of_month: bymonthday,
      day_of_month: (byday if freq == Frequencies::MONTHLY),
      day_of_week: (byday if freq == Frequencies::WEEKLY),
      frequency: freq,
      interval: components['INTERVAL']&.to_i || 1,
      minute_of_hour: components['BYMINUTE']&.to_i,
      monthly_option: monthly_option_for(freq, bysetpos, byday, bymonthday),
      nth_day_of_month: bysetpos
    }
  end

  private_class_method def self.monthly_option_for(freq, bysetpos, byday, bymonthday)
    return unless freq == Frequencies::MONTHLY
    return MonthlyOptions::NTH_DAY if bysetpos && byday

    MonthlyOptions::DATE if bymonthday
  end

  def rrule
    day = day_of_week.presence || day_of_month.presence

    components = {
      'FREQ' => frequency,
      'INTERVAL' => interval,
      'BYDAY' => day.presence,
      'BYMONTHDAY' => date_of_month.presence,
      'BYMINUTE' => minute_of_hour.presence,
      'BYSETPOS' => nth_day_of_month.presence
    }

    components.filter_map { |k, v| "#{k}=#{v}" if v.present? }.join(';')
  end

  def recurrence_statement
    frequency_noun = I18n.t(frequency, scope: 'recurrence_form.frequency_nouns').pluralize(interval)
    I18n.t('recurrence_form.recurrence_statement', interval:, frequency_noun:)
  end

  def recurrence_times(project_from:, project_to:, dt_start_at: nil)
    dt_start_at ||= project_from
    RruleAdapter.new(self, dt_start_at:, tzid: Time.zone.tzinfo.identifier)
                .times_between(project_from:, project_to:)
  end

  def nth_day_of_month=(value)
    @nth_day_of_month = value.presence&.to_i
  end

  def <=>(other)
    return super unless other.is_a?(self.class)

    FREQUENCY_VALUES.index(frequency) <=> FREQUENCY_VALUES.index(other.frequency)
  end

  def last_recurrence_time_before(dt_start_at:, end_at:)
    project_from = (DAYS_FROM_FREQUENCY[frequency] * interval).days.ago(end_at)
    recurrence_times(project_from:, project_to: end_at, dt_start_at:).last
  end

  private

  def date_of_month_option? = frequency == Frequencies::MONTHLY && monthly_option == MonthlyOptions::DATE

  def nth_day_option? = frequency == Frequencies::MONTHLY && monthly_option == MonthlyOptions::NTH_DAY
end
