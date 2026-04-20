# frozen_string_literal: true

class Recurrence
  # Emits a Recurrence as an RFC 5545 RRULE string.
  class Formatter
    def self.call(recurrence) = new(recurrence).call

    def initialize(recurrence)
      @recurrence = recurrence
    end

    def call
      components.filter_map { |k, v| "#{k}=#{v}" unless v.nil? }.join(';')
    end

    private

    def components
      r = @recurrence
      {
        'FREQ' => r.frequency,
        'INTERVAL' => r.interval,
        'COUNT' => non_blank(r.count),
        'UNTIL' => format_until(r.repeat_until),
        'BYDAY' => join_list(r.by_day),
        'BYMONTHDAY' => join_list(r.by_month_day),
        'BYMONTH' => join_list(r.month_of_year),
        'BYHOUR' => join_list(r.hour_of_day),
        'BYMINUTE' => join_list(r.minute_of_hour),
        'BYSECOND' => join_list(r.second_of_minute),
        'BYYEARDAY' => join_list(r.day_of_year),
        'BYWEEKNO' => join_list(r.week_of_year),
        'BYSETPOS' => join_list(r.by_set_pos),
        'WKST' => non_blank(r.week_start)
      }
    end

    def non_blank(value)
      value unless value.nil? || value.to_s.strip.empty?
    end

    def join_list(array)
      non_blank(array&.join(','))
    end

    def format_until(time)
      time&.utc&.strftime('%Y%m%dT%H%M%SZ')
    end
  end
end
