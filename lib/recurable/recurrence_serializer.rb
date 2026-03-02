# frozen_string_literal: true

require_relative 'recurrence'

# Serializes between RRULE strings and Recurrence objects. A Recurrence fully
# represents an RRULE — it can be constructed from the string and stored back as one.
class RecurrenceSerializer
  def self.load(rrule)
    Recurrence.from_rrule(rrule:) if rrule.present?
  end

  def self.dump(recurrence_instance) = recurrence_instance&.rrule
end
