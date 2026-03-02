# frozen_string_literal: true

require 'active_support/concern'

require_relative 'recurable/version'
require_relative 'recurable/recurrence'
require_relative 'recurable/rrule_adapter'
require_relative 'recurable/recurrence_serializer'
require_relative 'recurable/railtie' if defined?(Rails)

# A concern to be prepended by ActiveRecord models that persist an rrule string to the database. This concern gives them
# access to a Recurrence object (instead of an rrule string) which encapsulates user-friendly getters and
# setters for the rrule, as well as validation, display, and projection concerns.
module Recurable
  extend ActiveSupport::Concern

  prepended do
    # This concern should only be used with a model that has an `rrule` string column.
    serialize :rrule, RecurrenceSerializer, default: Recurrence.new(frequency: 'DAILY', interval: 1)

    delegate(*Recurrence::ATTRIBUTES.flat_map { |attr| [attr, :"#{attr}="] },
             *Recurrence::FREQUENCIES.each_key.map { |freq| :"#{freq.downcase}?" },
             to: :rrule)

    validates :date_of_month, inclusion: { in: Recurrence::DATE_OF_MONTH_RANGE }, if: :date_of_month_option?
    validates :day_of_month, inclusion: { in: Recurrence::DAYS_OF_WEEK }, if: :nth_day_option?
    validates :day_of_week, inclusion: { in: Recurrence::DAYS_OF_WEEK }, allow_blank: true
    validates :frequency, presence: true, inclusion: { in: Recurrence::FREQUENCIES.keys }
    validates :interval, presence: true, numericality: { in: Recurrence::INTERVAL_RANGE }
    validates :minute_of_hour, numericality: { in: Recurrence::MINUTE_OF_HOUR_RANGE }, allow_blank: true
    validates :monthly_option, inclusion: { in: Recurrence::MONTHLY_OPTIONS }, allow_blank: true
    validates :nth_day_of_month, inclusion: { in: Recurrence::NTH_DAY_OF_MONTH.values }, if: :nth_day_option?

    def recurrence_statement
      frequency_noun = I18n.t(frequency, scope: 'recurrence_form.frequency_nouns').pluralize(interval)
      I18n.t('recurrence_form.recurrence_statement', interval:, frequency_noun:)
    end

    def recurrence_times(project_from:, project_to:, dt_start_at: nil)
      RruleAdapter.times_between(rrule, project_from:, project_to:, dt_start_at:)
    end

    def last_recurrence_time_before(dt_start_at:, end_at:)
      RruleAdapter.last_time_before(rrule, dt_start_at:, end_at:)
    end

    private

    def date_of_month_option? = frequency == 'MONTHLY' && monthly_option == 'DATE'
    def nth_day_option? = frequency == 'MONTHLY' && monthly_option == 'NTH_DAY'
  end
end
