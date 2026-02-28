# frozen_string_literal: true

require_relative 'recurrence'

# A serializer to be used by ActiveRecord models that persist an rrule string to the database. This serializer gives
# them access to a user-friendly Recurrence object (instead of a string) which encapsulates user-friendly getters and
# setters for the rrule, as well as validation and display concerns.
class RecurrenceSerializer
  # When a model loads its rrule string from the DB, it gets an instantiated
  # Recurrence object instead.
  def self.load(rrule)
    Recurrence.from_rrule(rrule:) if rrule.present?
  end

  # When a model saves its rrule (a Recurrence object) to the DB, it persists
  # the RRULE string instead.
  def self.dump(recurrence_instance)
    recurrence_instance&.rrule
  end
end
