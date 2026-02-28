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
    serialize :rrule, RecurrenceSerializer, default: Recurrence.with_defaults

    delegate :date_of_month, :date_of_month=,
             :day_of_week, :day_of_week=,
             :day_of_month, :day_of_month=,
             :frequency, :frequency=,
             :interval, :interval=,
             :minute_of_hour, :minute_of_hour=,
             :monthly_option, :monthly_option=,
             :nth_day_of_month, :nth_day_of_month=,
             :recurrence_statement, to: :rrule

    # This overrides the prepending model's `valid?` method to also apply the recurrence object's interval validation
    # and merge any errors into the including model's errors.
    #
    # NOTE: This is prepended so that the including model's validation is run first, and then the recurrence object's.
    # NOTE: Many concerns can all do this without interfering with each other-- i.e., it is open/closed.
    def valid?(context = nil)
      including_model_valid = super
      recurrence_valid = rrule.valid?
      errors.merge! rrule.errors

      including_model_valid && recurrence_valid
    end

    # Defines a method for each frequency that returns true if the recurrence's frequency matches the method name.
    # E.g., `sample_plan.yearly?` will return true if `sample_plan.frequency` is "YEARLY".
    Recurrence::FREQUENCY_VALUES.each do |frequency|
      define_method(:"#{frequency.downcase}?") { frequency == self.frequency }
    end
  end
end
