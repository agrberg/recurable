# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Recurrence::Formatter do
  describe '.call' do
    it 'emits only present values' do
      recurrence = Recurrence.new(frequency: 'DAILY', interval: 1, count: 5)
      expect(described_class.call(recurrence)).to eq('FREQ=DAILY;INTERVAL=1;COUNT=5')
    end

    it 'formats UNTIL as a UTC RRULE datetime' do
      recurrence = Recurrence.new(frequency: 'DAILY', interval: 1,
                                  repeat_until: Time.utc(2026, 12, 31, 23, 59, 59))
      expect(described_class.call(recurrence)).to include('UNTIL=20261231T235959Z')
    end

    it 'converts non-UTC UNTIL times to UTC before formatting' do
      Time.use_zone('America/New_York') do
        recurrence = Recurrence.new(frequency: 'DAILY', interval: 1,
                                    repeat_until: Time.zone.local(2026, 12, 31, 23, 59, 59))
        expect(described_class.call(recurrence)).to include('UNTIL=20270101T045959Z')
      end
    end

    it 'joins array attributes with commas' do
      recurrence = Recurrence.new(frequency: 'WEEKLY', interval: 1, by_day: %w[MO WE FR])
      expect(described_class.call(recurrence)).to eq('FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE,FR')
    end

    it 'omits array attributes that coerce to empty' do
      recurrence = Recurrence.new(frequency: 'DAILY', interval: 1, by_day: [])
      expect(described_class.call(recurrence)).to eq('FREQ=DAILY;INTERVAL=1')
    end

    it 'emits components in RFC 5545 canonical order' do
      recurrence = Recurrence.new(
        by_day: ['MO'], by_set_pos: [-1], count: 10, frequency: 'MONTHLY', interval: 2
      )
      expect(described_class.call(recurrence))
        .to eq('FREQ=MONTHLY;INTERVAL=2;COUNT=10;BYDAY=MO;BYSETPOS=-1')
    end
  end
end
