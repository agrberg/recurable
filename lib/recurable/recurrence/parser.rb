# frozen_string_literal: true

class Recurrence
  # Parses an RFC 5545 RRULE string into a Recurrence attributes hash.
  class Parser
    def self.call(rrule) = new(rrule).call

    def initialize(rrule)
      @rrule = rrule
    end

    def call
      c = components
      {
        by_day: split_list(c['BYDAY']),
        by_month_day: split_int_list(c['BYMONTHDAY']),
        by_set_pos: split_int_list(c['BYSETPOS']),
        count: c['COUNT']&.to_i,
        day_of_year: split_int_list(c['BYYEARDAY']),
        frequency: c['FREQ'],
        hour_of_day: split_int_list(c['BYHOUR']),
        interval: c['INTERVAL']&.to_i || 1, # RFC 5545 §3.3.10: INTERVAL defaults to 1 when absent

        minute_of_hour: split_int_list(c['BYMINUTE']),
        month_of_year: split_int_list(c['BYMONTH']),
        repeat_until: c['UNTIL'],
        second_of_minute: split_int_list(c['BYSECOND']),
        week_of_year: split_int_list(c['BYWEEKNO']),
        week_start: c['WKST']
      }.compact
    end

    private

    # "FREQ=DAILY;INTERVAL=1;BYDAY=MO…" → {"FREQ"=>"DAILY", "BYDAY"=>"MO", …}
    def components
      @rrule.split(';').each_with_object({}) do |pair, hash|
        next if pair.strip.empty?

        key, value = pair.split('=', 2)
        hash[key] = value
      end
    end

    def split_list(csv)
      return unless csv

      list = csv.split(',')
      list unless list.empty?
    end

    def split_int_list(csv)
      split_list(csv)&.map(&:to_i)
    end
  end
end
