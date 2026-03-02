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

    delegate(*Recurrence::DELEGATED_ATTRIBUTES.flat_map { |attr| [attr, :"#{attr}="] },
             *Recurrence::FREQUENCIES.each_key.map { |freq| :"#{freq.downcase}?" },
             :recurrence_statement, to: :rrule)

    def recurrence_times(project_from:, project_to:, dt_start_at: nil)
      RruleAdapter.times_between(rrule, project_from:, project_to:, dt_start_at:)
    end

    def last_recurrence_time_before(dt_start_at:, end_at:)
      RruleAdapter.last_time_before(rrule, dt_start_at:, end_at:)
    end

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
  end
end
