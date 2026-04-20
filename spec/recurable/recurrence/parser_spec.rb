# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Recurrence::Parser do
  describe '.call' do
    it 'returns a hash shaped like Recurrence attributes' do
      attrs = described_class.call('FREQ=DAILY;INTERVAL=2')
      expect(attrs).to include(frequency: 'DAILY', interval: 2)
    end

    it 'defaults interval to 1 when absent' do
      expect(described_class.call('FREQ=DAILY')).to include(interval: 1)
    end

    it 'coerces COUNT to integer' do
      expect(described_class.call('FREQ=DAILY;COUNT=5')).to include(count: 5)
    end

    it 'leaves UNTIL as a raw string (Recurrence parses it during assignment)' do
      expect(described_class.call('FREQ=DAILY;UNTIL=20261231T235959Z'))
        .to include(repeat_until: '20261231T235959Z')
    end

    it 'splits comma-separated string lists' do
      expect(described_class.call('FREQ=WEEKLY;BYDAY=MO,WE,FR'))
        .to include(by_day: %w[MO WE FR])
    end

    it 'splits and coerces comma-separated integer lists' do
      expect(described_class.call('FREQ=MONTHLY;BYMONTHDAY=1,15,-1'))
        .to include(by_month_day: [1, 15, -1])
    end

    it 'omits keys for components that are absent from the RRULE' do
      expect(described_class.call('FREQ=DAILY').keys)
        .to contain_exactly(:frequency, :interval)
    end

    it 'tolerates a trailing semicolon' do
      expect(described_class.call('FREQ=DAILY;INTERVAL=1;'))
        .to include(frequency: 'DAILY', interval: 1)
    end

    it 'tolerates empty segments between semicolons' do
      expect(described_class.call('FREQ=DAILY;;INTERVAL=1'))
        .to include(frequency: 'DAILY', interval: 1)
    end

    it 'round-trips through Recurrence.new without raising' do
      attrs = described_class.call('FREQ=MONTHLY;INTERVAL=2;BYDAY=MO;BYSETPOS=-1')
      expect { Recurrence.new(**attrs) }.not_to raise_error
    end

    it 'does not crash on empty or garbage input' do
      expect(described_class.call('')).to eq(interval: 1)
      expect(described_class.call('   ')).to eq(interval: 1)
      expect(described_class.call('not an rrule')).to eq(interval: 1)
    end

    it 'silently drops unknown RRULE components' do
      expect(described_class.call('FREQ=DAILY;FOO=BAR'))
        .to eq(frequency: 'DAILY', interval: 1)
    end
  end
end
