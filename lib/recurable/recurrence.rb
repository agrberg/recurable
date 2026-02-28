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

  ALLOWED_PARAMS = %i[
    day_of_month
    date_of_month
    day_of_week
    frequency
    interval
    minute_of_hour
    monthly_option
    nth_day_of_month
  ].freeze

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

  module RRuleComponents
    BYDAY = 'BYDAY'
    BYMINUTE = 'BYMINUTE'
    BYMONTHDAY = 'BYMONTHDAY'
    FREQ = 'FREQ'
    INTERVAL = 'INTERVAL'
    BYSETPOS = 'BYSETPOS'
  end

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
    new(
      date_of_month: extract_component_from_rrule(rrule:, component: RRuleComponents::BYMONTHDAY)&.to_i,
      day_of_month: day_of_month_from_rrule(rrule:),
      day_of_week: day_of_week_from_rrule(rrule:),
      frequency: extract_component_from_rrule(rrule:, component: RRuleComponents::FREQ),
      interval: extract_component_from_rrule(rrule:, component: RRuleComponents::INTERVAL)&.to_i || 1,
      minute_of_hour: extract_component_from_rrule(rrule:, component: RRuleComponents::BYMINUTE)&.to_i,
      monthly_option: monthly_option_from_rrule(rrule:),
      nth_day_of_month: nth_day_of_month_from_rrule(rrule:)
    )
  end

  # Private class methods
  class << self
    private

    def extract_component_from_rrule(rrule:, component:)
      rrule.split(';').find { _1.include?(component) }&.split('=')&.second
    end

    def monthly_option_from_rrule(rrule:)
      return MonthlyOptions::NTH_DAY if nth_day_of_month_from_rrule(rrule:) && day_of_month_from_rrule(rrule:)

      MonthlyOptions::DATE if date_of_month_from_rrule(rrule:)
    end

    def date_of_month_from_rrule(rrule:)
      extract_component_from_rrule(rrule:, component: RRuleComponents::BYMONTHDAY)&.to_i
    end

    def day_of_month_from_rrule(rrule:)
      return unless extract_component_from_rrule(rrule:, component: RRuleComponents::FREQ) == Frequencies::MONTHLY

      extract_component_from_rrule(rrule:, component: RRuleComponents::BYDAY)
    end

    def day_of_week_from_rrule(rrule:)
      return unless extract_component_from_rrule(rrule:, component: RRuleComponents::FREQ) == Frequencies::WEEKLY

      extract_component_from_rrule(rrule:, component: RRuleComponents::BYDAY)
    end

    def nth_day_of_month_from_rrule(rrule:)
      extract_component_from_rrule(rrule:, component: RRuleComponents::BYSETPOS)&.to_i
    end
  end

  def rrule
    [frequency_component, interval_component, by_day_component, by_month_day_component, by_minute_component,
     set_pos_component].compact_blank.join(';')
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

  def frequency_component = "#{RRuleComponents::FREQ}=#{frequency}"

  def interval_component = "#{RRuleComponents::INTERVAL}=#{interval}"

  def by_day_component
    day = day_of_week.presence || day_of_month.presence
    "#{RRuleComponents::BYDAY}=#{day}" if day.present?
  end

  def by_minute_component = ("#{RRuleComponents::BYMINUTE}=#{minute_of_hour}" if minute_of_hour.present?)

  def by_month_day_component = ("#{RRuleComponents::BYMONTHDAY}=#{date_of_month}" if date_of_month.present?)

  def set_pos_component = ("#{RRuleComponents::BYSETPOS}=#{nth_day_of_month}" if nth_day_of_month.present?)
end
