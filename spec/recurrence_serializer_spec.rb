# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RecurrenceSerializer do
  describe '.load' do
    it 'returns nil for nil input' do
      expect(described_class.load(nil)).to be_nil
    end

    it 'returns nil for empty string input' do
      expect(described_class.load('')).to be_nil
    end

    it 'returns a Recurrence object for a valid rrule string' do
      result = described_class.load('FREQ=DAILY;INTERVAL=1')
      expect(result).to be_a(Recurrence)
      expect(result.frequency).to eq('DAILY')
      expect(result.interval).to eq(1)
    end
  end

  describe '.dump' do
    it 'returns nil for nil input' do
      expect(described_class.dump(nil)).to be_nil
    end

    it 'returns the rrule string for a Recurrence object' do
      recurrence = Recurrence.new(frequency: 'WEEKLY', interval: 2, by_day: %w[MO TU])
      expect(described_class.dump(recurrence)).to eq('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TU')
    end
  end

  describe 'round-trip' do
    it 'preserves data through dump then load' do
      original = Recurrence.new(frequency: 'MONTHLY', interval: 3, by_month_day: [15])
      rrule_string = described_class.dump(original)
      restored = described_class.load(rrule_string)

      expect(restored.frequency).to eq(original.frequency)
      expect(restored.interval).to eq(original.interval)
      expect(restored.by_month_day).to eq(original.by_month_day)
      expect(restored.to_rrule).to eq(original.to_rrule)
    end

    it 'preserves COUNT through round-trip' do
      original = Recurrence.new(frequency: 'DAILY', interval: 1, count: 10)
      restored = described_class.load(described_class.dump(original))
      expect(restored.count).to eq(10)
    end

    it 'preserves UNTIL through round-trip' do
      original = Recurrence.new(frequency: 'DAILY', interval: 1, repeat_until: Time.utc(2026, 12, 31, 23, 59, 59))
      restored = described_class.load(described_class.dump(original))
      expect(restored.repeat_until).to eq(Time.utc(2026, 12, 31, 23, 59, 59))
    end

    it 'preserves array attributes through round-trip' do
      original = Recurrence.new(frequency: 'YEARLY', interval: 1, month_of_year: [1, 6], day_of_year: [1, -1])
      restored = described_class.load(described_class.dump(original))
      expect(restored.month_of_year).to eq([1, 6])
      expect(restored.day_of_year).to eq([1, -1])
    end

    it 'preserves multi-value BYDAY through round-trip' do
      original = Recurrence.new(frequency: 'WEEKLY', interval: 1, by_day: %w[MO WE FR])
      restored = described_class.load(described_class.dump(original))
      expect(restored.by_day).to eq(%w[MO WE FR])
    end

    it 'preserves multi-value BYMONTHDAY through round-trip' do
      original = Recurrence.new(frequency: 'MONTHLY', interval: 1, by_month_day: [1, 15])
      restored = described_class.load(described_class.dump(original))
      expect(restored.by_month_day).to eq([1, 15])
    end

    it 'preserves ordinal BYDAY through round-trip' do
      original = Recurrence.new(frequency: 'YEARLY', interval: 1, by_day: ['+2TH'])
      restored = described_class.load(described_class.dump(original))
      expect(restored.by_day).to eq(['+2TH'])
    end
  end
end
