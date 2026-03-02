# frozen_string_literal: true

require 'active_support/concern'

require_relative 'recurable/version'
require_relative 'recurable/recurrence'
require_relative 'recurable/rrule_utils'
require_relative 'recurable/array_inclusion_validator'
require_relative 'recurable/recurrence_serializer'
# A concern to be prepended by ActiveRecord models that persist an rrule string to the database. This concern gives them
# access to a Recurrence object (instead of an rrule string) which encapsulates user-friendly getters and
# setters for the rrule, as well as validation, display, and projection concerns.
module Recurable
  extend ActiveSupport::Concern

  prepended do
    include RruleUtils

    # This concern should only be used with a model that has an `rrule` string column.
    serialize :rrule, RecurrenceSerializer, default: Recurrence.new(frequency: 'DAILY', interval: 1)
    alias_attribute :recurrence, :rrule

    delegate(*Recurrence::ATTRIBUTES.flat_map { |attr| [attr, :"#{attr}="] },
             *Recurrence::FREQUENCIES.each_key.map { |freq| :"#{freq.downcase}?" },
             to: :rrule)

    validates :by_day, array_inclusion: { in: Recurrence::BYDAY_PATTERN }, allow_blank: true
    validates :by_month_day, array_inclusion: { in: Recurrence::DATE_OF_MONTH_RANGE }, if: :by_month_day_option?
    validates :by_set_pos, array_inclusion: { in: Recurrence::NTH_DAY_OF_MONTH.values }, if: :by_set_pos_option?
    validates :count, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true
    validates :day_of_year, array_inclusion: { in: Recurrence::DAY_OF_YEAR_RANGE }, allow_blank: true
    validates :frequency, presence: true, inclusion: { in: Recurrence::FREQUENCIES.keys }
    validates :hour_of_day, array_inclusion: { in: Recurrence::HOUR_OF_DAY_RANGE }, allow_blank: true
    validates :interval, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :minute_of_hour, array_inclusion: { in: Recurrence::MINUTE_OF_HOUR_RANGE }, allow_blank: true
    validates :month_of_year, array_inclusion: { in: Recurrence::MONTH_OF_YEAR_RANGE }, allow_blank: true
    validates :second_of_minute, array_inclusion: { in: Recurrence::SECOND_OF_MINUTE_RANGE }, allow_blank: true
    validates :week_of_year, array_inclusion: { in: Recurrence::WEEK_OF_YEAR_RANGE }, allow_blank: true
    validates :week_start, inclusion: { in: Recurrence::DAYS_OF_WEEK }, allow_blank: true
    validate :count_and_until_mutually_exclusive
  end

  private

  def count_and_until_mutually_exclusive
    errors.add(:base, 'COUNT and UNTIL are mutually exclusive') if count.present? && repeat_until.present?
  end
end
